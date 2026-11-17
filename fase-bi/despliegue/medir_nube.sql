-- =====================================================================
-- medir_nube.sql · Banco Andino Colombia · Fase BI (despliegue)
-- ¿Cuánto ocupa la base en la nube y cuánto espacio nos queda?
--
-- Se corre en una conexión NUEVA, después de la reconstrucción, para que
-- no cuente las tablas temporales de la carga:
--   psql -d "<cadena>" -f fase-bi/despliegue/medir_nube.sql
-- Por defecto compara contra 1 GB (Neon Free, Render Free, Aiven Free).
-- Para otro límite: psql -d "<cadena>" -v limite_mb=500 -f …
--
-- Solo lee: no cambia nada en la base.
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\set QUIET on
\pset footer off
\if :{?limite_mb}
\else
\set limite_mb 1024
\endif

\echo '== 1) Tamaño total frente al límite del plan'
SELECT pg_size_pretty(pg_database_size(current_database()))                                   AS tamano_base,
       :limite_mb || ' MB'                                                                     AS limite_plan,
       round(100.0 * pg_database_size(current_database()) / (:limite_mb * 1024.0 * 1024), 1)  AS porcentaje_usado,
       pg_size_pretty(:limite_mb::bigint * 1024 * 1024 - pg_database_size(current_database())) AS margen;

\echo '== 2) Por esquema (incluye el esquema bi cuando exista)'
SELECT n.nspname                                            AS esquema,
       count(*)                                             AS tablas,
       pg_size_pretty(sum(pg_total_relation_size(c.oid)))   AS tamano
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm')
  AND n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud', 'bi')
GROUP BY n.nspname
ORDER BY sum(pg_total_relation_size(c.oid)) DESC;

\echo '== 3) Las 8 tablas más grandes'
SELECT n.nspname || '.' || c.relname                AS tabla,
       pg_size_pretty(pg_relation_size(c.oid))       AS datos,
       pg_size_pretty(pg_indexes_size(c.oid))        AS indices,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'm')
  AND n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud', 'bi')
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 8;

\echo '== 4) Los conteos son los mismos que en local'
SELECT x.control, x.esperado, x.obtenido, CASE WHEN x.obtenido = x.esperado THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM (VALUES
  ('Clientes',             10000::bigint,   (SELECT count(*) FROM core.cliente)),
  ('Cuentas',              50000::bigint,   (SELECT count(*) FROM core.cuenta)),
  ('Transacciones POSTED', 1000000::bigint, (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED')),
  ('Asientos contables',   2000000::bigint, (SELECT count(*) FROM fin.asiento_contable))
) AS x(control, esperado, obtenido);

\echo '== 5) Veredicto'
SELECT CASE
         WHEN pg_database_size(current_database()) < 0.75 * :limite_mb * 1024 * 1024 THEN 'CABE CON MARGEN'
         WHEN pg_database_size(current_database()) < 0.95 * :limite_mb * 1024 * 1024 THEN 'CABE JUSTO: el esquema bi tiene que ser liviano'
         ELSE 'NO CABE: pasamos al plan B'
       END AS veredicto;
