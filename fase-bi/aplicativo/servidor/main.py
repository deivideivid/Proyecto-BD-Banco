"""Servidor del aplicativo del Banco Andino.

En B4 solo tiene la sección Estadísticas (solo lectura). En B5 le agregamos el inicio de
sesión, los perfiles y las operaciones.

Arranque local:   uvicorn servidor.main:app --port 8000   (desde la carpeta aplicativo)
En la nube:       uvicorn servidor.main:app --host 0.0.0.0 --port $PORT
"""
import threading
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, RedirectResponse
from psycopg import OperationalError
from psycopg_pool import PoolTimeout
from fastapi.staticfiles import StaticFiles

from . import db, estadisticas

WEB = Path(__file__).resolve().parent.parent / "web"


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    db.abrir()
    threading.Thread(target=estadisticas.precalentar, daemon=True).start()
    yield
    db.cerrar()


app = FastAPI(title="Banco Andino · Aplicativo", version="0.4.0", lifespan=ciclo_de_vida)
app.include_router(estadisticas.router)

SIN_BASE = ("No pudimos conectarnos a la base de datos. Revise que PostgreSQL esté prendido y que "
            "la contraseña que escribió al arrancar sea la correcta.")


@app.exception_handler(PoolTimeout)
@app.exception_handler(OperationalError)
def base_no_disponible(request: Request, exc: Exception):
    """Si la base no responde, la página muestra el motivo en vez de quedarse cargando."""
    return JSONResponse(status_code=503, content={"detail": SIN_BASE})


@app.get("/salud", tags=["Servicio"])
def salud():
    """No consulta la base: sirve para despertar el servidor sin gastar horas de la base en la nube."""
    return {"estado": "ok"}


@app.get("/", include_in_schema=False)
def inicio():
    return RedirectResponse("/estadisticas.html")


app.mount("/", StaticFiles(directory=WEB), name="web")
