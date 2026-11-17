-- =====================================================================
-- 13_views.sql · Banco Andino Colombia
-- Vistas de control (reconciliación). Las usa el quality gate de G6.
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- Cuadre de cada transacción contabilizada (RN-46, RN-47)
CREATE VIEW fin.v_balance_transaccion AS
SELECT t.transaccion_id,
       t.tipo_codigo,
       coalesce(sum(a.valor) FILTER (WHERE a.naturaleza = 'D'), 0) AS total_debitos,
       coalesce(sum(a.valor) FILTER (WHERE a.naturaleza = 'C'), 0) AS total_creditos,
       count(a.linea) AS lineas,
       coalesce(sum(a.valor) FILTER (WHERE a.naturaleza = 'D'), 0)
         = coalesce(sum(a.valor) FILTER (WHERE a.naturaleza = 'C'), 0)
       AND count(a.linea) FILTER (WHERE a.naturaleza = 'D') > 0
       AND count(a.linea) FILTER (WHERE a.naturaleza = 'C') > 0 AS cuadrada
FROM fin.transaccion_financiera t
LEFT JOIN fin.asiento_contable a ON a.transaccion_id = t.transaccion_id
WHERE t.estado_codigo = 'POSTED'
GROUP BY t.transaccion_id, t.tipo_codigo;
COMMENT ON VIEW fin.v_balance_transaccion IS 'Débitos y créditos por transacción POSTED; cuadrada = true si Σ D = Σ C y hay al menos una línea de cada naturaleza (RN-46, RN-47).';

-- Saldo almacenado frente al saldo según el ledger (RN-48, desnormalización D-01)
CREATE VIEW core.v_saldo_vs_ledger AS
SELECT c.cuenta_id,
       c.numero_cuenta,
       c.moneda_codigo,
       c.saldo_contable,
       coalesce(l.saldo_ledger, 0) AS saldo_ledger,
       c.saldo_contable - coalesce(l.saldo_ledger, 0) AS diferencia
FROM core.cuenta c
LEFT JOIN (
  SELECT cuenta_id, sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS saldo_ledger
  FROM fin.asiento_contable
  WHERE cuenta_id IS NOT NULL
  GROUP BY cuenta_id
) l ON l.cuenta_id = c.cuenta_id;
COMMENT ON VIEW core.v_saldo_vs_ledger IS 'Reconciliación: diferencia debe ser 0 en todas las cuentas (RN-48).';

-- Estado almacenado frente al estado del último evento (RN-25, desnormalización D-03)
CREATE VIEW core.v_estado_vs_eventos AS
SELECT c.cuenta_id,
       c.estado_cuenta,
       e.estado_nuevo AS estado_ultimo_evento,
       c.estado_cuenta IS NOT DISTINCT FROM e.estado_nuevo AS coincide
FROM core.cuenta c
LEFT JOIN (
  SELECT DISTINCT ON (cuenta_id) cuenta_id, estado_nuevo
  FROM core.evento_cuenta
  ORDER BY cuenta_id, ocurrido_en DESC, evento_id DESC
) e ON e.cuenta_id = c.cuenta_id;
COMMENT ON VIEW core.v_estado_vs_eventos IS 'Reconciliación: coincide debe ser true en todas las cuentas (RN-25).';
