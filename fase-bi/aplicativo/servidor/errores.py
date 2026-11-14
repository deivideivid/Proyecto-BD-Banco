"""Traduce los errores de la base a mensajes en lenguaje sencillo.

Las funciones del banco fallan con códigos propios (clase BA, ver sql/14_functions.sql) y la
base niega con 42501 lo que un rol no puede hacer. Aquí cada código se vuelve un código HTTP y
un mensaje que la pantalla puede mostrar tal cual.
"""
import logging

import psycopg
from fastapi import HTTPException

log = logging.getLogger("banco")

# código de la base -> (código HTTP, mensaje para la persona)
MENSAJES = {
    "BA001": (403, "Su usuario no tiene permiso para esta operación."),
    "BA002": (409, "El estado de la cuenta no permite esta operación."),
    "BA003": (409, "Fondos insuficientes."),
    "BA004": (409, "La operación supera el límite diario de retiro de la cuenta."),
    "BA005": (422, "El monto no es válido: debe ser mayor que cero y tener máximo dos decimales."),
    "BA006": (422, "La transferencia no es válida."),
    "BA007": (409, "Ese registro no se puede modificar."),
    "BA008": (409, "Esa transacción no se puede reversar."),
    "BA009": (409, "No puede operar una cuenta de la que usted es titular."),
    "BA010": (403, "Esa cuenta no le pertenece."),
    "BA011": (409, "Ese cambio de estado no está permitido."),
    "BA012": (409, "La cuenta tiene saldo: no se puede cerrar."),
    "BA013": (409, "Ese ajuste no se puede aprobar o rechazar."),
    "BA014": (500, "La contabilidad de la operación no cuadra. No se hizo nada."),
    "BA015": (409, "Esa solicitud ya se había usado para otra operación. Intente de nuevo."),
    "BA016": (404, "No encontramos el registro."),
    "BA017": (422, "Algún dato no es válido."),
    "42501": (403, "La base de datos no permite esta operación a su perfil."),
    "23505": (409, "Ya existe un registro con esos datos."),
    "23514": (422, "Los datos no cumplen una regla del banco."),
    "23503": (422, "Algún dato hace referencia a algo que no existe."),
    "23502": (422, "Falta un dato obligatorio."),
    "22001": (422, "Algún texto es demasiado largo."),
    "22P02": (422, "Algún dato no tiene el formato correcto."),
    "22007": (422, "Alguna fecha no es válida."),
    "22008": (422, "Alguna fecha no es válida."),
}

# Rechazos del negocio que el banco deja registrados (RN-45)
MOTIVOS_RECHAZO = {
    "BA002": "Cuenta bloqueada o inactiva: no permite la operación",
    "BA003": "Fondos insuficientes",
    "BA004": "Excede el límite diario de retiro",
}


def codigo(error: psycopg.Error) -> str | None:
    return getattr(error, "sqlstate", None)


def traducir(error: psycopg.Error) -> HTTPException:
    estado = codigo(error)
    if estado in MENSAJES:
        http, mensaje = MENSAJES[estado]
        detalle_base = error.diag.message_primary if error.diag else None
        return HTTPException(status_code=http, detail={"mensaje": mensaje, "codigo": estado, "detalle": detalle_base})
    log.exception("Error de base no previsto (%s)", estado)
    return HTTPException(status_code=500, detail={"mensaje": "No pudimos completar la operación.", "codigo": estado})
