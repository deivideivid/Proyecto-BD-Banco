"""Sección Estadísticas (B4): los mismos tableros de Power BI, con gráficas propias.

Todo se calcula en la base con las funciones de b4_01_funciones_estadisticas.sql. Aquí solo
pedimos los datos, los guardamos un rato en memoria y los entregamos como JSON a la página.
La conexión es de solo lectura (rol banco_bi).

Desde B5 hay que iniciar sesión: el Administrador ve todo, el Supervisor ve todo pero solo de
su oficina, y el Auditor de datos solo la página Control y calidad.
"""
import threading
import time
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query

from . import db
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/estadisticas", tags=["Estadísticas"])
con_estadisticas = requiere("ADMINISTRADOR", "SUPERVISOR", "AUDITOR")
PAGINAS_DEL_AUDITOR = {"control"}

# Qué muestra cada página. Es lo mismo que B3_powerbi/powerbi/generar_paginas.py.
PAGINAS = {
    "resumen": {
        "titulo": "Resumen",
        "filtros": True,
        "indicadores": ["K01", "K02", "K07", "K08", "K09", "K05"],
        "graficas": ["monto_mes", "tx_tipo"],
    },
    "transacciones": {
        "titulo": "Transacciones",
        "filtros": True,
        "indicadores": ["K01", "K04", "K03", "K05", "TXR", "K06"],
        "graficas": ["tx_hora", "tx_dia", "rechazo_motivo", "monto_tipo"],
    },
    "clientes": {
        "titulo": "Clientes y cuentas",
        "filtros": True,
        "indicadores": ["CTA", "K08", "K11", "K09", "K10", "K07"],
        "graficas": ["cuentas_estado", "cuentas_producto", "saldo_departamento"],
        "tablas": ["top_clientes"],
    },
    "control": {
        "titulo": "Control y calidad",
        "filtros": False,  # los controles son de toda la base, igual que en Power BI
        "indicadores": ["K12", "K13", "K01", "CTA"],
        "graficas": [],
        "tablas": ["controles", "pruebas"],
    },
}

_cache: dict = {}
_cache_lock = threading.Lock()
_CACHE_MAX = 200
_opciones: dict | None = None


def _texto(v):
    """Los montos van como texto para no perder ni un centavo en el camino."""
    if isinstance(v, Decimal):
        return format(v, "f")
    return v


def _version_datos() -> int:
    """Si alguien recarga el modelo estrella (bi.cargar_bi), cambia y el caché se renueva."""
    fila = db.consultar("SELECT coalesce(max(carga_id), 0) AS v FROM bi.carga")
    return int(fila[0]["v"])


def opciones_filtro() -> dict:
    global _opciones
    if _opciones is None:
        res = {"mes": [], "producto": [], "departamento": []}
        for f in db.consultar("SELECT filtro, valor, etiqueta FROM bi.fn_opciones_filtro()"):
            res[f["filtro"]].append({"valor": f["valor"], "etiqueta": f["etiqueta"]})
        _opciones = res
    return _opciones


def _validar(nombre: str, valor: str | None) -> str | None:
    if valor in (None, ""):
        return None
    if valor not in {o["valor"] for o in opciones_filtro()[nombre]}:
        raise HTTPException(status_code=422, detail={"mensaje": f"El valor '{valor}' no existe en el filtro {nombre}.", "codigo": "FILTRO"})
    return valor


def calcular_pagina(pagina: str, mes=None, producto=None, departamento=None, oficina=None) -> dict:
    conf = PAGINAS[pagina]
    if not conf["filtros"]:
        mes = producto = departamento = oficina = None
    p = {"mes": mes, "producto": producto, "departamento": departamento, "oficina": oficina}
    inicio = time.perf_counter()

    indicadores = {}
    for f in db.consultar(
        "SELECT id, indicador, valor FROM bi.fn_indicadores(%(mes)s, %(producto)s, %(departamento)s, %(oficina)s)", p
    ):
        if f["id"] in conf["indicadores"]:
            indicadores[f["id"]] = {"nombre": f["indicador"], "valor": _texto(f["valor"])}

    graficas = {}
    for serie in conf["graficas"]:
        filas = db.consultar(
            "SELECT etiqueta, valor FROM bi.fn_serie(%(serie)s, %(mes)s, %(producto)s, %(departamento)s, %(oficina)s)",
            {**p, "serie": serie},
        )
        graficas[serie] = [{"etiqueta": f["etiqueta"], "valor": _texto(f["valor"])} for f in filas]

    tablas = {}
    for tabla in conf.get("tablas", []):
        if tabla == "top_clientes":
            filas = db.consultar(
                "SELECT * FROM bi.fn_top_clientes(%(producto)s, %(departamento)s, %(oficina)s, 10)", p
            )
        elif tabla == "controles":
            filas = db.consultar(
                "SELECT control_id, grupo, control, esperado, obtenido, resultado FROM bi.fact_control ORDER BY control_id"
            )
        else:  # pruebas del quality gate: primero las que no pasaron
            filas = db.consultar(
                "SELECT test_id, dimension, regla, severidad, resultado, obtenido FROM bi.calidad_prueba "
                "ORDER BY (resultado = 'PASS'), test_id"
            )
        tablas[tabla] = [{k: _texto(v) for k, v in f.items()} for f in filas]

    corte = db.consultar("SELECT to_char(fecha_corte, 'DD/MM/YYYY') AS f FROM bi.carga ORDER BY carga_id DESC LIMIT 1")
    return {
        "pagina": pagina,
        "fecha_corte": corte[0]["f"] if corte else None,
        "titulo": conf["titulo"],
        "filtros": p,
        "indicadores": indicadores,
        "graficas": graficas,
        "tablas": tablas,
        "calculado_en_ms": round((time.perf_counter() - inicio) * 1000),
    }


def pagina_con_cache(pagina: str, mes=None, producto=None, departamento=None, oficina=None) -> dict:
    llave = (pagina, mes, producto, departamento, oficina, _version_datos())
    with _cache_lock:
        if llave in _cache:
            return {**_cache[llave], "desde_cache": True}
    datos = calcular_pagina(pagina, mes, producto, departamento, oficina)
    with _cache_lock:
        if len(_cache) >= _CACHE_MAX:
            _cache.pop(next(iter(_cache)))
        _cache[llave] = datos
    return {**datos, "desde_cache": False}


def precalentar() -> None:
    """Al arrancar dejamos listas las 4 páginas sin filtros (las más pesadas)."""
    try:
        opciones_filtro()
        for pagina in PAGINAS:
            pagina_con_cache(pagina)
    except Exception as e:  # si la base no responde, la página lo dirá al abrirla
        print("No pudimos precalentar las estadísticas:", e)


@router.get("/filtros")
def filtros(s: Sesion = Depends(con_estadisticas)):
    return opciones_filtro()


@router.get("/{pagina}")
def ver_pagina(
    pagina: str,
    mes: str | None = Query(None, description="anio_mes, por ejemplo 2026-08"),
    producto: str | None = Query(None, description="producto_key, por ejemplo AHORROS"),
    departamento: str | None = Query(None, description="departamento de la oficina"),
    s: Sesion = Depends(con_estadisticas),
):
    if pagina not in PAGINAS:
        raise HTTPException(status_code=404, detail={"mensaje": "Esa página de estadísticas no existe.", "codigo": "PAGINA"})
    if s.perfil == "AUDITOR" and pagina not in PAGINAS_DEL_AUDITOR:
        raise HTTPException(status_code=403, detail={"mensaje": "El auditor de datos solo ve la página Control y calidad.", "codigo": "PERFIL"})
    oficina = s.oficina_id if s.perfil == "SUPERVISOR" else None   # el supervisor solo ve su oficina
    datos = pagina_con_cache(
        pagina, _validar("mes", mes), _validar("producto", producto), _validar("departamento", departamento), oficina
    )
    return {**datos, "alcance": s.oficina if oficina else "Todo el banco"}
