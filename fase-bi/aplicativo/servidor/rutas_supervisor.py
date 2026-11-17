"""Supervisor: lo que el cajero no puede hacer (RN-28, RN-51).

Aprobar o rechazar ajustes, reversar transacciones, desbloquear, cambiar el límite diario,
cerrar cuentas e inactivar las que no tienen movimiento.
"""
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from .comun import ConClave, Monto, cuenta_de_mi_oficina, filas, valor
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/supervisor", tags=["Supervisor"])
supervisor = requiere("SUPERVISOR")


class Motivo(BaseModel):
    motivo: str = Field(min_length=3, max_length=200)


class Reverso(ConClave):
    motivo: str = Field(min_length=3, max_length=140)


class Limite(BaseModel):
    nuevo_limite: Decimal = Monto


class Inactivar(BaseModel):
    dias: int = Field(ge=180, le=3650)
    confirmar: bool


def _transaccion_de_mi_oficina(s: Sesion, transaccion_id: int) -> dict:
    t = filas(s, """
      SELECT t.transaccion_id, t.tipo_codigo, t.estado_codigo, t.monto, t.descripcion, t.creado_por,
             t.fecha_solicitud, t.fecha_contabilizacion,
             co.numero_cuenta AS cuenta_origen, cd.numero_cuenta AS cuenta_destino,
             coalesce(co.oficina_id, cd.oficina_id) AS oficina_id,
             EXISTS (SELECT 1 FROM fin.transaccion_financiera r WHERE r.transaccion_reversada_id = t.transaccion_id) AS ya_reversada
      FROM fin.transaccion_financiera t
      LEFT JOIN core.cuenta co ON co.cuenta_id = t.cuenta_origen_id
      LEFT JOIN core.cuenta cd ON cd.cuenta_id = t.cuenta_destino_id
      WHERE t.transaccion_id = %s""", (transaccion_id,))
    if not t:
        raise HTTPException(status_code=404, detail={"mensaje": "No encontramos la transacción.", "codigo": "BA016"})
    if t[0]["oficina_id"] != s.oficina_id:
        raise HTTPException(status_code=403, detail={"mensaje": "Esa transacción es de otra oficina.", "codigo": "OFICINA"})
    return t[0]


@router.get("/ajustes")
def ajustes_pendientes(s: Sesion = Depends(supervisor)):
    return filas(s, """
      SELECT t.transaccion_id, t.monto, CASE WHEN t.cuenta_destino_id IS NOT NULL THEN 'C' ELSE 'D' END AS sentido,
             t.descripcion, t.fecha_solicitud, t.creado_por, c.numero_cuenta, t.creado_por = %(yo)s AS es_mio
      FROM fin.transaccion_financiera t
      JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_destino_id, t.cuenta_origen_id)
      WHERE t.tipo_codigo = 'AJUSTE' AND t.estado_codigo = 'PENDING_APPROVAL' AND c.oficina_id = %(of)s
      ORDER BY t.fecha_solicitud""", {"yo": s.usuario_id, "of": s.oficina_id})


@router.post("/ajustes/{transaccion_id}/aprobar")
def aprobar(transaccion_id: int, s: Sesion = Depends(supervisor)):
    _transaccion_de_mi_oficina(s, transaccion_id)
    return {"transaccion_id": valor(s, "SELECT fin.fn_aprobar_ajuste(%s, %s)", (s.usuario_id, transaccion_id)), "estado": "POSTED"}


@router.post("/ajustes/{transaccion_id}/rechazar")
def rechazar(transaccion_id: int, m: Motivo, s: Sesion = Depends(supervisor)):
    _transaccion_de_mi_oficina(s, transaccion_id)
    return {"transaccion_id": valor(s, "SELECT fin.fn_rechazar_ajuste(%s, %s, %s)", (s.usuario_id, transaccion_id, m.motivo)),
            "estado": "REJECTED"}


@router.get("/transacciones/{transaccion_id}")
def ver_transaccion(transaccion_id: int, s: Sesion = Depends(supervisor)):
    return _transaccion_de_mi_oficina(s, transaccion_id)


@router.post("/transacciones/{transaccion_id}/reversar")
def reversar(transaccion_id: int, r: Reverso, s: Sesion = Depends(supervisor)):
    _transaccion_de_mi_oficina(s, transaccion_id)
    return {"reverso_id": valor(s, "SELECT fin.fn_reversar(%s, %s, %s, %s)",
                                (s.usuario_id, transaccion_id, r.clave_o_nueva(), r.motivo))}


@router.post("/cuentas/{cuenta_id}/desbloquear")
def desbloquear(cuenta_id: int, s: Sesion = Depends(supervisor)):
    cuenta_de_mi_oficina(s, cuenta_id)
    return {"evento_id": valor(s, "SELECT core.fn_desbloquear_cuenta(%s, %s)", (s.usuario_id, cuenta_id))}


@router.post("/cuentas/{cuenta_id}/limite")
def cambiar_limite(cuenta_id: int, l: Limite, s: Sesion = Depends(supervisor)):
    cuenta_de_mi_oficina(s, cuenta_id)
    return {"cambio_id": valor(s, "SELECT core.fn_cambiar_limite(%s, %s, %s)", (s.usuario_id, cuenta_id, l.nuevo_limite))}


@router.post("/cuentas/{cuenta_id}/cerrar")
def cerrar(cuenta_id: int, s: Sesion = Depends(supervisor)):
    cuenta_de_mi_oficina(s, cuenta_id)
    return {"evento_id": valor(s, "SELECT core.fn_cerrar_cuenta(%s, %s)", (s.usuario_id, cuenta_id))}


@router.get("/inactivar")
def vista_previa_inactivar(dias: int = Query(180, ge=180, le=3650), s: Sesion = Depends(supervisor)):
    """Cuántas cuentas quedarían inactivas, antes de hacerlo (el proceso es de todo el banco)."""
    n = filas(s, """
      SELECT count(*) AS cuentas FROM core.cuenta c
      WHERE c.estado_cuenta = 'ACTIVA' AND c.fecha_apertura < clock_timestamp() - make_interval(days => %(d)s)
        AND NOT EXISTS (SELECT 1 FROM fin.asiento_contable a WHERE a.cuenta_id = c.cuenta_id
                        AND a.registrado_en >= clock_timestamp() - make_interval(days => %(d)s))""", {"d": dias})
    return {"dias": dias, "cuentas_que_se_inactivarian": n[0]["cuentas"]}


@router.post("/inactivar")
def inactivar(i: Inactivar, s: Sesion = Depends(supervisor)):
    if not i.confirmar:
        raise HTTPException(status_code=422, detail={"mensaje": "Confirme primero la vista previa.", "codigo": "CONFIRMAR"})
    n = valor(s, "CALL core.pr_inactivar_cuentas_sin_movimiento(%s, %s, NULL)", (s.usuario_id, i.dias))
    return {"cuentas_inactivadas": n}
