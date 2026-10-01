-- =====================================================================
-- run_all.sql · Banco Andino Colombia
-- Reconstruye TODO el modelo desde cero y ejecuta las pruebas de G3.
--
-- ¡Borra la base del laboratorio (incluidos los datos cargados)! Después
-- se vuelven a cargar los lotes con sql/load/carga_lote1.sql y
-- sql/load/carga_lote2_transacciones.sql.
--
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/run_all.sql
--
-- Criterio de G3: debe correr dos veces seguidas sin errores.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
\set QUIET on
SET client_min_messages = warning;
\echo '== Banco Andino · run_all: 1) borrar el modelo anterior'
\ir 20_teardown.sql

\echo '== 2) crear el modelo (00 a 17) en una sola transacción'
BEGIN;
\ir 00_extensions.sql
\ir 01_schemas.sql
\ir 02_catalogs.sql
\ir 03_geography.sql
\ir 04_customers.sql
\ir 05_products.sql
\ir 06_accounts.sql
\ir 07_users_security.sql
\ir 08_transactions.sql
\ir 09_ledger.sql
\ir 10_audit.sql
\ir 11_constraints.sql
\ir 12_indexes.sql
\ir 13_views.sql
\ir 14_functions.sql
\ir 15_procedures.sql
\ir 16_triggers.sql
\ir 17_roles_permissions.sql
COMMIT;

\echo '== 3) pruebas de G3 (se deshacen al final: no dejan datos)'
\ir 18_tests.sql

\echo '== run_all terminado'
