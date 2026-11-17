"""Lo que se ve sin iniciar sesión: el Equipo con sus hojas de vida.

Los datos salen de fase-bi/equipo/equipo.json y los PDF de fase-bi/equipo/hojas_de_vida/.
Solo se entregan los PDF que están en esa lista (nadie puede pedir otro archivo del servidor).
Si una hoja de vida todavía no está, la tarjeta dice "pendiente".
"""
import json
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

EQUIPO = Path(__file__).resolve().parents[2] / "equipo"
router = APIRouter(tags=["Público"])


def _iniciales(nombre: str) -> str:
    """Nombre + primer apellido: 'Juan Diego Ortiz Duero' -> JO, 'David González' -> DG."""
    p = [x for x in nombre.split() if x]
    if not p:
        return ""
    apellido = p[-2] if len(p) >= 4 else p[1] if len(p) >= 2 else ""
    return (p[0][0] + apellido[:1]).upper()


def _integrantes() -> list[dict]:
    try:
        return json.loads((EQUIPO / "equipo.json").read_text(encoding="utf-8"))["integrantes"]
    except (OSError, ValueError, KeyError):
        return []


@router.get("/api/equipo")
def equipo():
    salida = []
    for i in _integrantes():
        archivo = i.get("hoja_de_vida") or ""
        disponible = bool(archivo) and (EQUIPO / "hojas_de_vida" / archivo).is_file()
        salida.append({
            "nombre": i.get("nombre", ""),
            "iniciales": _iniciales(i.get("nombre", "")),
            "rol_proyecto": i.get("rol_proyecto") or "",
            "programa": i.get("programa") or "",
            "hoja_de_vida": f"/equipo/hv/{archivo}" if disponible else None,
        })
    return salida


@router.get("/equipo/hv/{archivo}", include_in_schema=False)
def hoja_de_vida(archivo: str):
    permitidos = {i.get("hoja_de_vida") for i in _integrantes()}
    ruta = EQUIPO / "hojas_de_vida" / archivo
    if archivo not in permitidos or not archivo.endswith(".pdf") or not ruta.is_file():
        raise HTTPException(status_code=404, detail={"mensaje": "Esa hoja de vida no está disponible.", "codigo": "BA016"})
    return FileResponse(ruta, media_type="application/pdf", headers={"Content-Disposition": f'inline; filename="{archivo}"'})
