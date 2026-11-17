-- =====================================================================
-- B2 · Validación del modelo estrella contra las tablas del banco
-- Cada control compara lo que hay en bi con lo que hay en ref/core/fin.
-- Al final repetimos la carga y revisamos que dé exactamente lo mismo.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\pset footer off

CREATE TEMP TABLE val (id text PRIMARY KEY, control text, esperado text, obtenido text, ok boolean);

INSERT INTO val
SELECT 'V01', 'Filas de fact_transaccion = transacciones del banco',
       (SELECT count(*) FROM fin.transaccion_financiera)::text, (SELECT count(*) FROM bi.fact_transaccion)::text, NULL::boolean
UNION ALL
SELECT 'V02', 'Transacciones contabilizadas (POSTED)', '1000000',
       (SELECT count(*) FROM bi.fact_transaccion WHERE estado = 'POSTED')::text, NULL::boolean
UNION ALL
SELECT 'V03', 'Monto POSTED en COP igual al del banco',
       (SELECT sum(t.monto) FROM fin.transaccion_financiera t JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_origen_id, t.cuenta_destino_id) WHERE t.estado_codigo = 'POSTED' AND c.moneda_codigo = 'COP')::text,
       (SELECT sum(monto) FROM bi.fact_transaccion WHERE estado = 'POSTED' AND moneda = 'COP')::text, NULL::boolean
UNION ALL
SELECT 'V04', 'Monto POSTED en USD igual al del banco',
       (SELECT sum(t.monto) FROM fin.transaccion_financiera t JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_origen_id, t.cuenta_destino_id) WHERE t.estado_codigo = 'POSTED' AND c.moneda_codigo = 'USD')::text,
       (SELECT sum(monto) FROM bi.fact_transaccion WHERE estado = 'POSTED' AND moneda = 'USD')::text, NULL::boolean
UNION ALL
SELECT 'V05', 'Monto POSTED por tipo igual al del banco (tipos distintos)', '0',
       (SELECT count(*) FROM (
          SELECT tipo_codigo, sum(monto) s FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED' GROUP BY 1
          EXCEPT
          SELECT tipo_key, sum(monto) FROM bi.fact_transaccion WHERE estado = 'POSTED' GROUP BY 1) x)::text, NULL::boolean
UNION ALL
SELECT 'V06', 'Rechazadas y pendientes', (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo <> 'POSTED')::text,
       (SELECT count(*) FROM bi.fact_transaccion WHERE estado <> 'POSTED')::text, NULL::boolean
UNION ALL
SELECT 'V07', 'Cuentas en dim_cuenta y en fact_saldo_cuenta', '50000 / 50000',
       (SELECT count(*) FROM bi.dim_cuenta)::text || ' / ' || (SELECT count(*) FROM bi.fact_saldo_cuenta)::text, NULL::boolean
UNION ALL
SELECT 'V08', 'Saldo contable total COP igual al del banco',
       (SELECT sum(saldo_contable) FROM core.cuenta WHERE moneda_codigo = 'COP')::text,
       (SELECT sum(saldo_contable) FROM bi.fact_saldo_cuenta WHERE moneda = 'COP')::text, NULL::boolean
UNION ALL
SELECT 'V09', 'Saldo contable total USD igual al del banco',
       (SELECT sum(saldo_contable) FROM core.cuenta WHERE moneda_codigo = 'USD')::text,
       (SELECT sum(saldo_contable) FROM bi.fact_saldo_cuenta WHERE moneda = 'USD')::text, NULL::boolean
UNION ALL
SELECT 'V10', 'Clientes y oficinas', (SELECT count(*) FROM core.cliente)::text || ' / ' || (SELECT count(*) FROM ref.oficina)::text,
       (SELECT count(*) FROM bi.dim_cliente)::text || ' / ' || (SELECT count(*) FROM bi.dim_oficina)::text, NULL::boolean
UNION ALL
SELECT 'V11', 'Cuentas sin titular principal en dim_cuenta', '0',
       (SELECT count(*) FROM core.cuenta c WHERE NOT EXISTS (SELECT 1 FROM bi.dim_cuenta d WHERE d.cuenta_key = c.cuenta_id))::text, NULL::boolean
UNION ALL
SELECT 'V12', 'Días del calendario sin hueco (de la primera a la última fecha)',
       ((SELECT max(fecha) - min(fecha) + 1 FROM bi.dim_fecha))::text, (SELECT count(*) FROM bi.dim_fecha)::text, NULL::boolean
UNION ALL
SELECT 'V13', 'Controles de cuadre y calidad en PASS', '6',
       (SELECT count(*) FROM bi.fact_control WHERE resultado = 'PASS')::text, NULL;

-- Repetimos la carga y comparamos una huella de los hechos
SELECT md5(string_agg(transaccion_id || ':' || cuenta_key || ':' || monto, ',' ORDER BY transaccion_id)) AS h1
FROM bi.fact_transaccion \gset
CALL bi.cargar_bi();
SELECT md5(string_agg(transaccion_id || ':' || cuenta_key || ':' || monto, ',' ORDER BY transaccion_id)) AS h2
FROM bi.fact_transaccion \gset
INSERT INTO val VALUES ('V14', 'Repetir la carga da exactamente lo mismo (huella md5)', :'h1', :'h2', NULL);

UPDATE val SET ok = (esperado = obtenido);

\echo '== Validación del modelo estrella'
SELECT id, control, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado FROM val ORDER BY id;

\echo '== Veredicto'
SELECT count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok) AS fail,
       CASE WHEN bool_and(ok) THEN 'B2 MODELO ESTRELLA = PASS' ELSE 'B2 MODELO ESTRELLA = FAIL' END AS veredicto
FROM val;
