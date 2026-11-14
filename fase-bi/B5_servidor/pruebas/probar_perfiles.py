"""B5 · Prueba cada perfil contra el servidor, como lo haría una persona desde el navegador.

1. Sesión: sin sesión no entra nada, la contraseña mala no entra, las operaciones exigen la
   cabecera del aplicativo.
2. Matriz de acceso: cada perfil intenta entrar a todas las secciones. Las suyas deben
   responder 200 y las ajenas 403.
3. Operaciones de verdad contra la base (consignar, retirar, transferir, ajustes, bloquear,
   desbloquear, reversar, cerrar...) y los intentos que deben fallar (fondos, oficina ajena,
   cuenta ajena, el que crea un ajuste no lo aprueba, nadie se asigna roles a sí mismo...).
4. Al final el auditor revisa que la contabilidad siga cuadrada después de todo.

Uso (con el aplicativo prendido):
    python fase-bi/B5_servidor/pruebas/probar_perfiles.py [http://localhost:8000]
Lee las contraseñas de fase-bi/aplicativo/accesos_demo.local.txt. Solo usa la librería estándar.

OJO: hace operaciones reales (quedan con la descripción "Prueba B5"), como cualquier uso del
aplicativo. Mueve montos pequeños y deja todo cuadrado.
"""
import http.cookiejar
import json
import re
import sys
import time
import urllib.error
import urllib.request
import uuid
from decimal import Decimal
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
ARCHIVO_ACCESOS = RAIZ / "aplicativo" / "accesos_demo.local.txt"
SALIDA = Path(__file__).resolve().parent.parent / "salidas" / "salida_pruebas_perfiles.txt"

resultados: list[tuple[str, str, str, str, bool]] = []


def anotar(grupo, prueba, esperado, obtenido, ok=None):
    ok = (str(esperado) == str(obtenido)) if ok is None else ok
    resultados.append((grupo, prueba, str(esperado), str(obtenido), bool(ok)))
    print(("PASS" if ok else "FAIL") + f"  [{grupo}] {prueba}: esperado {esperado}, obtenido {obtenido}", flush=True)
    return ok


class Navegador:
    """Una persona con su propia sesión (cookie)."""

    def __init__(self, base: str):
        self.base = base
        self.abridor = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def pedir(self, metodo, ruta, cuerpo=None, cabecera=True):
        datos = None if cuerpo is None else json.dumps(cuerpo, default=str).encode()
        req = urllib.request.Request(self.base + ruta, data=datos, method=metodo)
        req.add_header("Accept", "application/json")
        if datos is not None:
            req.add_header("Content-Type", "application/json")
        if cabecera:
            req.add_header("X-Banco-App", "1")
        try:
            with self.abridor.open(req, timeout=180) as r:
                return r.status, json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read() or b"null")
            except ValueError:
                return e.code, None

    def get(self, ruta):
        return self.pedir("GET", ruta)

    def post(self, ruta, cuerpo=None, cabecera=True):
        return self.pedir("POST", ruta, cuerpo or {}, cabecera)


def codigo(respuesta):
    d = (respuesta[1] or {}).get("detail") if isinstance(respuesta[1], dict) else None
    return d.get("codigo") if isinstance(d, dict) else None


def leer_accesos() -> dict:
    if not ARCHIVO_ACCESOS.exists():
        sys.exit(f"No encontramos {ARCHIVO_ACCESOS}. Arranque el aplicativo una vez con iniciar_local.bat.")
    claves = {}
    for linea in ARCHIVO_ACCESOS.read_text(encoding="utf-8").splitlines():
        m = re.search(r"usuario:\s*(\S+)\s+contraseña:\s*(\S+)", linea)
        if m:
            claves[m.group(1)] = m.group(2)   # si hay varias, gana la última
    return claves


_cajero_aux = None


def cajero_de_prueba(base, claves):
    global _cajero_aux
    if _cajero_aux is None:
        _cajero_aux = Navegador(base)
        _cajero_aux.post("/api/sesion/ingresar", {"login": "demo.cajero", "clave": claves["demo.cajero"]})
    return _cajero_aux


def buscar_servidor(base):
    if base:
        return base.rstrip("/")
    for puerto in range(8000, 8011):
        try:
            with urllib.request.urlopen(f"http://localhost:{puerto}/salud", timeout=2) as r:
                if json.loads(r.read()).get("estado") == "ok":
                    return f"http://localhost:{puerto}"
        except Exception:
            continue
    sys.exit("No encontramos el aplicativo prendido entre los puertos 8000 y 8010.")


def main():
    base = buscar_servidor(sys.argv[1] if len(sys.argv) > 1 else None)
    claves = leer_accesos()
    print(f"Servidor: {base}\n")
    D = Decimal

    # ------------------------------------------------------------------ 1. Sesión
    anon = Navegador(base)
    anotar("Sesión", "Sin sesión no se ven las cuentas", 401, anon.get("/api/cliente/cuentas")[0])
    anotar("Sesión", "Sin sesión no se ven las estadísticas", 401, anon.get("/api/estadisticas/resumen")[0])
    anotar("Sesión", "Operación sin la cabecera del aplicativo (CSRF)", 403,
           anon.post("/api/sesion/ingresar", {"login": "demo.cajero", "clave": "x"}, cabecera=False)[0])
    r_mala = anon.post("/api/sesion/ingresar", {"login": "demo.cajero", "clave": "clave-equivocada"})
    anotar("Sesión", "Contraseña equivocada", 401, r_mala[0])
    r_nadie = anon.post("/api/sesion/ingresar", {"login": "no.existe", "clave": "x"})
    anotar("Sesión", "Usuario que no existe: mismo mensaje que contraseña mala (no delata usuarios)",
           r_mala[1]["detail"]["mensaje"], r_nadie[1]["detail"]["mensaje"])

    nav = {}
    for login, perfil in [("demo.cliente", "CLIENTE"), ("demo.cajero", "CAJERO"), ("demo.supervisor", "SUPERVISOR"),
                          ("demo.auditor", "AUDITOR"), ("demo.admin", "ADMINISTRADOR")]:
        n = Navegador(base)
        r = n.post("/api/sesion/ingresar", {"login": login, "clave": claves.get(login, "")})
        anotar("Sesión", f"Ingresa {login}", f"200 {perfil}", f"{r[0]} {(r[1] or {}).get('perfil')}")
        nav[perfil] = n
    cliente, cajero, supervisor, auditor, admin = (nav[p] for p in ("CLIENTE", "CAJERO", "SUPERVISOR", "AUDITOR", "ADMINISTRADOR"))

    # ------------------------------------------------------------------ 2. Matriz de acceso
    cuentas = cliente.get("/api/cliente/cuentas")[1]
    # Dos cuentas activas en pesos del cliente que sean de la oficina del cajero
    activas = [c for c in cuentas if c["estado"] == "ACTIVA" and c["moneda"] == "COP"
               and cajero_de_prueba(base, claves).get(f"/api/caja/cuentas/{c['cuenta_id']}")[0] == 200]
    A, B = activas[0], activas[1]
    secciones = {
        "Cliente":                  "/api/cliente/cuentas",
        "Caja":                     f"/api/caja/buscar?q={A['numero_cuenta']}",
        "Supervisor":               "/api/supervisor/ajustes",
        "Auditor":                  "/api/auditor/ingresos",
        "Administrador":            "/api/admin/usuarios?q=demo",
        "Estadísticas: Resumen":    "/api/estadisticas/resumen",
        "Estadísticas: Control":    "/api/estadisticas/control",
    }
    permitido = {
        "CLIENTE": {"Cliente"},
        "CAJERO": {"Caja"},
        "SUPERVISOR": {"Caja", "Supervisor", "Estadísticas: Resumen", "Estadísticas: Control"},
        "AUDITOR": {"Auditor", "Estadísticas: Control"},
        "ADMINISTRADOR": {"Administrador", "Estadísticas: Resumen", "Estadísticas: Control"},
    }
    for perfil, n in nav.items():
        for seccion, ruta in secciones.items():
            esperado = 200 if seccion in permitido[perfil] else 403
            anotar("Matriz", f"{perfil} → {seccion}", esperado, n.get(ruta)[0])

    # ------------------------------------------------------------------ 3. Caja (cajero)
    cliente_id = cajero.get(f"/api/caja/buscar?q={A['numero_cuenta']}")[1][0]["cliente_id"]
    saldo_a = D(cajero.get(f"/api/caja/cuentas/{A['cuenta_id']}")[1]["saldo_contable"])

    k1 = str(uuid.uuid4())
    r = cajero.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "50000", "descripcion": "Prueba B5", "clave": k1})
    anotar("Cajero", "Consigna 50.000", 200, r[0])
    tx_consignacion = r[1]["transaccion_id"]
    anotar("Cajero", "El saldo sube exactamente 50.000", saldo_a + 50000, D(r[1]["saldo"]["saldo_contable"]))
    r2 = cajero.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "50000", "descripcion": "Prueba B5", "clave": k1})
    anotar("Cajero", "Repetir la misma solicitud no cobra dos veces (idempotencia)",
           f"{tx_consignacion} {saldo_a + 50000}", f"{r2[1]['transaccion_id']} {D(r2[1]['saldo']['saldo_contable'])}")
    anotar("Cajero", "Retira 20.000", 200,
           cajero.post("/api/caja/retirar", {"cuenta_id": A["cuenta_id"], "monto": "20000", "descripcion": "Prueba B5"})[0])
    r = cajero.post("/api/caja/retirar", {"cuenta_id": A["cuenta_id"], "monto": "900000000000", "descripcion": "Prueba B5"})
    anotar("Cajero", "Retiro imposible: rechazado y registrado (RN-45)", "409 con rechazo",
           f"{r[0]} {'con rechazo' if (r[1] or {}).get('detail', {}).get('rechazo_id') else 'sin rechazo'}")
    anotar("Cajero", "Transfiere 10.000 entre cuentas del cliente", 200,
           cajero.post("/api/caja/transferir", {"cuenta_origen_id": A["cuenta_id"], "numero_destino": B["numero_cuenta"],
                                                "monto": "10000", "descripcion": "Prueba B5"})[0])
    anotar("Cajero", "Monto con tres decimales", 422,
           cajero.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "10.555"})[0])

    otra = None
    for cid in range(1, 400):
        if cajero.get(f"/api/caja/cuentas/{cid}")[0] == 403:
            otra = cid
            break
    anotar("Cajero", "Consignar en una cuenta de otra oficina", "403 OFICINA",
           f"{(r := cajero.post('/api/caja/consignar', {'cuenta_id': otra, 'monto': '1000'}))[0]} {codigo(r)}")
    anotar("Cajero", "Reversar (solo supervisor)", 403,
           cajero.post(f"/api/supervisor/transacciones/{tx_consignacion}/reversar", {"motivo": "Prueba B5"})[0])

    r = cajero.post("/api/caja/ajustes", {"cuenta_id": A["cuenta_id"], "monto": "1000", "sentido": "C", "descripcion": "Prueba B5 ajuste"})
    anotar("Cajero", "Crea un ajuste (queda pendiente)", "200 PENDING_APPROVAL", f"{r[0]} {(r[1] or {}).get('estado')}")
    ajuste_cajero = r[1]["transaccion_id"]
    anotar("Cajero", "Aprobar su ajuste (solo supervisor)", 403, cajero.post(f"/api/supervisor/ajustes/{ajuste_cajero}/aprobar")[0])

    muni = cajero.get("/api/caja/municipios?q=Manizales")[1][0]["municipio_codigo"]
    doc = f"8{int(time.time()) % 10**9:09d}"
    persona = {"tipo_documento": "CC", "numero_documento": doc, "nombres": "Cliente", "apellidos": "De Prueba B5",
               "fecha_nacimiento": "1995-05-20", "municipio_codigo": muni}
    r = cajero.post("/api/caja/clientes/natural", persona)
    anotar("Cajero", "Registra un cliente nuevo (persona natural)", 200, r[0])
    r = cajero.post("/api/caja/clientes/natural", persona)
    anotar("Cajero", "Registrar el mismo documento otra vez", "409 23505", f"{r[0]} {codigo(r)}")

    r = cajero.post("/api/caja/cuentas", {"cliente_id": cliente_id, "producto_codigo": "AHORROS", "moneda_codigo": "COP",
                                          "limite_retiro_diario": "2000000"})
    anotar("Cajero", "Abre una cuenta de ahorros", "200 CREADA", f"{r[0]} {(r[1] or {}).get('estado_cuenta')}")
    nueva = r[1]["cuenta_id"]
    anotar("Cajero", "Activa la cuenta nueva", 200, cajero.post(f"/api/caja/cuentas/{nueva}/activar")[0])
    r = cajero.post("/api/caja/consignar", {"cuenta_id": nueva, "monto": "5000", "descripcion": "Prueba B5"})
    anotar("Cajero", "Consigna 5.000 en la cuenta nueva", 200, r[0])
    tx_nueva = r[1]["transaccion_id"]
    anotar("Cajero", "Bloquea la cuenta nueva", 200, cajero.post(f"/api/caja/cuentas/{nueva}/bloquear", {"motivo": "Prueba B5"})[0])
    r = cajero.post("/api/caja/retirar", {"cuenta_id": nueva, "monto": "1000", "descripcion": "Prueba B5"})
    anotar("Cajero", "Retirar de una cuenta bloqueada", "409 BA002", f"{r[0]} {codigo(r)}")
    anotar("Cajero", "Desbloquear (solo supervisor, RN-28)", 403, cajero.post(f"/api/supervisor/cuentas/{nueva}/desbloquear")[0])

    # ------------------------------------------------------------------ 4. Supervisor
    anotar("Supervisor", "Desbloquea la cuenta", 200, supervisor.post(f"/api/supervisor/cuentas/{nueva}/desbloquear")[0])
    anotar("Supervisor", "Reversa la consignación de 5.000", 200,
           supervisor.post(f"/api/supervisor/transacciones/{tx_nueva}/reversar", {"motivo": "Prueba B5"})[0])
    r = supervisor.post(f"/api/supervisor/transacciones/{tx_nueva}/reversar", {"motivo": "Prueba B5"})
    anotar("Supervisor", "Reversar dos veces lo mismo (RN-42)", "409 BA008", f"{r[0]} {codigo(r)}")
    anotar("Supervisor", "Cambia el límite diario", 200,
           supervisor.post(f"/api/supervisor/cuentas/{nueva}/limite", {"nuevo_limite": "1500000"})[0])
    anotar("Supervisor", "Cierra la cuenta (quedó en 0)", 200, supervisor.post(f"/api/supervisor/cuentas/{nueva}/cerrar")[0])
    pendientes = supervisor.get("/api/supervisor/ajustes")[1]
    anotar("Supervisor", "Ve el ajuste del cajero en pendientes", True, any(p["transaccion_id"] == ajuste_cajero for p in pendientes))
    anotar("Supervisor", "Aprueba el ajuste del cajero", 200, supervisor.post(f"/api/supervisor/ajustes/{ajuste_cajero}/aprobar")[0])
    r = supervisor.post("/api/caja/ajustes", {"cuenta_id": A["cuenta_id"], "monto": "1000", "sentido": "C", "descripcion": "Prueba B5 ajuste propio"})
    propio = r[1]["transaccion_id"]
    r = supervisor.post(f"/api/supervisor/ajustes/{propio}/aprobar")
    anotar("Supervisor", "Aprobar su propio ajuste (RN-44)", "409 BA013", f"{r[0]} {codigo(r)}")
    anotar("Supervisor", "Rechaza su ajuste con motivo", 200,
           supervisor.post(f"/api/supervisor/ajustes/{propio}/rechazar", {"motivo": "Prueba B5: lo aprueba otro"})[0])
    r = supervisor.get("/api/supervisor/inactivar?dias=180")
    anotar("Supervisor", "Vista previa de inactivación (no cambia nada)", 200, r[0])
    anotar("Supervisor", "Inactivar sin confirmar", 422, supervisor.post("/api/supervisor/inactivar", {"dias": 180, "confirmar": False})[0])
    anotar("Supervisor", "Inactivar con menos de 180 días", 422, supervisor.post("/api/supervisor/inactivar", {"dias": 30, "confirmar": True})[0])

    # ------------------------------------------------------------------ 5. Cliente
    movs = cliente.get(f"/api/cliente/cuentas/{A['cuenta_id']}/movimientos?limite=20")
    anotar("Cliente", "Ve sus movimientos (incluida la consignación del cajero)", True,
           movs[0] == 200 and any(m["transaccion_id"] == tx_consignacion for m in movs[1]))
    r = cliente.get(f"/api/cliente/cuentas/{otra}/movimientos")
    anotar("Cliente", "Movimientos de una cuenta ajena", "403 BA010", f"{r[0]} {codigo(r)}")
    r = cliente.post("/api/cliente/transferir", {"cuenta_origen_id": A["cuenta_id"], "numero_destino": B["numero_cuenta"],
                                                 "monto": "1000", "descripcion": "Prueba B5"})
    anotar("Cliente", "Transfiere 1.000 a su otra cuenta", 200, r[0])
    r = cliente.post("/api/cliente/transferir", {"cuenta_origen_id": otra, "numero_destino": B["numero_cuenta"], "monto": "1000"})
    anotar("Cliente", "Transferir desde una cuenta ajena", "403 BA010", f"{r[0]} {codigo(r)}")
    r = cliente.post("/api/cliente/transferir", {"cuenta_origen_id": A["cuenta_id"], "numero_destino": B["numero_cuenta"],
                                                 "monto": "900000000000"})
    anotar("Cliente", "Transferir más de lo que tiene: rechazado y registrado", "409 BA003 con rechazo",
           f"{r[0]} {codigo(r)} {'con rechazo' if (r[1] or {}).get('detail', {}).get('rechazo_id') else 'sin rechazo'}")
    r = cliente.post("/api/cliente/transferir", {"cuenta_origen_id": A["cuenta_id"], "numero_destino": "99999999999", "monto": "1000"})
    anotar("Cliente", "Transferir a una cuenta que no existe", "404 BA016", f"{r[0]} {codigo(r)}")
    anotar("Cliente", "Ve su resumen mensual", 200, cliente.get("/api/cliente/resumen")[0])
    anotar("Cliente", "Intenta consignar como cajero", 403, cliente.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "1000"})[0])

    # ------------------------------------------------------------------ 6. Administrador
    login_nuevo = f"prueba.b5.{int(time.time()) % 100000}"
    r = admin.post("/api/admin/usuarios", {"login": login_nuevo, "tipo_documento": "CC",
                                           "numero_documento": f"9{int(time.time()) % 10**9:09d}", "nombres": "Usuario",
                                           "apellidos": "De Prueba B5", "oficina_id": None})
    anotar("Administrador", "Crea un usuario interno", 200, r[0])
    nuevo_u = r[1]["usuario_id"]
    anotar("Administrador", "Le asigna el rol CAJERO", 200, admin.post(f"/api/admin/usuarios/{nuevo_u}/roles", {"rol": "CAJERO"})[0])
    anotar("Administrador", "Asignar otra vez el mismo rol", 409, admin.post(f"/api/admin/usuarios/{nuevo_u}/roles", {"rol": "CAJERO"})[0])
    anotar("Administrador", "Revoca el rol (con fecha, no se borra)", 200, admin.post(f"/api/admin/usuarios/{nuevo_u}/roles/CAJERO/revocar")[0])
    anotar("Administrador", "Desactiva el usuario", 200, admin.post(f"/api/admin/usuarios/{nuevo_u}/estado", {"estado": "INACTIVO"})[0])
    yo = admin.get("/api/sesion")[1]["nombre"]
    mi_id = next(u["usuario_id"] for u in admin.get("/api/admin/usuarios?q=" + urllib.request.quote(yo))[1])
    r = admin.post(f"/api/admin/usuarios/{mi_id}/roles", {"rol": "SUPERVISOR"})
    anotar("Administrador", "Asignarse un rol a sí mismo (RN-50, lo frena la base)", "422 23514", f"{r[0]} {codigo(r)}")
    anotar("Administrador", "Desactivarse a sí mismo", 409, admin.post(f"/api/admin/usuarios/{mi_id}/estado", {"estado": "INACTIVO"})[0])
    canal = admin.get("/api/admin/usuarios?q=canal.digital")[1][0]["usuario_id"]
    anotar("Administrador", "Tocar el usuario técnico del canal digital", 409,
           admin.post(f"/api/admin/usuarios/{canal}/estado", {"estado": "INACTIVO"})[0])
    anotar("Administrador", "Intenta consignar", 403, admin.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "1000"})[0])

    # Quitarle el rol a alguien lo saca de inmediato
    nombre_auditor = auditor.get("/api/sesion")[1]["nombre"]
    id_auditor = next(u["usuario_id"] for u in admin.get("/api/admin/usuarios?q=" + urllib.request.quote(nombre_auditor))[1])
    admin.post(f"/api/admin/usuarios/{id_auditor}/roles/AUDITOR/revocar")
    anotar("Administrador", "Al revocarle el rol al auditor, su sesión deja de servir al instante", 401,
           auditor.get("/api/auditor/ingresos")[0])
    anotar("Administrador", "Le devuelve el rol de auditor", 200, admin.post(f"/api/admin/usuarios/{id_auditor}/roles", {"rol": "AUDITOR"})[0])
    auditor = Navegador(base)
    auditor.post("/api/sesion/ingresar", {"login": "demo.auditor", "clave": claves["demo.auditor"]})

    # ------------------------------------------------------------------ 7. Auditor de datos
    r = auditor.get("/api/auditor/cuadres")
    anotar("Auditor", "Después de todas las pruebas la contabilidad sigue cuadrada (3 controles en 0)", "200 [0, 0, 0]",
           f"{r[0]} {[c['diferencias'] for c in r[1]] if r[0] == 200 else ''}")
    bit = auditor.get("/api/auditor/bitacora?tabla=transaccion_financiera&limite=30")[1]
    anotar("Auditor", "La bitácora muestra las operaciones hechas desde el aplicativo", True,
           any(b["usuario_bd"] == "app_servidor" for b in bit))
    ingresos = auditor.get("/api/auditor/ingresos?limite=100")[1]
    anotar("Auditor", "Ve el intento fallido de ingreso", True, any((not i["exitoso"]) and i["login"] == "demo.cajero" for i in ingresos))
    r = auditor.get("/api/auditor/calidad")
    anotar("Auditor", "Ve las 76 pruebas del quality gate", 76, len(r[1]["pruebas"]) if r[0] == 200 else r[0])
    anotar("Auditor", "Intenta consignar", 403, auditor.post("/api/caja/consignar", {"cuenta_id": A["cuenta_id"], "monto": "1000"})[0])
    anotar("Auditor", "Intenta crear usuarios", 403, auditor.post("/api/admin/usuarios", {})[0])

    # ------------------------------------------------------------------ 8. Estadísticas según el perfil
    r = admin.get("/api/estadisticas/resumen")
    anotar("Estadísticas", "El administrador ve todo el banco (K01 = 1.000.000)", "Todo el banco 1000000",
           f"{r[1]['alcance']} {r[1]['indicadores']['K01']['valor']}")
    r = supervisor.get("/api/estadisticas/resumen")
    k01_oficina = int(r[1]["indicadores"]["K01"]["valor"])
    anotar("Estadísticas", "El supervisor solo ve su oficina", True, r[1]["alcance"] != "Todo el banco" and 0 < k01_oficina < 1000000)

    # ------------------------------------------------------------------ 9. Salir
    cliente.post("/api/sesion/salir")
    anotar("Sesión", "Después de salir, la sesión ya no sirve", 401, cliente.get("/api/cliente/cuentas")[0])

    # ------------------------------------------------------------------ Resumen
    total, fallas = len(resultados), sum(not r[4] for r in resultados)
    veredicto = "B5 PERFILES = PASS" if fallas == 0 else "B5 PERFILES = FAIL"
    lineas = [f"B5 · Pruebas por perfil contra el servidor ({base}) · {time.strftime('%Y-%m-%d %H:%M')}", ""]
    lineas += [f"{'PASS' if ok else 'FAIL'}  [{g}] {p}: esperado {e}, obtenido {o}" for g, p, e, o, ok in resultados]
    lineas += ["", f"Pruebas: {total} · PASS: {total - fallas} · FAIL: {fallas}", veredicto]
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    print("\n" + lineas[-2] + "\n" + veredicto)
    sys.exit(0 if fallas == 0 else 1)


if __name__ == "__main__":
    main()
