-- =====================================================================
-- 15_procedures.sql · Banco Andino Colombia
-- Procedimientos de mantenimiento (tareas por lotes).
-- Se ejecuta desde sql/run_all.sql (no abre ni cierra transacción).
-- =====================================================================

-- Inactiva las cuentas ACTIVAS sin movimientos contabilizados en los últimos
-- p_dias días (por defecto 180) y abiertas hace más de p_dias días.
-- Cada inactivación queda como evento INACTIVACION (RN-24) y en auditoría.
-- Uso:  CALL core.pr_inactivar_cuentas_sin_movimiento(<usuario_id supervisor>, 180, NULL);
CREATE PROCEDURE core.pr_inactivar_cuentas_sin_movimiento(
  p_usuario_id bigint, p_dias integer DEFAULT 180, INOUT p_inactivadas integer DEFAULT NULL)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  v_cuenta bigint;
  v_corte timestamptz := clock_timestamp() - make_interval(days => p_dias);
BEGIN
  PERFORM seg.fn_exigir_permiso(p_usuario_id, 'CTA_INACTIVAR');
  IF p_dias IS NULL OR p_dias < 30 THEN
    RAISE EXCEPTION 'El periodo sin movimiento debe ser de al menos 30 días' USING ERRCODE = 'BA017';
  END IF;
  p_inactivadas := 0;
  FOR v_cuenta IN
    SELECT c.cuenta_id
    FROM core.cuenta c
    WHERE c.estado_cuenta = 'ACTIVA'
      AND c.fecha_apertura < v_corte
      -- G7 (W09): se filtra por asiento_contable.registrado_en, que fn_contabilizar
      -- llena con el mismo instante que fecha_contabilizacion. Así se evita el join y
      -- se usa el índice ix_asiento_cuenta_fecha (453 ms → 72 ms en la consulta).
      AND NOT EXISTS (
        SELECT 1
        FROM fin.asiento_contable a
        WHERE a.cuenta_id = c.cuenta_id
          AND a.registrado_en >= v_corte)
    ORDER BY c.cuenta_id
  LOOP
    PERFORM core.fn_registrar_evento(p_usuario_id, v_cuenta, 'INACTIVACION', 'INACTIVA',
                                     format('Sin movimientos en %s días', p_dias));
    p_inactivadas := p_inactivadas + 1;
  END LOOP;
END $$;
COMMENT ON PROCEDURE core.pr_inactivar_cuentas_sin_movimiento(bigint, integer, integer) IS 'Inactiva cuentas ACTIVAS sin movimientos en p_dias días, registrando el evento INACTIVACION. Permiso CTA_INACTIVAR (SUPERVISOR).';
