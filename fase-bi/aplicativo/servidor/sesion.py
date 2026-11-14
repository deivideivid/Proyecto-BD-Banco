"""Inicio de sesión y control de perfiles.

- La contraseña se compara con el hash bcrypt que guarda app.acceso (nunca en texto plano).
- La sesión va en una cookie firmada (no se puede alterar sin la clave APP_SECRET), solo con el
  número de acceso y el perfil. En cada petición volvemos a preguntar a la base si ese acceso
  sigue vigente: si el administrador le quita el rol a alguien, pierde el acceso al instante.
- Si la persona no hace nada en 30 minutos, la sesión se cierra.
"""
import time

import bcrypt
import psycopg
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from . import db, errores

router = APIRouter(prefix="/api/sesion", tags=["Sesión"])

INACTIVIDAD_MAX = 30 * 60
# Hash de relleno: si el usuario no existe igual hacemos el cálculo, para no delatar con el tiempo
_HASH_RELLENO = bcrypt.hashpw(b"no-es-una-clave", bcrypt.gensalt(rounds=12))

# Qué rol de la base usa cada perfil
ROL_DE_PERFIL = {
    "CLIENTE": "banco_cliente_app",
    "CAJERO": "banco_cajero",
    "SUPERVISOR": "banco_supervisor",
    "AUDITOR": "banco_auditor",
    "ADMINISTRADOR": "banco_admin_seg",
}

# Lo que ve cada perfil en el menú (B6 lo dibuja)
MENU = {
    "CLIENTE": ["mis_cuentas", "transferir", "mis_estadisticas", "equipo", "tecnologias"],
    "CAJERO": ["caja", "equipo", "tecnologias"],
    "SUPERVISOR": ["caja", "aprobaciones", "estadisticas", "equipo", "tecnologias"],
    "AUDITOR": ["calidad", "auditoria", "estadisticas_control", "equipo", "tecnologias"],
    "ADMINISTRADOR": ["usuarios", "estadisticas", "equipo", "tecnologias"],
}


class Sesion(BaseModel):
    acceso_id: int
    login: str
    perfil: str
    usuario_id: int | None = None
    cliente_id: int | None = None
    oficina_id: int | None = None
    oficina: str | None = None
    nombre: str

    @property
    def rol(self) -> str:
        return ROL_DE_PERFIL[self.perfil]


class Ingreso(BaseModel):
    login: str = Field(min_length=1, max_length=60)
    clave: str = Field(min_length=1, max_length=200)


def _no_autenticado(mensaje="Inicie sesión para continuar."):
    return HTTPException(status_code=401, detail={"mensaje": mensaje, "codigo": "SESION"})


def sesion_actual(request: Request) -> Sesion:
    datos = request.session
    acceso_id = datos.get("acceso_id")
    if not acceso_id:
        raise _no_autenticado()
    if time.time() - datos.get("t", 0) > INACTIVIDAD_MAX:
        request.session.clear()
        raise _no_autenticado("Su sesión se cerró por inactividad. Vuelva a ingresar.")
    fila = db.uno("SELECT * FROM app.fn_sesion(%s)", (acceso_id,), rol="banco_app_acceso")
    if not fila:
        request.session.clear()
        raise _no_autenticado("Su acceso ya no está vigente.")
    request.session["t"] = int(time.time())
    return Sesion(**fila)


def requiere(*perfiles: str):
    """Dependencia: deja pasar solo a los perfiles indicados."""
    def _dep(s: Sesion = Depends(sesion_actual)) -> Sesion:
        if s.perfil not in perfiles:
            raise HTTPException(status_code=403, detail={"mensaje": "Su perfil no tiene acceso a esta sección.", "codigo": "PERFIL"})
        return s
    return _dep


@router.post("/ingresar")
def ingresar(datos: Ingreso, request: Request):
    login = datos.login.strip().lower()
    origen = request.client.host if request.client else None
    try:
        fila = db.uno("SELECT * FROM app.fn_acceso_buscar(%s)", (login,), rol="banco_app_acceso")
    except psycopg.Error as e:
        raise errores.traducir(e)
    hash_guardado = (fila or {}).get("clave_hash") or _HASH_RELLENO.decode()
    clave_ok = bcrypt.checkpw(datos.clave.encode("utf-8"), hash_guardado.encode("utf-8"))
    exitoso = bool(fila) and bool(fila.get("clave_hash")) and clave_ok and not fila["bloqueado"]
    db.consultar("SELECT app.fn_acceso_registrar(%s, %s, %s, %s)",
                 ((fila or {}).get("acceso_id"), login, exitoso, origen), rol="banco_app_acceso")
    if fila and fila["bloqueado"]:
        raise HTTPException(status_code=423, detail={
            "mensaje": "El acceso quedó bloqueado por varios intentos fallidos. Intente de nuevo en 15 minutos.",
            "codigo": "BLOQUEADO"})
    if not exitoso:
        raise HTTPException(status_code=401, detail={"mensaje": "Usuario o contraseña incorrectos.", "codigo": "CREDENCIALES"})
    request.session.clear()
    request.session.update({"acceso_id": fila["acceso_id"], "perfil": fila["perfil"], "t": int(time.time())})
    s = sesion_actual(request)
    return {"perfil": s.perfil, "nombre": s.nombre, "oficina": s.oficina, "menu": MENU[s.perfil]}


@router.post("/salir")
def salir(request: Request):
    request.session.clear()
    return {"ok": True}


@router.get("")
def ver(s: Sesion = Depends(sesion_actual)):
    return {"login": s.login, "perfil": s.perfil, "nombre": s.nombre, "oficina": s.oficina, "menu": MENU[s.perfil]}
