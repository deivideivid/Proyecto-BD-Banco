-- =====================================================================
-- G0 · Evidencia del entorno (Banco Andino Colombia)
-- Crea el archivo evidence/g0_environment.txt con la versión de PostgreSQL,
-- la conexión y una consulta de prueba.
--
-- Ejecutar en SQL Shell (psql), estando en la carpeta lab-postgresql-banco-ia:
--   \cd 'C:/ruta/a/lab-postgresql-banco-ia'
--   \i sql/00_g0_environment.sql
-- =====================================================================

\o evidence/g0_environment.txt
\qecho '== G0 · Evidencia del entorno · Banco Andino Colombia =='
\qecho 'Cliente psql:' :VERSION
\qecho

SELECT version() AS servidor_postgresql;
SELECT current_database() AS base_de_datos, current_user AS usuario, current_timestamp AS fecha_hora;
SHOW server_version;
SHOW timezone;
SHOW data_checksums;
SHOW server_encoding;
SELECT 1 + 1 AS prueba_sql;
\o

\echo 'Listo: se creo evidence/g0_environment.txt'
