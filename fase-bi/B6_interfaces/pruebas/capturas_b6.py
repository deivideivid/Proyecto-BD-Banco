"""B6 · Recorre las pantallas de cada perfil en celular, tablet y computador, toma capturas y
revisa que el navegador no muestre errores (JavaScript o bloqueos de la política de seguridad).

Uso (con el aplicativo prendido):
    python fase-bi/B6_interfaces/pruebas/capturas_b6.py [http://localhost:8000]
Lee las contraseñas de fase-bi/aplicativo/accesos_demo.local.txt.
Necesita:  pip install playwright  y  python -m playwright install chromium
"""
import re
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
AQUI = Path(__file__).resolve().parent.parent
CAPTURAS = AQUI / "capturas"
ACCESOS = AQUI.parent / "aplicativo" / "accesos_demo.local.txt"
SALIDA = AQUI / "salidas" / "revision_pantallas.txt"

DISPOSITIVOS = {
    "celular": dict(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True, device_scale_factor=2),
    "tablet": dict(viewport={"width": 820, "height": 1180}, is_mobile=True, has_touch=True, device_scale_factor=1),
    "computador": dict(viewport={"width": 1440, "height": 900}, device_scale_factor=1),
}
# (perfil, pantalla, dirección, qué esperar en la página, en qué dispositivos)
TODOS = tuple(DISPOSITIVOS)
PANTALLAS = [
    (None, "inicio", "index.html", ".portada", TODOS),
    (None, "equipo", "equipo.html", ".integrante", TODOS),
    (None, "tecnologias", "tecnologias.html", ".tecnologia", ("computador", "celular")),
    (None, "ingresar", "ingresar.html", "#form-ingreso", TODOS),
    ("demo.cliente", "cliente_cuentas", "cliente.html#cuentas", ".cuenta", TODOS),
    ("demo.cliente", "cliente_movimientos", "cliente.html#movimientos", "#lista-movimientos table, #lista-movimientos .vacio", ("computador", "celular")),
    ("demo.cliente", "cliente_transferir", "cliente.html#transferir", "#form-transferir", TODOS),
    ("demo.cliente", "cliente_estadisticas", "cliente.html#estadisticas", "#est-totales .tarjeta", ("computador", "celular")),
    ("demo.cajero", "cajero_buscar", "caja.html#buscar?q=Sandoval", "#resultados table, #resultados .vacio", TODOS),
    ("demo.cajero", "cajero_operacion", "caja.html#operacion", "#form-operacion", ("computador", "celular")),
    ("demo.cajero", "cajero_nuevo_cliente", "caja.html#nuevo", "#form-natural", ("computador", "celular")),
    ("demo.supervisor", "supervisor_pendientes", "supervisor.html#pendientes", "#lista-pendientes table, #lista-pendientes .vacio", TODOS),
    ("demo.supervisor", "supervisor_reversar", "supervisor.html#reversar", "#form-tx", ("computador", "celular")),
    ("demo.supervisor", "supervisor_estadisticas", "estadisticas.html#resumen", "#tarjetas .valor .cifra", TODOS),
    ("demo.auditor", "auditor_calidad", "auditor.html#calidad", "#calidad-pruebas table", TODOS),
    ("demo.auditor", "auditor_bitacora", "auditor.html#bitacora", "#form-bitacora", ("computador", "celular")),
    ("demo.admin", "admin_usuarios", "admin.html#usuarios", "#lista-usuarios table", TODOS),
    ("demo.admin", "admin_accesos", "admin.html#accesos", "#lista-accesos table", ("computador", "celular")),
]


def claves():
    texto = ACCESOS.read_text(encoding="utf-8") if ACCESOS.exists() else ""
    return {m.group(1): m.group(2) for m in re.finditer(r"usuario:\s*(\S+)\s+contraseña:\s*(\S+)", texto)}


def entrar(nav, opciones, login, clave):
    ctx = nav.new_context(**opciones, locale="es-CO", timezone_id="America/Bogota")
    p = ctx.new_page()
    p.goto(f"{BASE}/ingresar.html")
    p.fill("#login", login)
    p.fill("#clave", clave)
    p.click("#entrar")
    p.wait_for_url(lambda u: "ingresar.html" not in u, timeout=60000)
    return ctx, p


def interacciones(nav, c):
    """Lo que no se ve en una captura quieta: el menú y una operación de punta a punta."""
    lineas = []

    def anotar(ok, texto):
        lineas.append(f"{'PASS' if ok else 'FAIL'}  {texto}")
        print(lineas[-1], flush=True)

    # Computador: plegar el menú y que se recuerde
    ctx, p = entrar(nav, DISPOSITIVOS["computador"], "demo.supervisor", c.get("demo.supervisor", ""))
    p.wait_for_selector(".marco")
    ancho_antes = p.evaluate("document.querySelector('.marco-menu').getBoundingClientRect().width")
    p.click(".boton-menu")
    p.wait_for_timeout(600)
    ancho_despues = p.evaluate("document.querySelector('.marco-menu').getBoundingClientRect().width")
    p.hover(".item-menu >> nth=1")
    p.wait_for_timeout(300)
    p.screenshot(path=str(CAPTURAS / "computador_menu_plegado.png"))
    p.reload()
    p.wait_for_selector(".marco")
    recordado = p.evaluate("document.querySelector('.marco').classList.contains('plegado')")
    anotar(ancho_despues < 90 < ancho_antes and recordado,
           f"computador menú plegable: {ancho_antes:.0f}px -> {ancho_despues:.0f}px, se recuerda al recargar: {recordado}")
    p.click(".boton-menu")   # dejarlo abierto otra vez
    ctx.close()

    # Celular: el menú sale encima del contenido y se cierra tocando afuera
    ctx, p = entrar(nav, DISPOSITIVOS["celular"], "demo.cliente", c.get("demo.cliente", ""))
    p.wait_for_selector(".cuenta")
    p.click(".boton-menu")
    p.wait_for_timeout(500)
    abierto = p.evaluate("document.querySelector('.marco').classList.contains('menu-abierto')")
    p.screenshot(path=str(CAPTURAS / "celular_menu_abierto.png"))
    p.mouse.click(370, 500)
    p.wait_for_timeout(500)
    cerrado = not p.evaluate("document.querySelector('.marco').classList.contains('menu-abierto')")
    anotar(abierto and cerrado, f"celular menú encima del contenido: se abre {abierto}, se cierra tocando afuera {cerrado}")

    # Transferencia completa del cliente: confirmar -> procesando -> marca de éxito con número
    p.goto(f"{BASE}/cliente.html#transferir")
    p.wait_for_selector("#tr-origen option", state="attached")
    destino = p.evaluate("(() => { const o = [...document.querySelectorAll('#tr-origen option')]; return o[o.length - 1].textContent.split(' · ')[1]; })()")
    p.fill('[name="numero_destino"]', destino)
    p.fill('[name="monto"]', "1.000")
    p.fill('[name="descripcion"]', "Prueba B6")
    p.click("#tr-enviar")
    p.wait_for_selector(".ventana")
    p.screenshot(path=str(CAPTURAS / "celular_transferir_confirmar.png"))
    p.click(".ventana .boton.primario")
    p.wait_for_selector(".marca-exito", timeout=60000)
    p.wait_for_timeout(900)
    numero = p.inner_text(".ventana .numero")
    p.screenshot(path=str(CAPTURAS / "celular_transferir_exito.png"))
    anotar(numero.isdigit(), f"celular transferencia de punta a punta: número de transacción {numero}")
    p.click(".ventana .boton.primario")

    # Error en lenguaje sencillo: transferir más de lo que hay
    p.fill('[name="numero_destino"]', destino)
    p.fill('[name="monto"]', "900000000000")
    p.click("#tr-enviar")
    p.wait_for_selector(".ventana")
    p.click(".ventana .boton.primario")
    p.wait_for_selector("#tr-error:not(:empty)", timeout=60000)
    mensaje = p.inner_text("#tr-error")
    p.screenshot(path=str(CAPTURAS / "celular_transferir_error.png"))
    anotar("Fondos insuficientes" in mensaje, f"celular error en lenguaje sencillo: {mensaje}")
    ctx.close()
    return lineas


def main():
    CAPTURAS.mkdir(parents=True, exist_ok=True)
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    c = claves()
    lineas, problemas = [], 0
    with sync_playwright() as pw:
        nav = pw.chromium.launch()
        for dispositivo, opciones in DISPOSITIVOS.items():
            contextos = {}
            for login, nombre, ruta, espera, dispositivos in PANTALLAS:
                if dispositivo not in dispositivos:
                    continue
                if login not in contextos:
                    ctx = nav.new_context(**opciones, reduced_motion="reduce", locale="es-CO", timezone_id="America/Bogota")
                    if login:
                        p = ctx.new_page()
                        p.goto(f"{BASE}/ingresar.html")
                        p.fill("#login", login)
                        p.fill("#clave", c.get(login, ""))
                        p.click("#entrar")
                        p.wait_for_url(lambda u: "ingresar.html" not in u, timeout=60000)
                        p.close()
                    contextos[login] = ctx
                pagina = contextos[login].new_page()
                errores = []
                pagina.on("pageerror", lambda e: errores.append(str(e)))
                pagina.on("console", lambda m: m.type == "error" and errores.append(m.text))
                pagina.goto(f"{BASE}/{ruta}")
                try:
                    pagina.wait_for_selector(espera, timeout=60000)
                    pagina.wait_for_timeout(600)
                    ok_carga = True
                except Exception:
                    ok_carga = False
                archivo = CAPTURAS / f"{dispositivo}_{nombre}.png"
                pagina.screenshot(path=str(archivo), full_page=True)
                # El ancho de la página no puede pasarse del de la pantalla (sin desplazamiento lateral)
                desborde = pagina.evaluate("document.documentElement.scrollWidth - window.innerWidth")
                ok = ok_carga and not errores and desborde <= 1
                problemas += not ok
                lineas.append(f"{'PASS' if ok else 'FAIL'}  {dispositivo:<10} {nombre:<26} "
                              f"{'cargó' if ok_carga else 'NO cargó'} · desborde lateral {desborde}px"
                              + (f" · errores: {errores[:2]}" if errores else ""))
                print(lineas[-1], flush=True)
                pagina.close()
            for ctx in contextos.values():
                ctx.close()
        # Interacciones: menú plegado (computador), menú abierto (celular) y una transferencia completa
        extra = interacciones(nav, c)
        lineas += extra
        problemas += sum(1 for l in extra if l.startswith("FAIL"))
        nav.close()
    veredicto = "B6 PANTALLAS = PASS" if problemas == 0 else "B6 PANTALLAS = FAIL"
    SALIDA.write_text("\n".join([f"B6 · Revisión de pantallas en {BASE}", ""] + lineas + ["", f"Pantallas revisadas: {len(lineas)} · con problemas: {problemas}", veredicto]) + "\n", encoding="utf-8")
    print(veredicto)
    sys.exit(0 if problemas == 0 else 1)


if __name__ == "__main__":
    main()
