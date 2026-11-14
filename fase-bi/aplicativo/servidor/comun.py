"""Piezas que comparten las rutas de operaciones."""
import uuid
from decimal import Decimal

import psycopg
from fastapi import HTTPException
from pydantic import BaseModel, Field

from . import db, errores
from .sesion import Sesion


class ConClave(BaseModel):
    """La pantalla manda una clave única por operación (idempotencia, RN-38): si la misma
    solicitud llega dos veces, la base no la cobra dos veces. Si no la manda, la creamos aquí."""
    clave: uuid.UUID | None = None

    def clave_o_nueva(self) -> uuid.UUID:
        return self.clave or uuid.uuid4()


Monto = Field(gt=0, max_digits=18, decimal_places=2)
Texto = Field(default=None, max_length=140)


def texto(v) -> str | None:
    if isinstance(v, Decimal):
        return format(v, "f")
    return v


def limpiar(fila: dict | None) -> dict | None:
    return None if fila is None else {k: texto(v) for k, v in fila.items()}


def valor(s: Sesion, consulta: str, parametros: tuple = ()):
    """Corre una función del banco con el rol del perfil y devuelve el primer valor."""
    try:
        with db.transaccion(s.rol, s.usuario_id) as con:
            fila = con.execute(consulta, parametros).fetchone()
            return None if fila is None else next(iter(fila.values()))
    except psycopg.Error as e:
        raise errores.traducir(e)


def filas(s: Sesion, consulta: str, parametros: tuple | dict = (), rol: str | None = None) -> list[dict]:
    try:
        return [limpiar(f) for f in db.consultar(consulta, parametros, rol=rol or s.rol, usuario_id=s.usuario_id)]
    except psycopg.Error as e:
        raise errores.traducir(e)


def con_rechazo(s: Sesion, operacion, registrar_rechazo):
    """Corre la operación. Si el banco la rechaza por estado, fondos o límite, deja el rechazo
    registrado con su motivo (RN-45) en otra transacción y responde 409 con ese número."""
    try:
        with db.transaccion(s.rol, s.usuario_id) as con:
            return operacion(con)
    except psycopg.Error as e:
        estado = errores.codigo(e)
        error = errores.traducir(e)
        if estado in errores.MOTIVOS_RECHAZO:
            try:
                with db.transaccion(s.rol, s.usuario_id) as con:
                    rechazo_id = registrar_rechazo(con, errores.MOTIVOS_RECHAZO[estado])
                error.detail["rechazo_id"] = rechazo_id
            except psycopg.Error:
                errores.log.exception("No se pudo registrar el rechazo")
        raise error


def cuenta_de_mi_oficina(s: Sesion, cuenta_id: int) -> dict:
    """Cajero y supervisor operan las cuentas de su oficina (B1, perfiles.md)."""
    c = db.uno("SELECT cuenta_id, numero_cuenta, oficina_id, estado_cuenta, moneda_codigo FROM core.cuenta WHERE cuenta_id = %s",
               (cuenta_id,), rol=s.rol)
    if not c:
        raise HTTPException(status_code=404, detail={"mensaje": "No encontramos la cuenta.", "codigo": "BA016"})
    if s.oficina_id is not None and c["oficina_id"] != s.oficina_id:
        raise HTTPException(status_code=403, detail={"mensaje": "Esa cuenta es de otra oficina.", "codigo": "OFICINA"})
    return c
