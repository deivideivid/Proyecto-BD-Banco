-- =====================================================================
-- 12_indexes.sql · Banco Andino Colombia
-- Índices secundarios (G7).
--
-- Regla del laboratorio: un índice solo existe si hay una consulta del
-- workload que lo justifique, medida con EXPLAIN (ANALYZE, BUFFERS) antes
-- y después. Cada índice indica qué consulta lo justifica; el análisis
-- completo (mejora, costo de escritura y almacenamiento, riesgo de
-- sobreindexación y los casos en que se decidió NO crear índice) está en
-- evidence/g7_explain.md. El workload está en sql/perf/g7_workload.sql.
--
-- Índices que ya existían porque los crean las restricciones:
--   - Todas las claves primarias y restricciones UNIQUE (documento del
--     cliente, número de cuenta, idempotency_key, transaccion_reversada_id…).
--   - core.uq_titularidad_principal_vigente  (RN-13, parcial)
--   - core.uq_titularidad_cliente_vigente    (G2, hallazgo H-06, parcial)
--
-- Se ejecuta desde sql/run_all.sql (sin transacción propia). También se
-- puede ejecutar solo sobre una base ya cargada: IF NOT EXISTS lo hace
-- repetible.
-- =====================================================================

-- IX-1 · W01 (límite diario dentro de fin.fn_retirar, RN-37) y W04 (historial de la cuenta)
--        Antes: Seq Scan de 1.024.178 transacciones en cada retiro, con la cuenta bloqueada.
CREATE INDEX IF NOT EXISTS ix_transaccion_origen_fecha
  ON fin.transaccion_financiera (cuenta_origen_id, fecha_contable);
COMMENT ON INDEX fin.ix_transaccion_origen_fecha IS 'G7 · W01 límite diario de retiro (RN-37) y W04 historial por cuenta origen.';

-- IX-2 · W04 (historial de la cuenta: la condición es origen = X OR destino = X)
--        Sin este índice el OR obliga a recorrer la tabla aunque exista IX-1.
CREATE INDEX IF NOT EXISTS ix_transaccion_destino_fecha
  ON fin.transaccion_financiera (cuenta_destino_id, fecha_contable);
COMMENT ON INDEX fin.ix_transaccion_destino_fecha IS 'G7 · W04 historial por cuenta destino (BitmapOr con IX-1).';

-- IX-3 · W02 (extracto), W03 (saldo según el ledger, RN-48) y W09 reescrita (cuentas sin movimiento)
--        Parcial: el 36 % de las líneas son de cuentas contables internas (cuenta_id NULL) y
--        ninguna consulta por cuenta las necesita; el índice queda más pequeño.
CREATE INDEX IF NOT EXISTS ix_asiento_cuenta_fecha
  ON fin.asiento_contable (cuenta_id, registrado_en)
  WHERE cuenta_id IS NOT NULL;
COMMENT ON INDEX fin.ix_asiento_cuenta_fecha IS 'G7 · W02 extracto, W03 saldo según ledger (RN-48), W09 cuentas sin movimiento. Parcial: excluye líneas sin cuenta de cliente.';

-- IX-4 · W05 (cuentas vigentes de un cliente; también fn_cerrar_cuenta)
CREATE INDEX IF NOT EXISTS ix_titularidad_cliente
  ON core.titularidad_cuenta (cliente_id);
COMMENT ON INDEX core.ix_titularidad_cliente IS 'G7 · W05 cuentas de un cliente y fn_cerrar_cuenta (cliente sin cuentas vigentes).';

-- IX-5 · W06 (trigger trg_evento_validar: último evento de la cuenta en cada evento nuevo)
CREATE INDEX IF NOT EXISTS ix_evento_cuenta_fecha
  ON core.evento_cuenta (cuenta_id, ocurrido_en);
COMMENT ON INDEX core.ix_evento_cuenta_fecha IS 'G7 · W06 último evento de la cuenta (trg_evento_validar, RN-23 a RN-25).';

-- IX-6 · W07 (cola de ajustes pendientes del supervisor, RN-44)
--        Parcial: solo las transacciones PENDING_APPROVAL (74 de 1.024.178).
CREATE INDEX IF NOT EXISTS ix_transaccion_pendientes
  ON fin.transaccion_financiera (fecha_solicitud)
  WHERE estado_codigo = 'PENDING_APPROVAL';
COMMENT ON INDEX fin.ix_transaccion_pendientes IS 'G7 · W07 cola de ajustes pendientes de aprobación (RN-44). Parcial.';

-- Decisiones de NO crear índice (ver evidence/g7_explain.md):
--   W08 búsqueda por documento → ya la cubre uq_cliente_documento.
--   W10 movimientos atípicos   → lee todos los asientos; un índice no ayuda.
--   Fechas de transacción, tipo o estado sueltos → baja selectividad, ninguna consulta lo justifica.
--   FK hacia catálogos (ref.*, producto, rol…) → los catálogos no se borran; no hay consulta que lo pida.
