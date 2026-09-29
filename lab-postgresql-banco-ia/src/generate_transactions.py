"""
Banco Andino Colombia · Generador de datos sintéticos — LOTE 2 (transacciones)

Lee los CSV del lote 1 (data/lote1) y genera:
  - data/lote2/transaccion_financiera.csv
      exactamente 1.000.000 de transacciones POSTED (supuesto S5: incluye reversos
      y ajustes aprobados) + transacciones REJECTED y PENDING_APPROVAL adicionales
  - data/lote2/asiento_contable.csv
      2 líneas (débito y crédito) por cada transacción POSTED

Cómo se construye: simulación cronológica de 24 meses (2024-09-01 a 2026-08-31).
Cada solicitud se procesa en orden de tiempo con el saldo de ese momento, así que
las reglas se cumplen por construcción y luego se comprueban con SQL:
  RN-30 montos > 0 con 2 decimales      RN-31 saldo disponible + cupo de sobregiro
  RN-32/33 transferencia entre cuentas distintas y de la misma moneda
  RN-34 débitos solo desde ACTIVA       RN-35 créditos solo a ACTIVA o BLOQUEADA
  RN-36 dentro del periodo válido       RN-37 límite diario de retiro (vigente ese día)
  RN-38 clave de idempotencia única     RN-41/42/43 reversos (una vez, mismas reglas)
  RN-44 ajuste creado por cajero y aprobado por supervisor
  RN-45 rechazadas con motivo y sin asientos   RN-46/47 doble partida cuadrada
  RN-20 cuenta cerrada con saldo 0 (se traslada el saldo antes del cierre)
  RN-51 reversos registrados por SUPERVISOR    RN-54 usuarios internos ≠ titulares

Supuestos de datos (documentar en el informe):
  - Los saldos parten de 0 al inicio de la ventana (el histórico 2015-2024 no se simula).
  - Una cuenta que termina INACTIVA no tiene movimientos en los 180 días previos.
  - Distribuciones no uniformes: cola larga por cuenta, quincenas, diciembre,
    fines de semana más bajos, horas pico.

Reproducibilidad: SEED = 20260909 y una sola fuente aleatoria. Mismo lote 1 → mismos CSV.

Uso (desde la raíz del repositorio, después de src/generate_data.py):
    python src/generate_transactions.py
"""

from __future__ import annotations

import csv
import hashlib
import heapq
import math
import random
import uuid
from bisect import bisect_left, bisect_right
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from itertools import accumulate
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
SEED = 20260909
OBJETIVO_POSTED = 1_000_000
N_SOLICITUDES = 955_000         # solicitudes genéricas (calibrado para superar levemente el objetivo)
N_AJUSTES = 4_500
N_AJUSTES_PENDIENTES = 75

TZ = timezone(timedelta(hours=-5))
W0 = int(datetime(2024, 9, 1, tzinfo=TZ).timestamp())     # inicio de la ventana
W1 = int(datetime(2026, 9, 1, tzinfo=TZ).timestamp())     # fin (exclusivo)
DIA = 86_400
MARGEN = 60                                               # segundos de holgura en los bordes
DIAS_QUIETA_ANTES_DE_INACTIVAR = 180

ROOT = Path(__file__).resolve().parents[1]
IN = ROOT / "data" / "lote1"
OUT = ROOT / "data" / "lote2"

rng = random.Random(SEED)

CONSIGNACION, RETIRO, TRANSFERENCIA, DEBITO, CREDITO, AJUSTE, REVERSO = (
    "CONSIGNACION", "RETIRO", "TRANSFERENCIA", "DEBITO", "CREDITO", "AJUSTE", "REVERSO")
POSTED, REJECTED, PENDING = "POSTED", "REJECTED", "PENDING_APPROVAL"

PASIVO = {"AHORROS": "PAS_DEP_AHORROS", "CORRIENTE": "PAS_DEP_CORRIENTE",
          "NOMINA": "PAS_DEP_NOMINA", "EMPRESARIAL": "PAS_DEP_EMPRESARIAL"}

# Mezcla de solicitudes genéricas por tipo de cliente
TIPOS = [CONSIGNACION, RETIRO, TRANSFERENCIA, DEBITO, CREDITO]
MEZCLA = {"NATURAL": [20, 24, 24, 24, 8], "JURIDICA": [26, 6, 32, 22, 14]}
CUM_MEZCLA = {k: list(accumulate(v)) for k, v in MEZCLA.items()}

# Montos en pesos: mediana y dispersión (lognormal)
MEDIANA = {CONSIGNACION: 380_000, RETIRO: 200_000, TRANSFERENCIA: 170_000, DEBITO: 60_000,
           CREDITO: 300_000, AJUSTE: 85_000}
SIGMA = {CONSIGNACION: 1.0, RETIRO: 0.8, TRANSFERENCIA: 1.1, DEBITO: 1.0, CREDITO: 1.0, AJUSTE: 1.0}
FACTOR_JURIDICA = 6
COP_POR_USD = 4_000
SALARIO_MINIMO = 1_423_500
COMISIONES_COP = [4_500, 8_900, 12_500, 15_900, 23_800]

# Horas (pico en la mañana y a media tarde)
HORAS_OFICINA = {8: 6, 9: 10, 10: 13, 11: 14, 12: 10, 13: 8, 14: 10, 15: 12, 16: 11, 17: 5}
HORAS_DIGITAL = {0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 2, 6: 4, 7: 7, 8: 9, 9: 10, 10: 11, 11: 11,
                 12: 12, 13: 10, 14: 10, 15: 10, 16: 10, 17: 11, 18: 12, 19: 12, 20: 11,
                 21: 8, 22: 5, 23: 3}
CANAL_OFICINA = {CONSIGNACION, RETIRO, AJUSTE}

MOTIVO_FONDOS = "Fondos insuficientes"
MOTIVO_LIMITE = "Excede el límite diario de retiro"
MOTIVO_BLOQUEADA = "Cuenta bloqueada: no puede originar débitos"


# ---------------------------------------------------------------------------
# Utilidades de tiempo y dinero (tiempos en segundos epoch; dinero en centavos)
# ---------------------------------------------------------------------------
N_DIAS = (W1 - W0) // DIA
DIAS = [date(2024, 9, 1) + timedelta(days=i) for i in range(N_DIAS)]
DIA_TXT = [d.isoformat() for d in DIAS]


def peso_dia(i: int, d: date) -> float:
    w = [1.0, 0.95, 0.95, 1.0, 1.15, 0.7, 0.4][d.weekday()]
    ultimo = (date(d.year + (d.month == 12), d.month % 12 + 1, 1) - timedelta(days=1)).day
    if d.day in (1, 2, 15, 16) or d.day >= ultimo - 1:
        w *= 1.5                                   # quincenas y fin de mes
    elif d.day in (3, 14, 17):
        w *= 1.15
    w *= {12: 1.35, 1: 0.85, 6: 1.1}.get(d.month, 1.0)  # diciembre, enero, prima de junio
    return w * (1 + 0.08 * i / N_DIAS)             # crecimiento del banco


CUM_DIAS = list(accumulate(peso_dia(i, d) for i, d in enumerate(DIAS)))


def tabla_horas(h: dict[int, int]):
    horas = sorted(h)
    return horas, list(accumulate(h[x] for x in horas))


TABLA_OFICINA = tabla_horas(HORAS_OFICINA)
TABLA_DIGITAL = tabla_horas(HORAS_DIGITAL)


def epoch(txt: str) -> int:
    return int(datetime.fromisoformat(txt).timestamp())


def centavos(txt: str) -> int:
    entero, _, dec = txt.partition(".")
    return int(entero) * 100 + int((dec + "00")[:2])


def fmt_ts(t: int) -> str:
    d, s = divmod(t - W0, DIA)
    return f"{DIA_TXT[d]} {s // 3600:02d}:{s % 3600 // 60:02d}:{s % 60:02d}-05:00"


def fmt_monto(c: int) -> str:
    return f"{c // 100}.{c % 100:02d}"


def dentro(iv, t: int) -> bool:
    inicios, fines = iv
    i = bisect_right(inicios, t) - 1
    return i >= 0 and t < fines[i]


def muestrear_tiempo(iv, oficina: bool) -> int:
    """Momento dentro de los intervalos permitidos, con estacionalidad por día y hora."""
    inicios, fines = iv
    if len(inicios) == 1:
        s, e = inicios[0], fines[0]
    else:
        largos = list(accumulate(f - i for i, f in zip(inicios, fines)))
        k = bisect_left(largos, rng.random() * largos[-1])
        s, e = inicios[k], fines[k]
    d0, d1 = (s - W0) // DIA, (e - 1 - W0) // DIA
    lo = CUM_DIAS[d0 - 1] if d0 else 0.0
    hi = CUM_DIAS[d1]
    horas, cum_h = TABLA_OFICINA if oficina else TABLA_DIGITAL
    for _ in range(12):
        d = min(max(bisect_left(CUM_DIAS, lo + rng.random() * (hi - lo)), d0), d1)
        h = horas[bisect_left(cum_h, rng.random() * cum_h[-1])]
        t = W0 + d * DIA + h * 3600 + rng.randrange(3600)
        if s <= t < e:
            return t
    return rng.randrange(s, e)


# ---------------------------------------------------------------------------
# 1. Lectura del lote 1
# ---------------------------------------------------------------------------
def leer(nombre: str) -> list[dict]:
    with (IN / f"{nombre}.csv").open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


usuarios = leer("usuario")
rol_de = {int(r["usuario_id"]): r["rol_codigo"] for r in leer("usuario_rol")}
CAJEROS: dict[int, list[int]] = defaultdict(list)
SUPERVISORES: dict[int, list[int]] = defaultdict(list)
for u in usuarios:
    uid = int(u["usuario_id"])
    if u["oficina_id"] and rol_de[uid] == "CAJERO":
        CAJEROS[int(u["oficina_id"])].append(uid)
    elif u["oficina_id"] and rol_de[uid] == "SUPERVISOR":
        SUPERVISORES[int(u["oficina_id"])].append(uid)
OFICINAS = sorted(CAJEROS)

tipo_cliente = {int(c["cliente_id"]): c["tipo_cliente"] for c in leer("cliente")}

cuentas_csv = leer("cuenta")
N = len(cuentas_csv) + 1
PROD = [""] * N
MON = [""] * N
OFI = [0] * N
CUPO = [0] * N
ESTADO = [""] * N
LIM_INI = [0] * N
for c in cuentas_csv:
    a = int(c["cuenta_id"])
    PROD[a], MON[a], OFI[a], ESTADO[a] = c["producto_codigo"], c["moneda_codigo"], int(c["oficina_id"]), c["estado_cuenta"]
    CUPO[a] = centavos(c["cupo_sobregiro"])
    LIM_INI[a] = centavos(c["limite_retiro_diario"])

PRINCIPAL = [0] * N
for t in leer("titularidad_cuenta"):
    a = int(t["cuenta_id"])
    if t["rol_titular"] == "PRINCIPAL" and not PRINCIPAL[a]:
        PRINCIPAL[a] = int(t["cliente_id"])
JUR = [tipo_cliente.get(PRINCIPAL[a]) == "JURIDICA" for a in range(N)]

EVENTOS: dict[int, list[tuple]] = defaultdict(list)
for e in leer("evento_cuenta"):
    EVENTOS[int(e["cuenta_id"])].append((epoch(e["ocurrido_en"]), int(e["evento_id"]), e["tipo_evento"], e["estado_nuevo"]))

cambios = {int(c["evento_id"]): (centavos(c["valor_anterior"]), centavos(c["valor_nuevo"])) for c in leer("cambio_limite")}
LIM_CAMBIOS: dict[int, list[tuple[int, int]]] = defaultdict(list)
for a in range(1, N):
    for t, eid, tipo, _ in sorted(EVENTOS[a]):
        if tipo == "CAMBIO_LIMITE":
            ant, nuevo = cambios[eid]
            if not LIM_CAMBIOS[a]:
                LIM_INI[a] = ant               # límite vigente antes del primer cambio
            LIM_CAMBIOS[a].append((t, nuevo))


# ---------------------------------------------------------------------------
# 2. Intervalos en los que cada cuenta puede recibir (créditos) u originar (débitos)
# ---------------------------------------------------------------------------
def intervalos(a: int):
    evs = sorted(EVENTOS[a])
    cred, deb, bloq = [], [], []
    for i, (t, _, _, est) in enumerate(evs):
        fin = evs[i + 1][0] if i + 1 < len(evs) else W1
        s, e = max(t, W0) + MARGEN, min(fin, W1) - MARGEN
        if e - s < 3600:
            continue
        if est in ("ACTIVA", "BLOQUEADA"):
            cred.append((s, e))
        if est == "ACTIVA":
            deb.append((s, e))
        if est == "BLOQUEADA":
            bloq.append((s, e))
    # Sin movimientos en los 180 días previos a cada inactivación (cuenta dormida)
    quietos = [(t - DIAS_QUIETA_ANTES_DE_INACTIVAR * DIA, t) for t, _, tipo, _ in evs if tipo == "INACTIVACION"]

    def restar(lista):
        piezas = list(lista)
        for qs, qe in quietos:
            nuevas = []
            for x, y in piezas:
                if y <= qs or x >= qe:
                    nuevas.append((x, y))
                    continue
                if qs - MARGEN - x >= 3600:
                    nuevas.append((x, qs - MARGEN))
                if y - max(x, qe + MARGEN) >= 3600:
                    nuevas.append((max(x, qe + MARGEN), y))
            piezas = nuevas
        return piezas
    cred, deb, bloq = restar(cred), restar(deb), restar(bloq)

    traslado = None
    if ESTADO[a] == "CERRADA":
        if deb:
            s, e = deb[-1]
            traslado = e - rng.randint(0, min(5 * DIA, e - s - 2 * MARGEN))
            corte = traslado - MARGEN

            def recortar(lista):
                return [(x, min(y, corte)) for x, y in lista if min(y, corte) - x > 0]
            cred, deb, bloq = recortar(cred), recortar(deb), recortar(bloq)
        else:
            cred, deb, bloq = [], [], []

    def partir(lista):
        return ([x for x, _ in lista], [y for _, y in lista])
    return partir(cred), partir(deb), partir(bloq), traslado


CRE, DEB, BLOQ, TRASLADO = [None] * N, [None] * N, [None] * N, [None] * N
for a in range(N):
    CRE[a], DEB[a], BLOQ[a], TRASLADO[a] = intervalos(a) if a else (([], []), ([], []), ([], []), None)


def largo_dias(iv) -> float:
    return sum(f - i for i, f in zip(*iv)) / DIA


# Actividad por cuenta: cola larga (lognormal), empresas mucho más activas
ACTIVIDAD = [0.0] * N
for a in range(1, N):
    w = rng.lognormvariate(0, 1.2 if JUR[a] else 0.9) * (4 if JUR[a] else 1)
    w *= 1.3 if PROD[a] == "NOMINA" else 1.0
    w *= 0.5 if MON[a] == "USD" else 1.0
    ACTIVIDAD[a] = w
PESO = [ACTIVIDAD[a] * largo_dias(CRE[a]) for a in range(N)]
CUM_PESO = list(accumulate(PESO))

POOL = {}
for m in ("COP", "USD"):
    ids = [a for a in range(1, N) if MON[a] == m and PESO[a] > 0]
    POOL[m] = (ids, list(accumulate(PESO[a] for a in ids)))

PROPIAS: dict[tuple[int, str], list[int]] = defaultdict(list)
for a in range(1, N):
    if PESO[a] > 0:
        PROPIAS[(PRINCIPAL[a], MON[a])].append(a)


# ---------------------------------------------------------------------------
# 3. Montos
# ---------------------------------------------------------------------------
def paso(tipo: str, a: int) -> int:
    if MON[a] == "USD":
        return 1_000 if tipo == RETIRO else 1
    return {RETIRO: 1_000_000, CONSIGNACION: 100_000}.get(tipo, 100)


def minimo(tipo: str, a: int) -> int:
    if MON[a] == "USD":
        return 1_000 if tipo == RETIRO else 100
    return 2_000_000 if tipo == RETIRO else 100_000


def importe(tipo: str, a: int) -> int:
    pesos = MEDIANA[tipo] * math.exp(SIGMA[tipo] * rng.gauss(0, 1))
    if JUR[a]:
        pesos *= FACTOR_JURIDICA if tipo != AJUSTE else 4
    pesos = min(pesos, 3_000_000_000)
    c = pesos * 100 / (COP_POR_USD if MON[a] == "USD" else 1)
    p = paso(tipo, a)
    return max(minimo(tipo, a), int(round(c / p)) * p)


def truncar(tipo: str, a: int, c: float) -> int:
    p = paso(tipo, a)
    return int(c // p) * p


def limite_min_dia(a: int, d: int) -> int:
    """Límite más bajo vigente durante el día d (más estricto que el control SQL)."""
    ch = LIM_CAMBIOS[a]
    if not ch:
        return LIM_INI[a]
    ds, de = W0 + d * DIA, W0 + (d + 1) * DIA
    vigente, en_dia = LIM_INI[a], []
    for t, nuevo in ch:
        if t < ds:
            vigente = nuevo
        elif t < de:
            en_dia.append(nuevo)
    return min([vigente] + en_dia)


def cajero(a: int, otra_oficina: float = 0.0) -> int:
    of = rng.choice(OFICINAS) if rng.random() < otra_oficina else OFI[a]
    return rng.choice(CAJEROS[of])


def supervisor(a: int) -> int:
    return rng.choice(SUPERVISORES[OFI[a]])


# ---------------------------------------------------------------------------
# 4. Solicitudes (antes de validar saldos)
# ---------------------------------------------------------------------------
def generar_solicitudes() -> list[tuple]:
    sol: list[tuple] = []
    ids = list(range(N))

    # 4.1 Solicitudes genéricas repartidas por actividad × tiempo disponible
    for a in rng.choices(ids, cum_weights=CUM_PESO, k=N_SOLICITUDES):
        cm = CUM_MEZCLA["JURIDICA" if JUR[a] else "NATURAL"]
        tipo = TIPOS[bisect_right(cm, rng.random() * cm[-1])]
        if tipo in (RETIRO, TRANSFERENCIA, DEBITO):
            if DEB[a][0]:
                sol.append((muestrear_tiempo(DEB[a], tipo in CANAL_OFICINA), len(sol), "G", a, tipo))
                continue
            if BLOQ[a][0] and rng.random() < 0.15:
                sol.append((muestrear_tiempo(BLOQ[a], True), len(sol), "B", a, RETIRO if tipo == RETIRO else DEBITO))
                continue
            tipo = CONSIGNACION
        sol.append((muestrear_tiempo(CRE[a], tipo in CANAL_OFICINA), len(sol), "G", a, tipo))

    # 4.2 Intentos contra cuentas bloqueadas (rechazos RN-34)
    for a in range(1, N):
        if BLOQ[a][0] and rng.random() < 0.6:
            for _ in range(rng.randint(1, 3)):
                sol.append((muestrear_tiempo(BLOQ[a], True), len(sol), "B", a, rng.choice([RETIRO, DEBITO])))

    # 4.3 Nómina: pagos quincenales (día 15 y último día; si cae en fin de semana, el viernes)
    quincenas = []
    for i, d in enumerate(DIAS):
        siguiente = d + timedelta(days=1)
        if d.day == 15 or siguiente.month != d.month:
            j = i - max(0, d.weekday() - 4)
            quincenas.append(j)
    empleadores = [a for a in range(1, N) if JUR[a] and MON[a] == "COP"
                   and PROD[a] in ("CORRIENTE", "EMPRESARIAL") and DEB[a][0]]
    cum_emp = list(accumulate(ACTIVIDAD[a] for a in empleadores))
    for a in range(1, N):
        if PROD[a] != "NOMINA" or not CRE[a][0]:
            continue
        salario = max(SALARIO_MINIMO, rng.lognormvariate(math.log(2_300_000), 0.55))
        empleador = rng.choices(empleadores, cum_weights=cum_emp)[0] if rng.random() < 0.4 else 0
        for d in quincenas:
            t = W0 + d * DIA + rng.randrange(5 * 3600, 9 * 3600)
            if dentro(CRE[a], t) and rng.random() < 0.95:
                monto = int(round(salario / 2 * rng.uniform(0.98, 1.02))) * 100
                sol.append((t, len(sol), "N", a, empleador, monto))

    # 4.4 Ajustes (créditos 72 %, débitos 28 %)
    for a in rng.choices(ids, cum_weights=CUM_PESO, k=N_AJUSTES):
        if rng.random() < 0.72 or not DEB[a][0]:
            sol.append((muestrear_tiempo(CRE[a], True), len(sol), "A", a, "C"))
        else:
            sol.append((muestrear_tiempo(DEB[a], True), len(sol), "A", a, "D"))

    # 4.5 Traslado del saldo antes del cierre (la cuenta debe cerrar en 0, RN-20)
    for a in range(1, N):
        if TRASLADO[a]:
            sol.append((TRASLADO[a], len(sol), "D", a))

    sol.sort()
    return sol


# ---------------------------------------------------------------------------
# 5. Simulación cronológica
# ---------------------------------------------------------------------------
# Registro de transacción:
# [t_orden, tipo, estado, origen, destino, monto, t_sol, t_cont, creado, aprobado, reversa_idx, motivo, desc, sub]
TX: list[list] = []
SALDO = [0] * N
RETIROS_DIA: dict[tuple[int, int], int] = defaultdict(int)
NO_REMOVIBLE: set[int] = set()
REVERSADAS: set[int] = set()
CUENTAS_CON_RECHAZO: set[int] = set()


def contabilizar(tipo, origen, destino, monto, t, creado, sub="", aprobado=0, t_sol=None, rev=-1, desc=""):
    if origen:
        SALDO[origen] -= monto
    if destino:
        SALDO[destino] += monto
    if tipo == RETIRO:
        RETIROS_DIA[(origen, (t - W0) // DIA)] += monto
    TX.append([t, tipo, POSTED, origen, destino, monto, t - rng.randint(0, 3) if t_sol is None else t_sol,
               t, creado, aprobado, rev, "", desc, sub])
    return len(TX) - 1


def rechazar(tipo, origen, destino, monto, t, creado, motivo, rev=-1, desc="", t_sol=None):
    for c in (origen, destino):
        if c:
            CUENTAS_CON_RECHAZO.add(c)
    ts_ = t if t_sol is None else t_sol
    TX.append([ts_, tipo, REJECTED, origen, destino, monto, ts_, None, creado, 0, rev, motivo, desc, ""])


def elegir_destino(a: int, t: int) -> int:
    propias = PROPIAS[(PRINCIPAL[a], MON[a])]
    if len(propias) > 1 and rng.random() < 0.35:
        for x in rng.sample(propias, min(3, len(propias))):
            if x != a and dentro(CRE[x], t):
                return x
    ids, cum = POOL[MON[a]]
    for _ in range(6):
        x = ids[bisect_left(cum, rng.random() * cum[-1])]
        if x != a and dentro(CRE[x], t):
            return x
    return 0


def simular(solicitudes: list[tuple]) -> None:
    dinamicas: list[tuple] = []
    seq = len(solicitudes)
    i = 0
    while i < len(solicitudes) or dinamicas:
        if dinamicas and (i >= len(solicitudes) or dinamicas[0] < solicitudes[i]):
            s = heapq.heappop(dinamicas)
        else:
            s = solicitudes[i]
            i += 1
        t, _, clase, a = s[0], s[1], s[2], s[3]

        if clase == "G":
            tipo = s[4]
            if tipo in (CONSIGNACION, CREDITO):
                if not dentro(CRE[a], t):
                    continue
                if tipo == CREDITO and PROD[a] == "AHORROS" and SALDO[a] > 0 and rng.random() < 0.3:
                    monto = max(1, int(SALDO[a] * rng.uniform(0.0005, 0.002)))
                    contabilizar(CREDITO, 0, a, monto, t, cajero(a), sub="INT", desc="Abono de intereses")
                    continue
                idx = contabilizar(tipo, 0, a, importe(tipo, a), t, cajero(a, 0.15 if tipo == CONSIGNACION else 0))
                if tipo == CONSIGNACION and rng.random() < 0.012:
                    seq += 1
                    heapq.heappush(dinamicas, (t + rng.randint(600, 2 * DIA), seq, "R", idx))
                continue

            # Débitos: RETIRO, TRANSFERENCIA, DEBITO
            if not dentro(DEB[a], t):
                continue
            sub = ""
            destino = 0
            if tipo == TRANSFERENCIA:
                destino = elegir_destino(a, t)
                if not destino:
                    tipo = DEBITO
            if tipo == DEBITO and rng.random() < 0.12:
                sub = "COMI"
                monto = rng.choice(COMISIONES_COP) * 100 if MON[a] == "COP" else rng.randint(2, 6) * 100
                if SALDO[a] + CUPO[a] >= monto:
                    contabilizar(DEBITO, a, 0, monto, t, cajero(a), sub=sub, desc="Comisión cuota de manejo")
                continue
            disponible = SALDO[a] + CUPO[a]
            restante = 1 << 62
            if tipo == RETIRO:
                d = (t - W0) // DIA
                restante = limite_min_dia(a, d) - RETIROS_DIA.get((a, d), 0)
            pedido = importe(tipo, a)
            creado = cajero(a, 0.15 if tipo == RETIRO else 0)
            if rng.random() < (0.03 if tipo == RETIRO else 0.012):   # intento que excede a propósito
                if tipo == RETIRO and disponible > restante > 0 and rng.random() < 0.6:
                    pedido = max(pedido, truncar(tipo, a, restante * rng.uniform(1.1, 1.8)) + paso(tipo, a))
                else:
                    pedido = max(pedido, truncar(tipo, a, max(disponible, 0) * rng.uniform(1.1, 2.5)))
                if pedido > disponible:
                    rechazar(tipo, a, destino, pedido, t, creado, MOTIVO_FONDOS)
                elif pedido > restante:
                    rechazar(tipo, a, destino, pedido, t, creado, MOTIVO_LIMITE)
                else:
                    contabilizar(tipo, a, destino, pedido, t, creado)
                continue
            tope = min(disponible, restante)
            monto = pedido
            if pedido > tope:
                monto = truncar(tipo, a, tope * rng.uniform(0.3, 0.95)) if tope > 0 else 0
                if monto < minimo(tipo, a):
                    if rng.random() < 0.25:
                        rechazar(tipo, a, destino, pedido, t, creado,
                                 MOTIVO_FONDOS if pedido > disponible else MOTIVO_LIMITE)
                    continue
            idx = contabilizar(tipo, a, destino, monto, t, creado)
            if tipo == DEBITO and rng.random() < 0.04:
                seq += 1
                heapq.heappush(dinamicas, (t + rng.randint(2 * 3600, 12 * DIA), seq, "R", idx))

        elif clase == "B":
            rechazar(s[4], a, 0, importe(s[4], a), t, cajero(a), MOTIVO_BLOQUEADA)

        elif clase == "N":
            empleador, monto = s[4], s[5]
            if not dentro(CRE[a], t):
                continue
            if empleador and dentro(DEB[empleador], t) and SALDO[empleador] + CUPO[empleador] >= monto:
                contabilizar(TRANSFERENCIA, empleador, a, monto, t, cajero(empleador), desc="Pago de nómina")
            else:
                contabilizar(CREDITO, 0, a, monto, t, cajero(a), desc="Pago de nómina")

        elif clase == "A":
            sentido = s[4]
            monto = importe(AJUSTE, a)
            creado, aprobado = cajero(a), supervisor(a)
            t_sol = max(W0, t - rng.randint(15 * 60, 26 * 3600))
            if sentido == "C":
                if not dentro(CRE[a], t):
                    continue
                if rng.random() < 0.04:
                    rechazar(AJUSTE, 0, a, monto, t, creado, "Rechazado por el supervisor: soporte insuficiente",
                             desc="Ajuste a favor del cliente", t_sol=t_sol)
                else:
                    contabilizar(AJUSTE, 0, a, monto, t, creado, sub="C", aprobado=aprobado, t_sol=t_sol,
                                 desc="Ajuste a favor del cliente")
            elif dentro(DEB[a], t) and SALDO[a] + CUPO[a] >= monto:
                idx = contabilizar(AJUSTE, a, 0, monto, t, creado, sub="D", aprobado=aprobado, t_sol=t_sol,
                                   desc="Ajuste por abono duplicado")
                NO_REMOVIBLE.add(idx)

        elif clase == "D":
            if SALDO[a] > 0:
                idx = contabilizar(DEBITO, a, 0, SALDO[a], t, supervisor(a),
                                   desc="Traslado de saldo por cancelación de la cuenta")
                NO_REMOVIBLE.add(idx)
            elif SALDO[a] < 0:
                contabilizar(CREDITO, 0, a, -SALDO[a], t, supervisor(a),
                             desc="Cubrimiento de sobregiro para cancelación")

        elif clase == "R":
            o = TX[a]                                    # aquí "a" es el índice de la original
            if o[1] == DEBITO:
                c = o[3]
                if dentro(CRE[c], t):
                    contabilizar(REVERSO, 0, c, o[5], t, supervisor(c), rev=a, desc="Reverso de débito no reconocido")
                    REVERSADAS.add(a)
            else:                                        # CONSIGNACION: el reverso debita la cuenta
                c = o[4]
                if dentro(DEB[c], t):
                    if SALDO[c] + CUPO[c] >= o[5]:
                        contabilizar(REVERSO, c, 0, o[5], t, supervisor(c), rev=a, desc="Reverso de consignación errada")
                        REVERSADAS.add(a)
                    elif rng.random() < 0.5:
                        rechazar(REVERSO, c, 0, o[5], t, supervisor(c), "Fondos insuficientes para el reverso", rev=a)
                        REVERSADAS.add(a)
                elif dentro(CRE[c], t):                  # cuenta BLOQUEADA (RN-43)
                    rechazar(REVERSO, c, 0, o[5], t, supervisor(c), "Cuenta bloqueada: el reverso no puede debitarla", rev=a)
                    REVERSADAS.add(a)


# ---------------------------------------------------------------------------
# 6. Ajuste fino al objetivo exacto de POSTED y pendientes de aprobación
# ---------------------------------------------------------------------------
def ajustar_objetivo() -> set[int]:
    posted = sum(1 for x in TX if x[2] == POSTED)
    quitar: set[int] = set()
    if posted > OBJETIVO_POSTED:
        # Solo débitos simples de cuentas que no cierran y sin rechazos: quitarlos
        # únicamente sube saldos posteriores, así que ninguna regla se rompe.
        candidatos = [i for i, x in enumerate(TX)
                      if x[2] == POSTED and x[1] in (RETIRO, DEBITO) and x[13] == ""
                      and i not in NO_REMOVIBLE and i not in REVERSADAS
                      and not TRASLADO[x[3]] and x[3] not in CUENTAS_CON_RECHAZO]
        quitar = set(rng.sample(candidatos, posted - OBJETIVO_POSTED))
    elif posted < OBJETIVO_POSTED:
        faltan = OBJETIVO_POSTED - posted
        ids = [a for a in range(1, N) if PESO[a] > 0 and not TRASLADO[a] and a not in CUENTAS_CON_RECHAZO]
        for a in rng.choices(ids, weights=[PESO[a] for a in ids], k=faltan):
            t = muestrear_tiempo(CRE[a], True)
            contabilizar(CONSIGNACION, 0, a, importe(CONSIGNACION, a), t, cajero(a, 0.15))
    for _ in range(N_AJUSTES_PENDIENTES):
        ids, cum = POOL["COP"]
        a = ids[bisect_left(cum, rng.random() * cum[-1])]
        t = W1 - rng.randint(3600, 3 * DIA)
        if dentro(CRE[a], t):
            TX.append([t, AJUSTE, PENDING, 0, a, importe(AJUSTE, a), t, None, cajero(a), 0, -1, "",
                       "Ajuste a favor del cliente", "C"])
    return quitar


# ---------------------------------------------------------------------------
# 7. Escritura
# ---------------------------------------------------------------------------
def lineas(x: list, id_tx: int, id_de: dict[int, int]) -> list[tuple]:
    """Asientos (cuenta_contable, cuenta_id, naturaleza) de una transacción POSTED."""
    tipo, origen, destino, sub = x[1], x[3], x[4], x[13]
    if tipo == REVERSO:
        orig = TX[x[10]]
        return [(cc, cid, "C" if nat == "D" else "D") for cc, cid, nat in reversed(lineas(orig, 0, id_de))]
    if tipo == CONSIGNACION:
        return [("ACT_CAJA", 0, "D"), (PASIVO[PROD[destino]], destino, "C")]
    if tipo == RETIRO:
        return [(PASIVO[PROD[origen]], origen, "D"), ("ACT_CAJA", 0, "C")]
    if tipo == TRANSFERENCIA:
        return [(PASIVO[PROD[origen]], origen, "D"), (PASIVO[PROD[destino]], destino, "C")]
    if tipo == DEBITO:
        return [(PASIVO[PROD[origen]], origen, "D"), ("ING_COMISIONES" if sub == "COMI" else "ACT_COMPENSACION", 0, "C")]
    if tipo == CREDITO:
        return [("GAS_INTERESES" if sub == "INT" else "ACT_COMPENSACION", 0, "D"), (PASIVO[PROD[destino]], destino, "C")]
    if tipo == AJUSTE and sub == "C":
        return [("PAS_AJUSTES_PENDIENTES", 0, "D"), (PASIVO[PROD[destino]], destino, "C")]
    return [(PASIVO[PROD[origen]], origen, "D"), ("PAS_AJUSTES_PENDIENTES", 0, "C")]


def escribir(quitar: set[int]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    orden = sorted((i for i in range(len(TX)) if i not in quitar), key=lambda i: (TX[i][0], i))
    id_de = {i: n for n, i in enumerate(orden, start=1)}
    v = lambda x: "" if not x else x  # noqa: E731

    with (OUT / "transaccion_financiera.csv").open("w", encoding="utf-8", newline="") as ft, \
         (OUT / "asiento_contable.csv").open("w", encoding="utf-8", newline="") as fa:
        wt = csv.writer(ft, lineterminator="\n")
        wa = csv.writer(fa, lineterminator="\n")
        wt.writerow(["transaccion_id", "tipo_codigo", "estado_codigo", "cuenta_origen_id", "cuenta_destino_id",
                     "monto", "idempotency_key", "transaccion_reversada_id", "descripcion", "fecha_solicitud",
                     "fecha_contabilizacion", "fecha_contable", "creado_por", "aprobado_por", "motivo_rechazo"])
        wa.writerow(["transaccion_id", "linea", "cuenta_contable_codigo", "cuenta_id", "naturaleza", "valor",
                     "registrado_en"])
        for i in orden:
            x = TX[i]
            n = id_de[i]
            clave = uuid.UUID(int=rng.getrandbits(128), version=4)
            t_cont = x[7]
            wt.writerow([n, x[1], x[2], v(x[3]), v(x[4]), fmt_monto(x[5]), clave,
                         id_de[x[10]] if x[10] >= 0 else "", x[12], fmt_ts(x[6]),
                         fmt_ts(t_cont) if t_cont else "",
                         DIA_TXT[(t_cont - W0) // DIA] if t_cont else "",
                         x[8], v(x[9]), x[11]])
            if x[2] == POSTED:
                reg = fmt_ts(t_cont)
                for k, (cc, cid, nat) in enumerate(lineas(x, n, id_de), start=1):
                    wa.writerow([n, k, cc, v(cid), nat, fmt_monto(x[5]), reg])


def main() -> None:
    solicitudes = generar_solicitudes()
    simular(solicitudes)
    quitar = ajustar_objetivo()
    escribir(quitar)

    vivas = [x for i, x in enumerate(TX) if i not in quitar]
    por_estado = Counter(x[2] for x in vivas)
    por_tipo = Counter((x[1], x[2]) for x in vivas)
    print(f"Semilla: {SEED}")
    print(f"Solicitudes simuladas: {len(solicitudes):,} · removidas para el objetivo: {len(quitar):,}")
    for estado, n in sorted(por_estado.items()):
        print(f"  {estado:<18}{n:>10,}")
    for (tipo, estado), n in sorted(por_tipo.items()):
        print(f"  {tipo:<14}{estado:<18}{n:>10,}")
    print(f"{'archivo':<28}{'filas':>10}  {'MB':>7}  sha256")
    for ruta in sorted(OUT.glob("*.csv")):
        filas = sum(1 for _ in ruta.open(encoding="utf-8")) - 1
        huella = hashlib.sha256(ruta.read_bytes()).hexdigest()[:16]
        print(f"{ruta.name:<28}{filas:>10,}  {ruta.stat().st_size / 1e6:>7.1f}  {huella}")


if __name__ == "__main__":
    main()
