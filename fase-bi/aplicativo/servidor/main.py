"""Servidor del aplicativo del Banco Andino.

B4: sección Estadísticas. B5: inicio de sesión, los 5 perfiles y las operaciones contra la base.

Arranque local:   uvicorn servidor.main:app --port 8000   (desde la carpeta aplicativo)
En la nube:       uvicorn servidor.main:app --host 0.0.0.0 --port $PORT

Variables de entorno:
  DATABASE_URL  conexión a PostgreSQL con el usuario app_servidor (obligatoria)
  APP_SECRET    clave para firmar la cookie de sesión (obligatoria en la nube; en local
                iniciar_local.ps1 crea una nueva cada vez que arranca)
  APP_HTTPS     "1" si el sitio va por https (en la nube), para que la cookie solo viaje cifrada
"""
import logging
import os
import secrets
import threading
from contextlib import asynccontextmanager
from pathlib import Path

import psycopg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from psycopg import OperationalError
from psycopg_pool import PoolTimeout
from starlette.middleware.sessions import SessionMiddleware

from . import db, errores, estadisticas, rutas_admin, rutas_auditor, rutas_caja, rutas_cliente, rutas_supervisor, sesion

WEB = Path(__file__).resolve().parent.parent / "web"
logging.basicConfig(level=logging.INFO)


@asynccontextmanager
async def ciclo_de_vida(app: FastAPI):
    db.abrir()
    threading.Thread(target=estadisticas.precalentar, daemon=True).start()
    yield
    db.cerrar()


app = FastAPI(title="Banco Andino · Aplicativo", version="0.5.0", lifespan=ciclo_de_vida)

for r in (sesion.router, rutas_cliente.router, rutas_caja.router, rutas_supervisor.router,
          rutas_auditor.router, rutas_admin.router, estadisticas.router):
    app.include_router(r)


# ---------- Seguridad de las peticiones ----------
@app.middleware("http")
async def cabeceras_y_origen(request: Request, call_next):
    # Las operaciones solo se aceptan si vienen de nuestras pantallas: piden una cabecera propia
    # que otro sitio no puede poner sin permiso del navegador (protección contra CSRF).
    if request.method in ("POST", "PUT", "PATCH", "DELETE") and request.url.path.startswith("/api/"):
        if request.headers.get("x-banco-app") != "1":
            return JSONResponse(status_code=403, content={"detail": {"mensaje": "Solicitud no permitida.", "codigo": "ORIGEN"}})
    respuesta = await call_next(request)
    respuesta.headers["X-Content-Type-Options"] = "nosniff"
    respuesta.headers["X-Frame-Options"] = "DENY"
    respuesta.headers["Referrer-Policy"] = "same-origin"
    if not request.url.path.startswith(("/docs", "/redoc", "/openapi.json")):   # la documentación usa su propio JS
      respuesta.headers["Content-Security-Policy"] = (
          "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; "
          "connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'")
    if request.url.path.startswith("/api/"):
        respuesta.headers["Cache-Control"] = "no-store"
    return respuesta


secreto = os.environ.get("APP_SECRET") or secrets.token_urlsafe(32)
app.add_middleware(SessionMiddleware, secret_key=secreto, session_cookie="banco_sesion",
                   max_age=8 * 3600, same_site="strict", https_only=os.environ.get("APP_HTTPS") == "1")


# ---------- Errores en lenguaje sencillo ----------
SIN_BASE = ("No pudimos conectarnos a la base de datos. Revise que PostgreSQL esté prendido y que "
            "la contraseña que escribió al arrancar sea la correcta.")


@app.exception_handler(PoolTimeout)
@app.exception_handler(OperationalError)
def base_no_disponible(request: Request, exc: Exception):
    """Si la base no responde, la página muestra el motivo en vez de quedarse cargando."""
    return JSONResponse(status_code=503, content={"detail": {"mensaje": SIN_BASE, "codigo": "SIN_BASE"}})


@app.exception_handler(psycopg.Error)
def error_de_base(request: Request, exc: psycopg.Error):
    e = errores.traducir(exc)
    return JSONResponse(status_code=e.status_code, content={"detail": e.detail})


@app.exception_handler(RequestValidationError)
def datos_invalidos(request: Request, exc: RequestValidationError):
    campos = sorted({str(err["loc"][-1]) for err in exc.errors() if err.get("loc")})
    return JSONResponse(status_code=422, content={"detail": {
        "mensaje": "Revise los datos: " + ", ".join(campos) if campos else "Revise los datos enviados.",
        "codigo": "DATOS", "campos": campos}})


# ---------- Rutas sueltas ----------
@app.get("/salud", tags=["Servicio"])
def salud():
    """No consulta la base: sirve para despertar el servidor sin gastar horas de la base en la nube."""
    return {"estado": "ok"}


@app.get("/", include_in_schema=False)
def inicio():
    return RedirectResponse("/ingresar.html")


app.mount("/", StaticFiles(directory=WEB), name="web")
