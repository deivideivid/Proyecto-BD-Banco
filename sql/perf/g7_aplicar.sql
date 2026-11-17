-- =====================================================================
-- g7_aplicar.sql · Banco Andino Colombia · G7
-- Aplica a una base YA CARGADA los cambios de rendimiento de G7:
--   1. Los 6 índices justificados (sql/12_indexes.sql)
--   2. El procedimiento de inactivación reescrito (sql/15_procedures.sql)
-- En una base nueva no hace falta: run_all.sql ya los incluye.
-- Es repetible (IF NOT EXISTS / DROP IF EXISTS).
--
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/perf/g7_aplicar.sql
--   SQL Shell: \i sql/perf/g7_aplicar.sql
-- Nota: en producción se usaría CREATE INDEX CONCURRENTLY para no bloquear
-- escrituras; aquí basta la forma normal (≈ 3 s con el millón de transacciones).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
\set QUIET on
SET client_min_messages = warning;
\timing on

BEGIN;
\ir ../12_indexes.sql
DROP PROCEDURE IF EXISTS core.pr_inactivar_cuentas_sin_movimiento(bigint, integer, integer);
\ir ../15_procedures.sql
REVOKE EXECUTE ON PROCEDURE core.pr_inactivar_cuentas_sin_movimiento(bigint, integer, integer) FROM PUBLIC;
GRANT  EXECUTE ON PROCEDURE core.pr_inactivar_cuentas_sin_movimiento(bigint, integer, integer) TO banco_supervisor;
COMMIT;

VACUUM (ANALYZE) fin.transaccion_financiera, fin.asiento_contable, core.titularidad_cuenta, core.evento_cuenta;
\timing off

\echo '== Índices de G7'
SELECT i.indexrelid::regclass AS indice, i.indrelid::regclass AS tabla,
       pg_size_pretty(pg_relation_size(i.indexrelid)) AS tamano,
       obj_description(i.indexrelid, 'pg_class') AS justificacion
FROM pg_index i
WHERE i.indexrelid::regclass::text LIKE '%.ix\_%'
ORDER BY pg_relation_size(i.indexrelid) DESC;
