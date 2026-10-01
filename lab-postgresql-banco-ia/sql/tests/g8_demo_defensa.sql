-- =====================================================================
-- g8_demo_defensa.sql · Banco Andino Colombia · G8
-- Demostración en vivo para la defensa (5 minutos). No deja cambios:
-- todo lo que escribe se deshace con ROLLBACK.
-- Los ERROR que aparecen son ESPERADOS: son la base de datos protegiéndose.
--
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/tests/g8_demo_defensa.sql
--   SQL Shell: \c banco_andino_lab   \i sql/tests/g8_demo_defensa.sql
-- Guion y respuestas: docs/defensa.md
-- =====================================================================
\set ON_ERROR_STOP off
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
SET client_min_messages = warning;
\set VERBOSITY terse
\pset footer off

\echo ''
\echo '== DEMO 1 · Inmutabilidad: una transacción POSTED no se modifica ni se borra (RN-40, RN-53)'
\echo '   (se intenta como postgres, el dueño de la base: aun así lo impide un trigger)'
UPDATE fin.transaccion_financiera SET monto = 1 WHERE transaccion_id = 1;
DELETE FROM fin.asiento_contable WHERE transaccion_id = 1;

\echo ''
\echo '== DEMO 2 · Doble partida: Σ débitos = Σ créditos en el millón de transacciones (RN-47)'
SELECT count(*) AS transacciones_posted,
       count(*) FILTER (WHERE debitos <> creditos) AS descuadradas
FROM (SELECT t.transaccion_id,
             sum(a.valor) FILTER (WHERE a.naturaleza = 'D') AS debitos,
             sum(a.valor) FILTER (WHERE a.naturaleza = 'C') AS creditos
      FROM fin.transaccion_financiera t JOIN fin.asiento_contable a ON a.transaccion_id = t.transaccion_id
      WHERE t.estado_codigo = 'POSTED'
      GROUP BY t.transaccion_id) x;

\echo ''
\echo '== DEMO 3 · Reconciliación: saldo guardado = saldo según el ledger en las 50.000 cuentas (RN-48)'
SELECT count(*) AS cuentas, count(*) FILTER (WHERE diferencia <> 0) AS con_diferencia,
       sum(abs(diferencia)) AS diferencia_total
FROM core.v_saldo_vs_ledger;

\echo ''
\echo '== DEMO 4 · Idempotencia: la misma solicitud enviada dos veces genera UNA sola transacción (RN-38)'
BEGIN;
SELECT fin.fn_consignar(10, 30, 50000, 'a1b2c3d4-0000-4000-8000-000000000001') AS primer_envio;
SELECT fin.fn_consignar(10, 30, 50000, 'a1b2c3d4-0000-4000-8000-000000000001') AS segundo_envio;
SELECT count(*) AS transacciones_creadas FROM fin.transaccion_financiera
WHERE idempotency_key = 'a1b2c3d4-0000-4000-8000-000000000001';
ROLLBACK;

\echo ''
\echo '== DEMO 5 · Atomicidad: una transferencia que falla no deja nada a medias (RN-39)'
SELECT count(*) AS transacciones_antes FROM fin.transaccion_financiera \gset
SELECT saldo_contable AS saldo_origen_antes FROM core.cuenta WHERE cuenta_id = 30 \gset
SELECT fin.fn_transferir(10, 30, 25, 999999999999, gen_random_uuid());
SELECT (SELECT count(*) FROM fin.transaccion_financiera) - :transacciones_antes AS transacciones_nuevas,
       (SELECT saldo_contable FROM core.cuenta WHERE cuenta_id = 30) - :saldo_origen_antes AS cambio_saldo_origen;

\echo ''
\echo '== DEMO 6 · Reglas en la base: retiro que excede el límite diario (RN-37, error BA004)'
BEGIN;
SELECT fin.fn_retirar(10, 30, 2000000.01, gen_random_uuid());
ROLLBACK;

\echo ''
\echo '== DEMO 7 · Índice útil: el límite diario de cada retiro usa ix_transaccion_origen_fecha (G7)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT coalesce(sum(monto), 0) FROM fin.transaccion_financiera
WHERE cuenta_origen_id = 30 AND tipo_codigo = 'RETIRO' AND estado_codigo = 'POSTED' AND fecha_contable = DATE '2026-07-17';

\echo ''
\echo '== DEMO 8 · Mínimo privilegio: un usuario de consulta no puede tocar el dinero (G7)'
DROP ROLE IF EXISTS demo_defensa;
CREATE ROLE demo_defensa NOLOGIN IN ROLE banco_consulta;
BEGIN;
SET LOCAL ROLE demo_defensa;
SELECT count(*) AS cuentas_que_puede_leer FROM core.cuenta;
UPDATE core.cuenta SET saldo_contable = 0 WHERE cuenta_id = 30;
ROLLBACK;
DROP ROLE demo_defensa;

\echo ''
\echo '== Fin de la demostración: la base no cambió.'
