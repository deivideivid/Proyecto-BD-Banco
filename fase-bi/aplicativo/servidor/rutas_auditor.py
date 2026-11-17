"""Auditor de datos: solo consulta. Cuadres, bitácora de auditoría, ingresos y calidad."""
from datetime import date

from fastapi import APIRouter, Depends, Query

from .comun import filas
from .sesion import Sesion, requiere

router = APIRouter(prefix="/api/auditor", tags=["Auditor de datos"])
auditor = requiere("AUDITOR")


@router.get("/cuadres")
def cuadres(s: Sesion = Depends(auditor)):
    """Las tres vistas de reconciliación del banco: lo esperado es 0 en las tres."""
    return filas(s, """
      SELECT 'Transacciones contabilizadas que no cuadran (débitos ≠ créditos)' AS control,
             (SELECT count(*) FROM fin.v_balance_transaccion WHERE NOT cuadrada) AS diferencias
      UNION ALL
      SELECT 'Cuentas con saldo distinto del ledger', (SELECT count(*) FROM core.v_saldo_vs_ledger WHERE diferencia <> 0)
      UNION ALL
      SELECT 'Cuentas con estado distinto de su último evento', (SELECT count(*) FROM core.v_estado_vs_eventos WHERE NOT coincide)""")


@router.get("/bitacora")
def bitacora(tabla: str | None = Query(None, max_length=63), operacion: str | None = Query(None, pattern="^(INSERT|UPDATE|DELETE)$"),
             login: str | None = Query(None, max_length=40), desde: date | None = None, hasta: date | None = None,
             limite: int = Query(50, ge=1, le=500), s: Sesion = Depends(auditor)):
    return filas(s, """
      SELECT a.auditoria_id, a.ocurrido_en, u.login, a.usuario_bd, a.esquema || '.' || a.tabla AS tabla, a.operacion, a.registro,
             -- B8 (sugerencia de Miguel): en los UPDATE, qué campos cambiaron y cómo [antes, después]
             CASE WHEN a.operacion = 'UPDATE' THEN (
               SELECT jsonb_object_agg(k, jsonb_build_array(a.valores_antes -> k, a.valores_despues -> k))
               FROM jsonb_object_keys(a.valores_despues) AS k
               WHERE a.valores_antes -> k IS DISTINCT FROM a.valores_despues -> k) END AS cambios,
             -- y a quién se refiere el registro, con nombre y no solo con el número
             (SELECT x.login FROM seg.usuario x WHERE x.usuario_id = (a.registro ->> 'usuario_id')::bigint) AS usuario_afectado,
             (SELECT r.codigo FROM seg.rol r WHERE r.rol_id = (a.registro ->> 'rol_id')::int) AS rol_afectado,
             (SELECT c.numero_cuenta FROM core.cuenta c WHERE c.cuenta_id = (a.registro ->> 'cuenta_id')::bigint) AS cuenta_afectada
      FROM aud.log_auditoria a LEFT JOIN seg.usuario u ON u.usuario_id = a.usuario_id
      WHERE (%(tabla)s::text IS NULL OR a.tabla = %(tabla)s)
        AND (%(op)s::text IS NULL OR a.operacion = %(op)s)
        AND (%(login)s::text IS NULL OR u.login = %(login)s)
        AND (%(desde)s::date IS NULL OR a.ocurrido_en >= %(desde)s::date)
        AND (%(hasta)s::date IS NULL OR a.ocurrido_en < %(hasta)s::date + 1)
      ORDER BY a.auditoria_id DESC LIMIT %(lim)s""",
                 {"tabla": tabla, "op": operacion, "login": login, "desde": desde, "hasta": hasta, "lim": limite})


@router.get("/ingresos")
def ingresos(limite: int = Query(50, ge=1, le=500), s: Sesion = Depends(auditor)):
    """Quién ha entrado (o intentado entrar) al aplicativo."""
    return filas(s, """SELECT i.momento, i.login, a.perfil, i.exitoso, i.origen
                       FROM app.ingreso i LEFT JOIN app.acceso a ON a.acceso_id = i.acceso_id
                       ORDER BY i.ingreso_id DESC LIMIT %s""", (limite,))


@router.get("/calidad")
def calidad(s: Sesion = Depends(auditor)):
    """Resultado del quality gate de G6 (desde el modelo estrella, con el rol de solo lectura)."""
    puntaje = filas(s, "SELECT dimension, pruebas, pass, warning, fail, puntaje FROM bi.v_calidad_puntaje ORDER BY dimension = 'OVERALL' DESC, dimension",
                    rol="banco_bi")
    pruebas = filas(s, """SELECT test_id, categoria, dimension, regla, severidad, resultado, obtenido
                          FROM bi.calidad_prueba ORDER BY (resultado = 'PASS'), test_id""", rol="banco_bi")
    return {"puntaje": puntaje, "pruebas": pruebas}
