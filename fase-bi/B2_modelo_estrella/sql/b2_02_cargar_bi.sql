-- =====================================================================
-- B2 · Carga del modelo estrella
-- 1) Traemos el resultado del quality gate de G6 (evidence/g6_quality_results.csv).
-- 2) Llenamos dimensiones y hechos con bi.cargar_bi().
-- Lo corremos desde la raíz del repositorio (la ruta del CSV es relativa).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\timing on

TRUNCATE bi.calidad_prueba;
\copy bi.calidad_prueba FROM 'evidence/g6_quality_results.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CALL bi.cargar_bi();
ANALYZE bi.dim_fecha, bi.dim_oficina, bi.dim_producto, bi.dim_tipo_transaccion, bi.dim_cliente,
        bi.dim_cuenta, bi.fact_transaccion, bi.fact_saldo_cuenta, bi.fact_control, bi.calidad_prueba;

\echo '== Última carga'
SELECT carga_id, fecha_corte, filas_fact_transaccion, filas_fact_saldo,
       round(extract(epoch FROM fin - inicio)::numeric, 1) AS segundos
FROM bi.carga ORDER BY carga_id DESC LIMIT 1;
