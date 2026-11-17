"""
Banco Andino Colombia · Generador de datos sintéticos — LOTE 1

Genera, en archivos CSV, los datos base del laboratorio:
  - Muestra de departamentos y municipios (códigos DIVIPOLA oficiales)
  - Oficinas y usuarios internos (cajeros, supervisores, auditores, administradores)
  - 10.000 clientes (8.500 personas naturales y 1.500 personas jurídicas)
  - 50.000 cuentas: 1 cuenta base por cliente + 40.000 adicionales con cola larga
    (pocos clientes, sobre todo empresas, con muchas cuentas)
  - Titularidades, eventos del ciclo de vida y cambios de límite

Reglas respetadas (ver docs/01_especificacion.md):
  RN-01 documento único · RN-02 un subtipo por cliente · RN-03 documento según tipo
  RN-04 dígito de verificación del NIT · RN-07 municipio ↔ departamento
  RN-08 titulares naturales con 18 años o más · RN-11 número de cuenta de 11 dígitos
  RN-13 un titular principal · RN-14/15 producto según tipo de cliente
  RN-16 máximo de titulares · RN-17 sobregiro solo en CORRIENTE
  RN-21 cierre posterior a apertura · RN-23 primer evento CREACION
  RN-24 transiciones válidas · RN-25 estado = último evento · RN-27 cambio de límite
  RN-28 desbloqueo, cierre y cambio de límite por SUPERVISOR · RN-29 bloqueo con motivo
  RN-48 saldo 0 (todavía no hay transacciones ni asientos) · RN-54 usuarios ≠ titulares

Reproducibilidad: SEED = 20260909, una sola fuente aleatoria (random.Random) y
Faker con semilla propia. Mismas versiones de requirements.txt → mismos CSV.

Datos 100 % sintéticos: nombres de Faker, documentos en rangos inventados,
correos en el dominio reservado example.com.

Uso (desde la raíz del repositorio):
    python src/generate_data.py
"""

from __future__ import annotations

import csv
import hashlib
import random
import unicodedata
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

from faker import Faker

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
SEED = 20260909
N_CLIENTES = 10_000
N_JURIDICAS = 1_500                      # 15 %
N_CUENTAS = 50_000
TOPE_CUENTAS_NATURAL = 12
TOPE_CUENTAS_JURIDICA = 300
FECHA_INICIO = date(2015, 1, 1)          # vinculaciones históricas
INICIO_VENTANA = date(2024, 9, 1)        # inicio de la ventana de 24 meses
FECHA_CORTE = date(2026, 8, 31)          # último día con datos
TZ = timezone(timedelta(hours=-5))       # Colombia (UTC-5, sin horario de verano)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "lote1"

rng = random.Random(SEED)
fake = Faker("es_CO")
fake.seed_instance(SEED)

# ---------------------------------------------------------------------------
# Geografía: muestra de la DIVIPOLA (DANE). Pesos = población APROXIMADA en
# miles de habitantes, usados solo para que la distribución no sea uniforme.
# Para producción, cargar la DIVIPOLA completa desde datos.gov.co.
# ---------------------------------------------------------------------------
DEPARTAMENTOS = {
    "05": "Antioquia", "08": "Atlántico", "11": "Bogotá, D.C.", "13": "Bolívar",
    "15": "Boyacá", "17": "Caldas", "18": "Caquetá", "19": "Cauca", "20": "Cesar",
    "23": "Córdoba", "25": "Cundinamarca", "27": "Chocó", "41": "Huila",
    "44": "La Guajira", "47": "Magdalena", "50": "Meta", "52": "Nariño",
    "54": "Norte de Santander", "63": "Quindío", "66": "Risaralda", "68": "Santander",
    "70": "Sucre", "73": "Tolima", "76": "Valle del Cauca", "81": "Arauca",
    "85": "Casanare", "86": "Putumayo",
    "88": "Archipiélago de San Andrés, Providencia y Santa Catalina",
    "91": "Amazonas", "94": "Guainía", "95": "Guaviare", "97": "Vaupés", "99": "Vichada",
}

MUNICIPIOS = [  # (código DIVIPOLA, nombre, peso aproximado)
    ("11001", "Bogotá, D.C.", 7900),
    ("05001", "Medellín", 2600), ("05088", "Bello", 560), ("05360", "Itagüí", 290),
    ("05266", "Envigado", 240), ("05615", "Rionegro", 130),
    ("76001", "Santiago de Cali", 2280), ("76520", "Palmira", 360),
    ("76109", "Buenaventura", 320), ("76834", "Tuluá", 220),
    ("08001", "Barranquilla", 1300), ("08758", "Soledad", 700),
    ("13001", "Cartagena de Indias", 1060), ("13430", "Magangué", 140),
    ("54001", "San José de Cúcuta", 790), ("68001", "Bucaramanga", 620),
    ("68276", "Floridablanca", 330), ("73001", "Ibagué", 550),
    ("50001", "Villavicencio", 560), ("47001", "Santa Marta", 540),
    ("20001", "Valledupar", 530), ("23001", "Montería", 510),
    ("66001", "Pereira", 480), ("66170", "Dosquebradas", 230),
    ("17001", "Manizales", 450), ("17873", "Villamaría", 70),
    ("17174", "Chinchiná", 55), ("17380", "La Dorada", 80),
    ("52001", "Pasto", 390), ("41001", "Neiva", 370), ("19001", "Popayán", 330),
    ("63001", "Armenia", 300), ("70001", "Sincelejo", 300), ("44001", "Riohacha", 290),
    ("15001", "Tunja", 180), ("15238", "Duitama", 125), ("15759", "Sogamoso", 120),
    ("18001", "Florencia", 180), ("85001", "Yopal", 180),
    ("25175", "Chía", 150), ("25269", "Facatativá", 150), ("25126", "Cajicá", 90),
    ("27001", "Quibdó", 130), ("81001", "Arauca", 95),
    ("95001", "San José del Guaviare", 70), ("86001", "Mocoa", 60),
    ("88001", "San Andrés", 60), ("91001", "Leticia", 50), ("94001", "Inírida", 30),
    ("97001", "Mitú", 30), ("99001", "Puerto Carreño", 20),
]

SUFIJOS_OFICINA = [
    "Centro", "Norte", "Sur", "Oriente", "Occidente", "Principal", "Plaza Mayor",
    "Avenida Principal", "Terminal", "Aeropuerto", "Zona Industrial", "Universidad",
    "Parque Central", "Estadio", "Zona Franca", "Mercado", "Salitre", "Cedritos",
    "Chapinero", "Usaquén",
]

# ---------------------------------------------------------------------------
# Productos y parámetros (coherentes con core.producto)
# ---------------------------------------------------------------------------
PRODUCTOS_NATURAL = (["AHORROS", "NOMINA", "CORRIENTE"], [60, 25, 15])
PRODUCTOS_JURIDICA = (["CORRIENTE", "EMPRESARIAL", "AHORROS"], [45, 40, 15])
# Cuentas adicionales (después de la cuenta base)
PRODUCTOS_NATURAL_EXTRA = (["AHORROS", "CORRIENTE", "NOMINA"], [65, 30, 5])
PRODUCTOS_JURIDICA_EXTRA = (["EMPRESARIAL", "CORRIENTE", "AHORROS"], [50, 40, 10])
PREFIJO_CUENTA = {"AHORROS": "10", "CORRIENTE": "20", "NOMINA": "30", "EMPRESARIAL": "40"}
LIMITE_COP = {"AHORROS": 3_000_000, "NOMINA": 2_000_000, "CORRIENTE": 10_000_000, "EMPRESARIAL": 50_000_000}
LIMITE_USD = {"AHORROS": 1_000, "EMPRESARIAL": 15_000}

ESTADOS_FINALES = (["ACTIVA", "INACTIVA", "BLOQUEADA", "CERRADA"], [85, 6, 4, 5])
MOTIVOS_BLOQUEO = [
    "Solicitud del cliente", "Sospecha de fraude", "Orden de embargo",
    "Documentación desactualizada", "Pérdida de tarjeta débito",
]

CIIU = ["4711", "1081", "4111", "4520", "4923", "5611", "6201", "6920", "7020", "8621"]
GIROS = ["Logística", "Soluciones", "Ingeniería", "Construcciones", "Distribuciones",
         "Consultores", "Alimentos", "Transportes", "Tecnología", "Servicios Médicos"]


# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
def slug(texto: str) -> str:
    """Minúsculas sin tildes ni espacios (para login y correos)."""
    base = unicodedata.normalize("NFKD", texto).encode("ascii", "ignore").decode()
    return "".join(ch for ch in base.lower() if ch.isalnum())


def dv_nit(nit: str) -> int:
    """Dígito de verificación del NIT (módulo 11 DIAN); igual a ref.fn_dv_nit."""
    pesos = [3, 7, 13, 17, 19, 23, 29, 37, 41, 43, 47, 53, 59, 67, 71]
    s = sum(int(d) * pesos[i] for i, d in enumerate(reversed(nit)))
    r = s % 11
    return r if r in (0, 1) else 11 - r


def dia_entre(a: date, b: date) -> date:
    """Día aleatorio entre a y b (incluidos)."""
    return a + timedelta(days=rng.randint(0, (b - a).days))


def hora_habil(d: date) -> datetime:
    """Momento aleatorio en horario de oficina (8:00–16:59)."""
    return datetime.combine(d, time(rng.randint(8, 16), rng.randint(0, 59), rng.randint(0, 59)), TZ)


def ts(v: datetime | None) -> str:
    return "" if v is None else v.isoformat(sep=" ")


def escribir_csv(nombre: str, encabezado: list[str], filas: list[tuple]) -> None:
    ruta = OUT / nombre
    with ruta.open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(encabezado)
        for fila in filas:
            w.writerow(["" if v is None else v for v in fila])


# ---------------------------------------------------------------------------
# 1. Geografía y oficinas
# ---------------------------------------------------------------------------
def generar_geografia():
    codigos_dpto = sorted({m[0][:2] for m in MUNICIPIOS})
    departamentos = [(c, DEPARTAMENTOS[c]) for c in codigos_dpto]
    municipios = [(cod, cod[:2], nombre) for cod, nombre, _ in MUNICIPIOS]

    oficinas = []                      # (oficina_id, codigo, nombre, municipio)
    oficinas_por_municipio: dict[str, list[int]] = {}
    for cod, nombre, peso in MUNICIPIOS:
        n = min(20, max(1, round(peso / 400)))
        for k in range(n):
            oficina_id = len(oficinas) + 1
            nombre_of = f"Oficina {nombre}" if n == 1 else f"Oficina {nombre} {SUFIJOS_OFICINA[k]}"
            oficinas.append((oficina_id, f"OF{oficina_id:04d}", nombre_of, cod))
            oficinas_por_municipio.setdefault(cod, []).append(oficina_id)
    return departamentos, municipios, oficinas, oficinas_por_municipio


# ---------------------------------------------------------------------------
# 2. Usuarios internos
# ---------------------------------------------------------------------------
def generar_usuarios(oficinas):
    creado = datetime(2014, 12, 1, 9, 0, 0, tzinfo=TZ)
    plan = [("ADMIN_SEGURIDAD", None)] * 2 + [("AUDITOR", None)] * 6
    for oficina_id, *_ in oficinas:
        plan += [("SUPERVISOR", oficina_id), ("CAJERO", oficina_id), ("CAJERO", oficina_id)]

    documentos = rng.sample(range(70_000_000, 80_000_000), len(plan))   # CC de 8 dígitos
    usuarios, roles, logins = [], [], {}
    cajeros: dict[int, list[int]] = {}
    supervisores: dict[int, list[int]] = {}

    for i, (rol, oficina_id) in enumerate(plan):
        usuario_id = i + 1
        nombre, apellido = fake.first_name(), fake.last_name()
        base = (slug(nombre)[:1] + slug(apellido)) or "usuario"
        logins[base] = logins.get(base, 0) + 1
        login = base if logins[base] == 1 else f"{base}{logins[base]}"
        if len(login) < 4:
            login = f"{login}{usuario_id:04d}"
        usuarios.append((usuario_id, login, "CC", str(documentos[i]), nombre,
                         f"{apellido} {fake.last_name()}", oficina_id, "ACTIVO", ts(creado)))
        asignado_por = None if usuario_id == 1 else 1        # el primer admin es la carga inicial
        roles.append((usuario_id, rol, ts(creado), None, asignado_por))
        if rol == "CAJERO":
            cajeros.setdefault(oficina_id, []).append(usuario_id)
        elif rol == "SUPERVISOR":
            supervisores.setdefault(oficina_id, []).append(usuario_id)
    return usuarios, roles, cajeros, supervisores


# ---------------------------------------------------------------------------
# 3. Clientes
# ---------------------------------------------------------------------------
def meses(desde: date, hasta: date) -> list[date]:
    out, d = [], desde.replace(day=1)
    while d <= hasta:
        out.append(d)
        d = (d.replace(day=28) + timedelta(days=4)).replace(day=1)
    return out


def fechas_vinculacion(n: int) -> list[date]:
    """60 % antes de la ventana y 40 % dentro, con crecimiento mes a mes."""
    hist = meses(FECHA_INICIO, INICIO_VENTANA - timedelta(days=1))
    vent = meses(INICIO_VENTANA, FECHA_CORTE)
    w_hist = [1 + 0.02 * k for k in range(len(hist))]
    w_vent = [1 + 0.03 * k for k in range(len(vent))]
    pesos = [0.60 * w / sum(w_hist) for w in w_hist] + [0.40 * w / sum(w_vent) for w in w_vent]
    elegidos = rng.choices(hist + vent, weights=pesos, k=n)

    fechas = []
    for m in elegidos:
        fin_mes = (m.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
        d = dia_entre(m, min(fin_mes, FECHA_CORTE))
        if d.weekday() == 6:                                  # domingo → lunes
            d += timedelta(days=1)
        fechas.append(min(d, FECHA_CORTE))
    return sorted(fechas)


def generar_clientes():
    vinculaciones = fechas_vinculacion(N_CLIENTES)
    indices_juridicas = sorted(rng.sample(range(N_CLIENTES), N_JURIDICAS))
    es_juridica = [False] * N_CLIENTES
    for i in indices_juridicas:
        es_juridica[i] = True

    municipios = [m[0] for m in MUNICIPIOS]
    pesos_mun = [m[2] for m in MUNICIPIOS]

    n_nat = N_CLIENTES - N_JURIDICAS
    cc = iter(rng.sample(range(1_000_000_000, 1_300_000_000), n_nat))
    ce = iter(rng.sample(range(100_000, 1_000_000), n_nat))
    ppt = iter(rng.sample(range(1_000_000, 10_000_000), n_nat))
    nits = iter(rng.sample(range(960_000_000, 990_000_000), N_JURIDICAS))
    pasaportes_usados: list[str] = []

    clientes, naturales, juridicas = [], [], []
    for i in range(N_CLIENTES):
        cliente_id = i + 1
        vinc = vinculaciones[i]
        municipio = rng.choices(municipios, weights=pesos_mun)[0]
        telefono = "3" + f"{rng.randint(0, 999_999_999):09d}"

        if es_juridica[i]:
            nit = str(next(nits))
            ap1, ap2 = fake.last_name(), fake.last_name()
            sufijo = rng.choices(["S.A.S.", "S.A.", "Ltda."], weights=[80, 12, 8])[0]
            patron = rng.randint(1, 3)
            if patron == 1:
                razon = f"Inversiones {ap1} {sufijo}"
            elif patron == 2:
                razon = f"Comercializadora {ap1} y {ap2} {sufijo}"
            else:
                razon = f"{ap1} {rng.choice(GIROS)} {sufijo}"
            clientes.append((cliente_id, "JURIDICA", "NIT", nit, dv_nit(nit), municipio, "ACTIVO",
                             vinc.isoformat(), f"contacto{cliente_id}@example.com", telefono))
            constitucion = vinc - timedelta(days=rng.randint(180, 30 * 365))
            juridicas.append((cliente_id, razon, constitucion.isoformat(), rng.choice(CIIU)))
        else:
            tipo = rng.choices(["CC", "CE", "PPT", "PA"], weights=[95, 3, 1.5, 0.5])[0]
            if tipo == "CC":
                numero = str(next(cc))
            elif tipo == "CE":
                numero = str(next(ce))
            elif tipo == "PPT":
                numero = str(next(ppt))
            else:
                while True:
                    numero = "".join(rng.choice("ABCDEFGHJKLMNPRSTUVWXYZ") for _ in range(2)) + f"{rng.randint(0, 9_999_999):07d}"
                    if numero not in pasaportes_usados:
                        pasaportes_usados.append(numero)
                        break
            nombre = fake.first_name()
            nombres = nombre if rng.random() < 0.6 else f"{nombre} {fake.first_name()}"
            ap1 = fake.last_name()
            apellidos = f"{ap1} {fake.last_name()}"
            edad = int(rng.triangular(18, 80, 32))
            nacimiento = vinc - timedelta(days=int(edad * 365.25) + rng.randint(1, 364))
            email = None if rng.random() < 0.08 else f"{slug(nombre)}.{slug(ap1)}{cliente_id}@example.com"
            clientes.append((cliente_id, "NATURAL", tipo, numero, None, municipio, "ACTIVO",
                             vinc.isoformat(), email, telefono))
            naturales.append((cliente_id, nombres, apellidos, nacimiento.isoformat()))
    return clientes, naturales, juridicas


# ---------------------------------------------------------------------------
# 4. Cuentas: plan de 50.000 cuentas (10.000 base + 40.000 adicionales)
# ---------------------------------------------------------------------------
def planear_cuentas(clientes):
    """Decide cuántas cuentas tiene cada cliente, su producto y su fecha de apertura.

    - Cada cliente tiene 1 cuenta base, abierta al vincularse.
    - Las 40.000 adicionales se reparten con cola larga: pesos lognormales,
      4 veces mayores para personas jurídicas (pocas empresas con muchas cuentas).
    - Topes: 12 cuentas por persona natural, 300 por persona jurídica.
    - Una persona natural tiene como máximo una cuenta de nómina.
    """
    n = len(clientes)
    juridica = [c[1] == "JURIDICA" for c in clientes]
    pesos = [rng.lognormvariate(0, 1.2) * 4 if juridica[i] else rng.lognormvariate(0, 0.9) for i in range(n)]
    tope = [TOPE_CUENTAS_JURIDICA - 1 if juridica[i] else TOPE_CUENTAS_NATURAL - 1 for i in range(n)]

    extra = [0] * n
    pendientes = N_CUENTAS - n
    while pendientes > 0:
        elegibles = [i for i in range(n) if extra[i] < tope[i]]
        for i in rng.choices(elegibles, weights=[pesos[i] for i in elegibles], k=pendientes):
            extra[i] += 1
        pendientes = 0
        for i in range(n):
            if extra[i] > tope[i]:
                pendientes += extra[i] - tope[i]
                extra[i] = tope[i]

    plan = []                                   # (fecha_apertura, cliente_id, es_base, producto)
    for i, cli in enumerate(clientes):
        cliente_id, tipo_cliente, *_ = cli
        vinc = date.fromisoformat(cli[7])
        productos, pesos_p = PRODUCTOS_JURIDICA if juridica[i] else PRODUCTOS_NATURAL
        base = rng.choices(productos, weights=pesos_p)[0]
        plan.append((min(vinc + timedelta(days=rng.randint(0, 3)), FECHA_CORTE), cliente_id, True, base))
        tiene_nomina = base == "NOMINA"
        for _ in range(extra[i]):
            if juridica[i]:
                producto = rng.choices(*PRODUCTOS_JURIDICA_EXTRA)[0]
            else:
                producto = rng.choices(*PRODUCTOS_NATURAL_EXTRA)[0]
                if producto == "NOMINA":
                    if tiene_nomina:
                        producto = "AHORROS"
                    tiene_nomina = True
            plan.append((dia_entre(vinc, FECHA_CORTE), cliente_id, False, producto))

    plan.sort(key=lambda p: (p[0], p[1], not p[2]))          # cuenta_id en orden cronológico
    return plan


# ---------------------------------------------------------------------------
# 5. Cuentas, titularidad y eventos
# ---------------------------------------------------------------------------
def generar_cuentas(clientes, oficinas_por_municipio, cajeros, supervisores):
    plan = planear_cuentas(clientes)
    cuentas, titularidades, eventos_tmp = [], [], []
    vigentes_por_cliente = [0] * len(clientes)       # titularidades vigentes (para estado del cliente)
    naturales_vinculados: list[int] = []             # candidatos a cotitular
    puntero = 0

    for cuenta_id, (d0, cliente_id, es_base, producto) in enumerate(plan, start=1):
        cli = clientes[cliente_id - 1]
        tipo_cliente, municipio = cli[1], cli[5]

        # clientes naturales ya vinculados en la fecha de apertura (mayores de edad)
        while puntero < len(clientes) and date.fromisoformat(clientes[puntero][7]) <= d0:
            if clientes[puntero][1] == "NATURAL":
                naturales_vinculados.append(clientes[puntero][0])
            puntero += 1

        moneda = "USD" if producto in LIMITE_USD and rng.random() < 0.02 else "COP"
        limite = LIMITE_USD[producto] if moneda == "USD" else LIMITE_COP[producto]
        if producto == "CORRIENTE" and tipo_cliente == "JURIDICA":
            limite = 20_000_000
        cupo = 0
        if producto == "CORRIENTE" and rng.random() < 0.35:                      # RN-17
            opciones = [5_000_000, 10_000_000, 20_000_000] if tipo_cliente == "JURIDICA" \
                else [1_000_000, 2_000_000, 3_000_000, 5_000_000]
            cupo = rng.choice(opciones)

        oficina_id = rng.choice(oficinas_por_municipio[municipio])
        cajero = lambda: rng.choice(cajeros[oficina_id])
        supervisor = lambda: rng.choice(supervisores[oficina_id])

        t0 = hora_habil(d0)
        estado = rng.choices(*ESTADOS_FINALES)[0]
        eventos = []                                    # (ts, tipo, anterior, nuevo, motivo, usuario, cambio)
        fecha_cierre = None

        # Desistimiento: cuenta creada y cerrada sin activarse
        if estado == "CERRADA" and rng.random() < 0.10 and d0 < FECHA_CORTE:
            eventos.append((t0, "CREACION", None, "CREADA", None, cajero(), None))
            d_cierre = dia_entre(d0 + timedelta(days=1), min(d0 + timedelta(days=10), FECHA_CORTE))
            fecha_cierre = hora_habil(d_cierre)
            eventos.append((fecha_cierre, "CIERRE", "CREADA", "CERRADA", "Desistimiento del cliente", supervisor(), None))
        else:
            eventos.append((t0, "CREACION", None, "CREADA", None, cajero(), None))
            t1 = t0 + timedelta(minutes=rng.randint(5, 90))
            eventos.append((t1, "ACTIVACION", "CREADA", "ACTIVA", None, cajero(), None))

            # Fecha del evento final (se reserva primero para que la historia quepa antes)
            minimo = {"INACTIVA": 180, "BLOQUEADA": 2, "CERRADA": 30}.get(estado)
            d_final = None
            if minimo is not None:
                if d0 + timedelta(days=minimo) <= FECHA_CORTE:
                    d_final = dia_entre(d0 + timedelta(days=minimo), FECHA_CORTE)
                else:
                    estado = "ACTIVA"
            fin_historia = (d_final - timedelta(days=1)) if d_final else FECHA_CORTE
            cursor = d0

            # Historia opcional: bloqueo y desbloqueo (RN-28, RN-29)
            if rng.random() < 0.03 and (fin_historia - cursor).days >= 4:
                d_b = dia_entre(cursor + timedelta(days=1), fin_historia - timedelta(days=2))
                d_u = dia_entre(d_b + timedelta(days=1), min(d_b + timedelta(days=60), fin_historia - timedelta(days=1)))
                eventos.append((hora_habil(d_b), "BLOQUEO", "ACTIVA", "BLOQUEADA", rng.choice(MOTIVOS_BLOQUEO), cajero(), None))
                eventos.append((hora_habil(d_u), "DESBLOQUEO", "BLOQUEADA", "ACTIVA", "Validación completada", supervisor(), None))
                cursor = d_u

            # Historia opcional: cambio de límite (RN-27)
            if rng.random() < 0.06 and (fin_historia - cursor).days >= 1:
                factor = rng.choice([0.5, 1.5, 2.0])
                paso = 100 if moneda == "USD" else 100_000
                nuevo = max(paso, round(limite * factor / paso) * paso)
                if nuevo != limite:
                    d_c = dia_entre(cursor + timedelta(days=1), fin_historia)
                    eventos.append((hora_habil(d_c), "CAMBIO_LIMITE", "ACTIVA", "ACTIVA", None, supervisor(), (limite, nuevo)))
                    limite = nuevo
                    cursor = d_c

            # Evento final
            if estado == "INACTIVA":
                eventos.append((hora_habil(d_final), "INACTIVACION", "ACTIVA", "INACTIVA", "Sin movimientos por más de 180 días", cajero(), None))
            elif estado == "BLOQUEADA":
                eventos.append((hora_habil(d_final), "BLOQUEO", "ACTIVA", "BLOQUEADA", rng.choice(MOTIVOS_BLOQUEO), cajero(), None))
            elif estado == "CERRADA":
                fecha_cierre = hora_habil(d_final)
                eventos.append((fecha_cierre, "CIERRE", "ACTIVA", "CERRADA", "Solicitud del cliente", supervisor(), None))

        numero = PREFIJO_CUENTA[producto] + f"{cuenta_id:09d}"                     # RN-11
        cuentas.append((cuenta_id, numero, producto, moneda, oficina_id, estado, ts(t0), ts(fecha_cierre),
                        "0.00", "0.00", f"{cupo:.2f}", f"{limite:.2f}"))

        # Titular principal (RN-13) y, en algunos casos, un cotitular (RN-16: máximo 4)
        hasta = ts(fecha_cierre)
        titularidades.append((cuenta_id, cliente_id, ts(t0), "PRINCIPAL", hasta))
        if fecha_cierre is None:
            vigentes_por_cliente[cliente_id - 1] += 1
        if (tipo_cliente == "NATURAL" and producto in ("AHORROS", "CORRIENTE") and moneda == "COP"
                and len(naturales_vinculados) > 1 and rng.random() < 0.06):
            cotitular = rng.choice(naturales_vinculados)
            if cotitular != cliente_id:
                titularidades.append((cuenta_id, cotitular, ts(t0), "COTITULAR", hasta))
                if fecha_cierre is None:
                    vigentes_por_cliente[cotitular - 1] += 1

        for e in eventos:
            eventos_tmp.append((e[0], cuenta_id, e))

    # Cliente INACTIVO si ya no tiene ninguna titularidad vigente
    estado_cliente = ["ACTIVO" if v > 0 else "INACTIVO" for v in vigentes_por_cliente]

    # IDs de evento en orden cronológico
    eventos_tmp.sort(key=lambda x: (x[0], x[1]))
    eventos, cambios = [], []
    for evento_id, (momento, cuenta_id, e) in enumerate(eventos_tmp, start=1):
        _, tipo, anterior, nuevo, motivo, usuario, cambio = e
        eventos.append((evento_id, cuenta_id, tipo, anterior, nuevo, motivo, ts(momento), usuario))
        if cambio:
            cambios.append((evento_id, f"{cambio[0]:.2f}", f"{cambio[1]:.2f}"))
    return cuentas, titularidades, eventos, cambios, estado_cliente


# ---------------------------------------------------------------------------
# Principal
# ---------------------------------------------------------------------------
def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    departamentos, municipios, oficinas, oficinas_por_municipio = generar_geografia()
    usuarios, roles, cajeros, supervisores = generar_usuarios(oficinas)
    clientes, naturales, juridicas = generar_clientes()
    cuentas, titularidades, eventos, cambios, estado_cliente = generar_cuentas(
        clientes, oficinas_por_municipio, cajeros, supervisores)

    clientes = [c[:6] + (estado_cliente[i],) + c[7:] for i, c in enumerate(clientes)]

    escribir_csv("departamento.csv", ["departamento_codigo", "nombre"], departamentos)
    escribir_csv("municipio.csv", ["municipio_codigo", "departamento_codigo", "nombre"], municipios)
    escribir_csv("oficina.csv", ["oficina_id", "codigo", "nombre", "municipio_codigo"], oficinas)
    escribir_csv("usuario.csv", ["usuario_id", "login", "tipo_documento", "numero_documento", "nombres",
                                 "apellidos", "oficina_id", "estado", "creado_en"], usuarios)
    escribir_csv("usuario_rol.csv", ["usuario_id", "rol_codigo", "vigente_desde", "vigente_hasta",
                                     "asignado_por"], roles)
    escribir_csv("cliente.csv", ["cliente_id", "tipo_cliente", "tipo_documento", "numero_documento",
                                 "digito_verificacion", "municipio_codigo", "estado_cliente",
                                 "fecha_vinculacion", "email", "telefono"], clientes)
    escribir_csv("persona_natural.csv", ["cliente_id", "nombres", "apellidos", "fecha_nacimiento"], naturales)
    escribir_csv("persona_juridica.csv", ["cliente_id", "razon_social", "fecha_constitucion",
                                          "actividad_economica"], juridicas)
    escribir_csv("cuenta.csv", ["cuenta_id", "numero_cuenta", "producto_codigo", "moneda_codigo", "oficina_id",
                                "estado_cuenta", "fecha_apertura", "fecha_cierre", "saldo_contable",
                                "saldo_retenido", "cupo_sobregiro", "limite_retiro_diario"], cuentas)
    escribir_csv("titularidad_cuenta.csv", ["cuenta_id", "cliente_id", "vigente_desde", "rol_titular",
                                            "vigente_hasta"], titularidades)
    escribir_csv("evento_cuenta.csv", ["evento_id", "cuenta_id", "tipo_evento", "estado_anterior",
                                       "estado_nuevo", "motivo", "ocurrido_en", "registrado_por"], eventos)
    escribir_csv("cambio_limite.csv", ["evento_id", "valor_anterior", "valor_nuevo"], cambios)

    print(f"Semilla: {SEED}")
    print(f"{'archivo':<26}{'filas':>8}  sha256")
    for ruta in sorted(OUT.glob("*.csv")):
        filas = sum(1 for _ in ruta.open(encoding="utf-8")) - 1
        huella = hashlib.sha256(ruta.read_bytes()).hexdigest()[:16]
        print(f"{ruta.name:<26}{filas:>8}  {huella}")


if __name__ == "__main__":
    main()
