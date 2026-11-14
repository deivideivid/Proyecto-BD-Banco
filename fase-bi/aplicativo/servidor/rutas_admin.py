"""Administrador: usuarios internos y sus roles. No ve ni mueve dinero.

Usa el rol banco_admin_seg, que solo puede leer y escribir en seg.usuario y seg.usuario_rol.
Los roles no se borran: se revocan con fecha (vigente_hasta). Nadie se asigna roles a sí mismo
(RN-50, lo frena la base). Todo queda en la auditoría con el administrador que lo hizo.
"""
from typing import Literal

import psycopg
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from . import db, errores
from .comun import filas, limpiar
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/admin", tags=["Administrador"])
admin = requiere("ADMINISTRADOR")

ROLES_ASIGNABLES = ("CAJERO", "SUPERVISOR", "AUDITOR", "ADMIN_SEGURIDAD")   # CANAL_DIGITAL es técnico
PROTEGIDOS = ("canal.digital",)


class NuevoUsuario(BaseModel):
    login: str = Field(pattern=r"^[a-z0-9._]{4,40}$")
    tipo_documento: Literal["CC", "CE", "PA", "PPT"]
    numero_documento: str = Field(pattern=r"^[A-Z0-9]{5,15}$")
    nombres: str = Field(min_length=1, max_length=120)
    apellidos: str = Field(min_length=1, max_length=120)
    oficina_id: int | None = None


class Rol(BaseModel):
    rol: Literal["CAJERO", "SUPERVISOR", "AUDITOR", "ADMIN_SEGURIDAD"]


class Estado(BaseModel):
    estado: Literal["ACTIVO", "INACTIVO"]


def _escribir(s: Sesion, consulta: str, parametros: tuple) -> dict | None:
    try:
        with db.transaccion(s.rol, s.usuario_id) as con:
            return limpiar(con.execute(consulta, parametros).fetchone())
    except psycopg.Error as e:
        raise errores.traducir(e)


def _usuario(s: Sesion, usuario_id: int) -> dict:
    u = filas(s, "SELECT usuario_id, login, estado FROM seg.usuario WHERE usuario_id = %s", (usuario_id,))
    if not u:
        raise HTTPException(status_code=404, detail={"mensaje": "No encontramos el usuario.", "codigo": "BA016"})
    if u[0]["login"] in PROTEGIDOS:
        raise HTTPException(status_code=409, detail={"mensaje": "Ese es un usuario técnico del sistema y no se modifica aquí.", "codigo": "PROTEGIDO"})
    return u[0]


@router.get("/usuarios")
def usuarios(q: str | None = Query(None, max_length=60), rol: str | None = Query(None, max_length=30),
             s: Sesion = Depends(admin)):
    return filas(s, """
      SELECT u.usuario_id, u.login, u.nombres, u.apellidos, u.tipo_documento, u.numero_documento, u.estado,
             o.nombre AS oficina,
             coalesce((SELECT string_agg(r.codigo, ', ' ORDER BY r.codigo) FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id
                       WHERE ur.usuario_id = u.usuario_id AND ur.vigente_hasta IS NULL), '') AS roles
      FROM seg.usuario u LEFT JOIN ref.oficina o ON o.oficina_id = u.oficina_id
      WHERE (%(q)s::text IS NULL OR u.login ILIKE %(qq)s OR (u.nombres || ' ' || u.apellidos) ILIKE %(qq)s)
        AND (%(rol)s::text IS NULL OR EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id
                                         WHERE ur.usuario_id = u.usuario_id AND ur.vigente_hasta IS NULL AND r.codigo = %(rol)s))
      ORDER BY u.usuario_id LIMIT 100""", {"q": q, "qq": f"%{q}%" if q else None, "rol": rol})


@router.get("/catalogos")
def catalogos(s: Sesion = Depends(admin)):
    return {"roles": filas(s, "SELECT codigo, nombre FROM seg.rol WHERE codigo = ANY(%s) ORDER BY rol_id", (list(ROLES_ASIGNABLES),)),
            "oficinas": filas(s, "SELECT oficina_id, nombre FROM ref.oficina WHERE activa ORDER BY nombre")}


@router.post("/usuarios")
def crear_usuario(u: NuevoUsuario, s: Sesion = Depends(admin)):
    fila = _escribir(s, """INSERT INTO seg.usuario (login, tipo_documento, numero_documento, nombres, apellidos, oficina_id)
                           VALUES (%s, %s, %s, %s, %s, %s) RETURNING usuario_id""",
                     (u.login, u.tipo_documento, u.numero_documento, u.nombres.strip(), u.apellidos.strip(), u.oficina_id))
    return fila


@router.post("/usuarios/{usuario_id}/roles")
def asignar_rol(usuario_id: int, r: Rol, s: Sesion = Depends(admin)):
    _usuario(s, usuario_id)
    ya = filas(s, """SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol x ON x.rol_id = ur.rol_id
                     WHERE ur.usuario_id = %s AND x.codigo = %s AND ur.vigente_hasta IS NULL""", (usuario_id, r.rol))
    if ya:
        raise HTTPException(status_code=409, detail={"mensaje": "El usuario ya tiene ese rol.", "codigo": "DUPLICADO"})
    return _escribir(s, """INSERT INTO seg.usuario_rol (usuario_id, rol_id, asignado_por)
                           SELECT %s, rol_id, %s FROM seg.rol WHERE codigo = %s
                           RETURNING usuario_id, vigente_desde""", (usuario_id, s.usuario_id, r.rol))


@router.post("/usuarios/{usuario_id}/roles/{rol}/revocar")
def revocar_rol(usuario_id: int, rol: Literal["CAJERO", "SUPERVISOR", "AUDITOR", "ADMIN_SEGURIDAD"], s: Sesion = Depends(admin)):
    _usuario(s, usuario_id)
    if usuario_id == s.usuario_id and rol == "ADMIN_SEGURIDAD":
        raise HTTPException(status_code=409, detail={"mensaje": "No puede quitarse su propio rol de administrador.", "codigo": "PROPIO"})
    fila = _escribir(s, """UPDATE seg.usuario_rol ur SET vigente_hasta = clock_timestamp()
                           FROM seg.rol r WHERE r.rol_id = ur.rol_id AND ur.usuario_id = %s AND r.codigo = %s
                             AND ur.vigente_hasta IS NULL
                           RETURNING ur.usuario_id, ur.vigente_hasta""", (usuario_id, rol))
    if not fila:
        raise HTTPException(status_code=404, detail={"mensaje": "El usuario no tenía ese rol vigente.", "codigo": "BA016"})
    return fila


@router.post("/usuarios/{usuario_id}/estado")
def cambiar_estado(usuario_id: int, e: Estado, s: Sesion = Depends(admin)):
    _usuario(s, usuario_id)
    if usuario_id == s.usuario_id:
        raise HTTPException(status_code=409, detail={"mensaje": "No puede desactivarse a sí mismo.", "codigo": "PROPIO"})
    return _escribir(s, "UPDATE seg.usuario SET estado = %s WHERE usuario_id = %s RETURNING usuario_id, estado", (e.estado, usuario_id))
