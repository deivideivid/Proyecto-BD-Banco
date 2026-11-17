"""Caja: lo que hacen el Cajero y el Supervisor en la oficina.

Cada operación llama a la función segura del banco (14_functions.sql) con el empleado de la
sesión. La base valida su permiso (seg.rol_permiso), las reglas del negocio y deja la auditoría.
El servidor además limita las cuentas a las de la oficina del empleado.
"""
import re
from datetime import date
from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from .comun import ConClave, Monto, Texto, con_rechazo, cuenta_de_mi_oficina, filas, valor
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/caja", tags=["Caja (Cajero y Supervisor)"])
caja = requiere("CAJERO", "SUPERVISOR")


# ---------- Consultas ----------
@router.get("/buscar")
def buscar(q: str = Query(min_length=3, max_length=80), s: Sesion = Depends(caja)):
    """Por número de cuenta (11 dígitos), por documento exacto o por nombre (en su oficina)."""
    q = q.strip()
    base = """
      SELECT c.cliente_id, c.tipo_cliente, c.tipo_documento, c.numero_documento,
             coalesce(pn.nombres || ' ' || pn.apellidos, pj.razon_social) AS nombre, c.estado_cliente,
             (SELECT count(*) FROM core.titularidad_cuenta t JOIN core.cuenta cu ON cu.cuenta_id = t.cuenta_id
              WHERE t.cliente_id = c.cliente_id AND t.vigente_hasta IS NULL AND cu.oficina_id = %(of)s) AS cuentas_en_oficina
      FROM core.cliente c
      LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
      LEFT JOIN core.persona_juridica pj ON pj.cliente_id = c.cliente_id
    """
    p = {"of": s.oficina_id, "q": q}
    if re.fullmatch(r"[0-9]{11}", q):
        donde = """WHERE c.cliente_id IN (SELECT t.cliente_id FROM core.titularidad_cuenta t JOIN core.cuenta cu ON cu.cuenta_id = t.cuenta_id
                                          WHERE cu.numero_cuenta = %(q)s AND t.vigente_hasta IS NULL AND cu.oficina_id = %(of)s)"""
    elif re.fullmatch(r"[0-9A-Za-z]{5,15}", q) and any(ch.isdigit() for ch in q):
        donde = "WHERE c.numero_documento = upper(%(q)s)"   # documento exacto: también clientes sin cuentas aún
    else:
        p["q"] = "%" + q.replace("%", "").replace("_", "") + "%"
        donde = """WHERE (pn.nombres || ' ' || pn.apellidos ILIKE %(q)s OR pj.razon_social ILIKE %(q)s)
                     AND EXISTS (SELECT 1 FROM core.titularidad_cuenta t JOIN core.cuenta cu ON cu.cuenta_id = t.cuenta_id
                                 WHERE t.cliente_id = c.cliente_id AND t.vigente_hasta IS NULL AND cu.oficina_id = %(of)s)"""
    return filas(s, base + donde + " ORDER BY nombre LIMIT 30", p)


@router.get("/clientes/{cliente_id}")
def ficha_cliente(cliente_id: int, s: Sesion = Depends(caja)):
    datos = filas(s, """
      SELECT c.cliente_id, c.tipo_cliente, c.tipo_documento, c.numero_documento, c.estado_cliente, c.fecha_vinculacion,
             c.email, c.telefono, m.nombre AS municipio,
             coalesce(pn.nombres || ' ' || pn.apellidos, pj.razon_social) AS nombre
      FROM core.cliente c
      JOIN ref.municipio m ON m.municipio_codigo = c.municipio_codigo
      LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
      LEFT JOIN core.persona_juridica pj ON pj.cliente_id = c.cliente_id
      WHERE c.cliente_id = %s""", (cliente_id,))
    if not datos:
        raise HTTPException(status_code=404, detail={"mensaje": "No encontramos el cliente.", "codigo": "BA016"})
    cuentas = filas(s, """
      SELECT cu.cuenta_id, cu.numero_cuenta, cu.producto_codigo, cu.moneda_codigo, cu.estado_cuenta, t.rol_titular,
             cu.saldo_contable, cu.saldo_disponible, cu.limite_retiro_diario, cu.oficina_id = %s AS de_mi_oficina
      FROM core.titularidad_cuenta t JOIN core.cuenta cu ON cu.cuenta_id = t.cuenta_id
      WHERE t.cliente_id = %s AND t.vigente_hasta IS NULL
      ORDER BY cu.numero_cuenta""", (s.oficina_id, cliente_id))
    return {**datos[0], "cuentas": cuentas}


@router.get("/cuentas/{cuenta_id}")
def ver_cuenta(cuenta_id: int, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, cuenta_id)
    cuenta = filas(s, """SELECT cuenta_id, numero_cuenta, producto_codigo, moneda_codigo, estado_cuenta, saldo_contable,
                                saldo_retenido, saldo_disponible, cupo_sobregiro, limite_retiro_diario, fecha_apertura
                         FROM core.cuenta WHERE cuenta_id = %s""", (cuenta_id,))[0]
    movimientos = filas(s, """
      SELECT transaccion_id, tipo_codigo, estado_codigo, monto, descripcion, motivo_rechazo,
             coalesce(fecha_contabilizacion, fecha_solicitud) AS fecha,
             CASE WHEN cuenta_destino_id = %(c)s THEN 'ENTRA' ELSE 'SALE' END AS sentido
      FROM fin.transaccion_financiera
      WHERE cuenta_origen_id = %(c)s OR cuenta_destino_id = %(c)s
      ORDER BY coalesce(fecha_contabilizacion, fecha_solicitud) DESC, transaccion_id DESC LIMIT 20""", {"c": cuenta_id})
    return {**cuenta, "movimientos": movimientos}


@router.get("/municipios")
def municipios(q: str = Query(min_length=2, max_length=60), s: Sesion = Depends(caja)):
    return filas(s, """SELECT m.municipio_codigo, m.nombre, d.nombre AS departamento
                       FROM ref.municipio m JOIN ref.departamento d ON d.departamento_codigo = m.departamento_codigo
                       WHERE m.nombre ILIKE %s ORDER BY m.nombre LIMIT 20""", ("%" + q.strip() + "%",))


# ---------- Clientes y cuentas ----------
class ClienteNatural(BaseModel):
    tipo_documento: Literal["CC", "CE", "PA", "PPT"]
    numero_documento: str = Field(pattern=r"^[A-Za-z0-9]{5,15}$")
    nombres: str = Field(min_length=1, max_length=120)
    apellidos: str = Field(min_length=1, max_length=120)
    fecha_nacimiento: date
    municipio_codigo: str = Field(pattern=r"^[0-9]{5}$")
    email: str | None = Field(default=None, max_length=254)
    telefono: str | None = Field(default=None, max_length=20)


class ClienteJuridico(BaseModel):
    nit: str = Field(pattern=r"^[0-9]{9}$")
    razon_social: str = Field(min_length=1, max_length=200)
    fecha_constitucion: date
    actividad_economica: str = Field(pattern=r"^[0-9]{4}$")
    municipio_codigo: str = Field(pattern=r"^[0-9]{5}$")
    email: str | None = Field(default=None, max_length=254)
    telefono: str | None = Field(default=None, max_length=20)


class NuevaCuenta(BaseModel):
    cliente_id: int
    producto_codigo: Literal["AHORROS", "CORRIENTE", "NOMINA", "EMPRESARIAL"]
    moneda_codigo: Literal["COP", "USD"]
    limite_retiro_diario: Decimal = Monto
    cupo_sobregiro: Decimal = Field(default=Decimal("0"), ge=0, max_digits=18, decimal_places=2)


@router.post("/clientes/natural")
def crear_natural(c: ClienteNatural, s: Sesion = Depends(caja)):
    cid = valor(s, "SELECT core.fn_crear_cliente_natural(%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (s.usuario_id, c.tipo_documento, c.numero_documento.upper(), c.nombres.strip(), c.apellidos.strip(),
                 c.fecha_nacimiento, c.municipio_codigo, c.email, c.telefono))
    return {"cliente_id": cid}


@router.post("/clientes/juridico")
def crear_juridico(c: ClienteJuridico, s: Sesion = Depends(caja)):
    cid = valor(s, "SELECT core.fn_crear_cliente_juridico(%s, %s, %s, %s, %s, %s, %s, %s)",
                (s.usuario_id, c.nit, c.razon_social.strip(), c.fecha_constitucion, c.actividad_economica,
                 c.municipio_codigo, c.email, c.telefono))
    return {"cliente_id": cid}


@router.post("/cuentas")
def abrir_cuenta(c: NuevaCuenta, s: Sesion = Depends(caja)):
    if s.oficina_id is None:
        raise HTTPException(status_code=409, detail={"mensaje": "Su usuario no tiene oficina asignada.", "codigo": "OFICINA"})
    cuenta_id = valor(s, "SELECT core.fn_abrir_cuenta(%s, %s, %s, %s, %s, %s, %s)",
                      (s.usuario_id, c.cliente_id, c.producto_codigo, c.moneda_codigo, s.oficina_id,
                       c.limite_retiro_diario, c.cupo_sobregiro))
    numero = filas(s, "SELECT numero_cuenta, estado_cuenta FROM core.cuenta WHERE cuenta_id = %s", (cuenta_id,))[0]
    return {"cuenta_id": cuenta_id, **numero}


@router.post("/cuentas/{cuenta_id}/activar")
def activar(cuenta_id: int, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, cuenta_id)
    return {"evento_id": valor(s, "SELECT core.fn_activar_cuenta(%s, %s)", (s.usuario_id, cuenta_id))}


class Motivo(BaseModel):
    motivo: str = Field(min_length=3, max_length=200)


@router.post("/cuentas/{cuenta_id}/bloquear")
def bloquear(cuenta_id: int, m: Motivo, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, cuenta_id)
    return {"evento_id": valor(s, "SELECT core.fn_bloquear_cuenta(%s, %s, %s)", (s.usuario_id, cuenta_id, m.motivo))}


# ---------- Dinero ----------
class Movimiento(ConClave):
    cuenta_id: int
    monto: Decimal = Monto
    descripcion: str | None = Texto


class TransferenciaCaja(ConClave):
    cuenta_origen_id: int
    numero_destino: str = Field(pattern=r"^\s*[0-9]{11}\s*$")
    monto: Decimal = Monto
    descripcion: str | None = Texto


class Ajuste(ConClave):
    cuenta_id: int
    monto: Decimal = Monto
    sentido: Literal["C", "D"]
    descripcion: str = Field(min_length=3, max_length=140)


def _saldo(con, cuenta_id):
    f = con.execute("SELECT saldo_contable, saldo_disponible FROM core.cuenta WHERE cuenta_id = %s", (cuenta_id,)).fetchone()
    return {k: format(v, "f") for k, v in f.items()}


@router.post("/consignar")
def consignar(m: Movimiento, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, m.cuenta_id)
    clave = m.clave_o_nueva()

    def operar(con):
        tx = con.execute("SELECT fin.fn_consignar(%s, %s, %s, %s, %s) AS id",
                         (s.usuario_id, m.cuenta_id, m.monto, clave, m.descripcion)).fetchone()["id"]
        return {"transaccion_id": tx, "saldo": _saldo(con, m.cuenta_id)}

    def rechazo(con, motivo):
        return con.execute("SELECT fin.fn_registrar_rechazo(%s, 'CONSIGNACION', NULL, %s, %s, gen_random_uuid(), %s) AS id",
                           (s.usuario_id, m.cuenta_id, m.monto, motivo)).fetchone()["id"]

    return con_rechazo(s, operar, rechazo)


@router.post("/retirar")
def retirar(m: Movimiento, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, m.cuenta_id)
    clave = m.clave_o_nueva()

    def operar(con):
        tx = con.execute("SELECT fin.fn_retirar(%s, %s, %s, %s, %s) AS id",
                         (s.usuario_id, m.cuenta_id, m.monto, clave, m.descripcion)).fetchone()["id"]
        return {"transaccion_id": tx, "saldo": _saldo(con, m.cuenta_id)}

    def rechazo(con, motivo):
        return con.execute("SELECT fin.fn_registrar_rechazo(%s, 'RETIRO', %s, NULL, %s, gen_random_uuid(), %s) AS id",
                           (s.usuario_id, m.cuenta_id, m.monto, motivo)).fetchone()["id"]

    return con_rechazo(s, operar, rechazo)


@router.post("/transferir")
def transferir(t: TransferenciaCaja, s: Sesion = Depends(caja)):
    cuenta_de_mi_oficina(s, t.cuenta_origen_id)
    destino = filas(s, "SELECT cuenta_id FROM core.cuenta WHERE numero_cuenta = %s", (t.numero_destino.strip(),))
    if not destino:
        raise HTTPException(status_code=404, detail={"mensaje": "No existe la cuenta de destino.", "codigo": "BA016"})
    destino_id = destino[0]["cuenta_id"]
    clave = t.clave_o_nueva()

    def operar(con):
        tx = con.execute("SELECT fin.fn_transferir(%s, %s, %s, %s, %s, %s) AS id",
                         (s.usuario_id, t.cuenta_origen_id, destino_id, t.monto, clave, t.descripcion)).fetchone()["id"]
        return {"transaccion_id": tx, "saldo_origen": _saldo(con, t.cuenta_origen_id)}

    def rechazo(con, motivo):
        return con.execute("SELECT fin.fn_registrar_rechazo(%s, 'TRANSFERENCIA', %s, %s, %s, gen_random_uuid(), %s) AS id",
                           (s.usuario_id, t.cuenta_origen_id, destino_id, t.monto, motivo)).fetchone()["id"]

    return con_rechazo(s, operar, rechazo)


@router.post("/ajustes")
def crear_ajuste(a: Ajuste, s: Sesion = Depends(caja)):
    """El ajuste queda pendiente: no mueve saldos hasta que un supervisor (otro) lo apruebe."""
    cuenta_de_mi_oficina(s, a.cuenta_id)
    tx = valor(s, "SELECT fin.fn_crear_ajuste(%s, %s, %s, %s, %s, %s)",
               (s.usuario_id, a.cuenta_id, a.monto, a.sentido, a.clave_o_nueva(), a.descripcion))
    return {"transaccion_id": tx, "estado": "PENDING_APPROVAL"}
