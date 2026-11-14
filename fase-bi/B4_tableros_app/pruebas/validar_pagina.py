"""B4 · Abre la página de Estadísticas en un navegador y compara lo que se ve con los valores
oficiales de SQL (b2_05_kpi_referencia.sql), que en B3 también dieron igual en Power BI.

Uso (con el aplicativo corriendo):
    python fase-bi/B4_tableros_app/pruebas/validar_pagina.py http://localhost:8000
Desde B5 hay que iniciar sesión: entra como demo.admin con la contraseña de
fase-bi/aplicativo/accesos_demo.local.txt.
Necesita:  pip install playwright  y  python -m playwright install chromium
"""
import re
import sys
from decimal import Decimal
from pathlib import Path

from playwright.sync_api import sync_playwright

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
SALIDA = Path(__file__).resolve().parent.parent / "salidas" / "validacion_pagina.txt"
CAPTURAS = Path(__file__).resolve().parent.parent / "capturas"
ACCESOS = Path(__file__).resolve().parents[2] / "aplicativo" / "accesos_demo.local.txt"


def ingresar(page):
    """Entra como administrador (ve todo el banco, igual que Power BI)."""
    clave = None
    if ACCESOS.exists():
        for linea in ACCESOS.read_text(encoding="utf-8").splitlines():
            m = re.search(r"usuario:\s*demo\.admin\s+contraseña:\s*(\S+)", linea)
            if m:
                clave = m.group(1)
    if not clave:
        sys.exit("No encontramos la contraseña de demo.admin en accesos_demo.local.txt")
    page.goto(f"{BASE}/ingresar.html")
    page.fill("#login", "demo.admin")
    page.fill("#clave", clave)
    page.click("#entrar")
    page.wait_for_url("**/estadisticas.html*", timeout=60000)

# Valores oficiales (catalogo_indicadores.md). A = todo; B = 2026-08 y AHORROS.
OFICIAL = {
    "K01": ("1000000", "11834"), "K02": ("1767796946066.07", "12643399220.02"),
    "K03": ("1768114.58", "18151.07"), "K04": ("1775276.18", "1077317.59"),
    "K05": ("2.35", "6.94"), "K06": ("9530", "135"), "K07": ("9070", "3947"),
    "K08": ("43557", "17851"), "K09": ("1004471074520.73", "126700742889.73"),
    "K10": ("1051931.27", "253402.31"), "K11": ("1000", "0"),
    "K12": ("99.6", "99.6"), "K13": ("6", "6"),
}
ESCENARIOS = {"A": "", "B": "mes=2026-08&producto=AHORROS"}
# Control y calidad no usa filtros (igual que en Power BI): en B solo comparamos K12 y K13 ahí.
SIN_FILTRO = {"K12", "K13"}
MONEDA = {"K02": "COP", "K04": "COP", "K09": "COP", "K03": "USD", "K10": "USD", "K05": "%"}


def como_se_ve(kpi, texto):
    """Formato colombiano: miles con punto y decimales con coma, más la moneda."""
    d = Decimal(texto)
    dec = 1 if kpi == "K12" else (2 if kpi in MONEDA else 0)
    ent, _, fr = f"{d:.{dec}f}".partition(".")
    ent = f"{int(ent):,}".replace(",", ".")
    return ent + ("," + fr if dec else "") + (MONEDA.get(kpi, ""))
PAGINAS = ["resumen", "transacciones", "clientes", "control"]


def esperar_pagina(page, pagina, consulta):
    page.wait_for_function(
        "([p, q]) => document.body.dataset.listo === p + '|' + q", arg=[pagina, consulta], timeout=120000
    )
    page.wait_for_timeout(1500)  # que terminen las animaciones de cifras y gráficas


def main():
    lineas, fallas, comparados = [], 0, set()
    with sync_playwright() as pw:
        nav = pw.chromium.launch()
        contexto = nav.new_context(viewport={"width": 1366, "height": 900})
        page = contexto.new_page()
        ingresar(page)
        for esc, consulta in ESCENARIOS.items():
            for pagina in PAGINAS:
                q = "" if pagina == "control" else consulta
                page.goto(f"{BASE}/estadisticas.html#{pagina}" + (f"?{q}" if q else ""))
                esperar_pagina(page, pagina, q)
                for tarjeta in page.query_selector_all(".tarjeta"):
                    kpi = tarjeta.get_attribute("data-kpi")
                    if kpi not in OFICIAL or (pagina == "control" and esc == "B" and kpi not in SIN_FILTRO):
                        continue
                    valor = tarjeta.query_selector(".valor")
                    dato = valor.get_attribute("data-valor")
                    texto_pantalla = " ".join(valor.inner_text().split())
                    visto = texto_pantalla.replace(" ", "")
                    esperado = OFICIAL[kpi][0 if esc == "A" else 1]
                    ok = Decimal(dato) == Decimal(esperado) and visto == como_se_ve(kpi, esperado)
                    fallas += not ok
                    comparados.add((esc, kpi))
                    lineas.append(f"{'PASS' if ok else 'FAIL'}  {esc}  {pagina:<14} {kpi}  oficial={esperado:<18} página={texto_pantalla}")
        # Capturas: computador y celular (sin animaciones, para que salgan completas)
        page = nav.new_context(viewport={"width": 1366, "height": 900}, reduced_motion="reduce").new_page()
        ingresar(page)
        for pagina in PAGINAS:
            page.goto(f"{BASE}/estadisticas.html#{pagina}")
            esperar_pagina(page, pagina, "")
            page.screenshot(path=str(CAPTURAS / f"computador_{pagina}.png"), full_page=True)
        movil = nav.new_context(viewport={"width": 390, "height": 844}, device_scale_factor=2, is_mobile=True, has_touch=True,
                                reduced_motion="reduce").new_page()
        ingresar(movil)
        for pagina in PAGINAS:
            movil.goto(f"{BASE}/estadisticas.html#{pagina}")
            esperar_pagina(movil, pagina, "")
            movil.screenshot(path=str(CAPTURAS / f"celular_{pagina}.png"), full_page=True)
        movil.goto(f"{BASE}/estadisticas.html#transacciones?mes=2026-08&producto=AHORROS")
        esperar_pagina(movil, "transacciones", "mes=2026-08&producto=AHORROS")
        movil.screenshot(path=str(CAPTURAS / "celular_transacciones_escenario_B.png"), full_page=True)
        nav.close()

    faltan = [f"{e} {k}" for e in ESCENARIOS for k in OFICIAL if (e, k) not in comparados]
    resumen = (f"Comparaciones: {len(lineas)} · indicadores distintos cubiertos: {len(comparados)} de 26 · "
               f"fallas: {fallas}" + (f" · sin comparar: {', '.join(faltan)}" if faltan else ""))
    veredicto = "B4 PÁGINA = PASS" if fallas == 0 and not faltan else "B4 PÁGINA = FAIL"
    texto = "\n".join(["B4 · Página de Estadísticas contra los valores oficiales de SQL", f"Servidor: {BASE}", ""]
                      + lineas + ["", resumen, veredicto])
    SALIDA.write_text(texto + "\n", encoding="utf-8")
    print(texto)
    sys.exit(0 if veredicto.endswith("PASS") else 1)


if __name__ == "__main__":
    main()
