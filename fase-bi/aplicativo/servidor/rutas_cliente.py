"""Perfil Cliente (banca en línea): sus cuentas, sus movimientos y transferencias.

Todo pasa por las funciones app.fn_cliente_*, que en la base vuelven a revisar que la cuenta
sea del cliente. El servidor solo les pasa el cliente de la sesión, nunca uno que venga de la
pantalla.
"""
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import Field

from .comun import ConClave, Monto, Texto, con_rechazo, filas, limpiar
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/cliente", tags=["Cliente"])
cliente = requiere("CLIENTE")


class Transferencia(ConClave):
    cuenta_origen_id: int
    numero_destino: str = Field(pattern=r"^\s*[0-9]{11}\s*$")
    monto: Decimal = Monto
    descripcion: str | None = Texto


@router.get("/cuentas")
def mis_cuentas(s: Sesion = Depends(cliente)):
    return filas(s, "SELECT * FROM app.fn_cliente_cuentas(%s)", (s.cliente_id,))


@router.get("/cuentas/{cuenta_id}/movimientos")
def movimientos(cuenta_id: int, desde: date | None = None, hasta: date | None = None,
                limite: int = Query(100, ge=1, le=500), s: Sesion = Depends(cliente)):
    return filas(s, "SELECT * FROM app.fn_cliente_movimientos(%s, %s, %s, %s, %s)",
                 (s.cliente_id, cuenta_id, desde, hasta, limite))


@router.get("/resumen")
def resumen_mensual(s: Sesion = Depends(cliente)):
    return filas(s, "SELECT * FROM app.fn_cliente_resumen_mensual(%s)", (s.cliente_id,))


@router.post("/transferir")
def transferir(t: Transferencia, s: Sesion = Depends(cliente)):
    clave = t.clave_o_nueva()

    def operar(con):
        tx = con.execute("SELECT app.fn_cliente_transferir(%s, %s, %s, %s, %s, %s) AS id",
                         (s.cliente_id, t.cuenta_origen_id, t.numero_destino.strip(), t.monto, clave, t.descripcion)).fetchone()["id"]
        cuenta = con.execute("SELECT * FROM app.fn_cliente_cuentas(%s) WHERE cuenta_id = %s",
                             (s.cliente_id, t.cuenta_origen_id)).fetchone()
        return {"transaccion_id": tx, "cuenta_origen": limpiar(cuenta)}

    def rechazo(con, motivo):
        return con.execute("SELECT app.fn_cliente_registrar_rechazo(%s, %s, %s, %s, %s) AS id",
                           (s.cliente_id, t.cuenta_origen_id, t.numero_destino.strip(), t.monto, motivo)).fetchone()["id"]

    return con_rechazo(s, operar, rechazo)
