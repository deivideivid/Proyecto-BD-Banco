-- =====================================================================
-- g7_workload.sql · Banco Andino Colombia · G7 (rendimiento)
-- Workload de 10 consultas representativas (W01–W10) + 2 variantes, medido
-- con EXPLAIN (ANALYZE, BUFFERS). Se ejecuta DOS veces:
--   1. ANTES:   sin los índices de G7          → evidence/g7_explain_antes.csv
--   2. DESPUÉS: con sql/perf/g7_aplicar.sql    → evidence/g7_explain_despues.csv
-- El script detecta solo en qué fase está (si existen o no los índices).
-- Las operaciones de dinero (OP1–OP3) se ejecutan y se DESHACEN (ROLLBACK).
--
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/perf/g7_workload.sql
--   SQL Shell: \c banco_andino_lab   \i sql/perf/g7_workload.sql
-- Tarda 1-2 min antes de los índices y menos de 1 min después.
-- Análisis completo: evidence/g7_explain.md
-- =====================================================================

\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';   -- SQL Shell de Windows no usa UTF-8 por defecto: sin esto las tildes se dañan
\set QUIET on
SET client_min_messages = warning;
SET timezone = 'America/Bogota';
\pset footer off

SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_transaccion_origen_fecha') AS con_indices,
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'ix_transaccion_origen_fecha')
            THEN 'DESPUÉS (con índices de G7)' ELSE 'ANTES (sin índices de G7)' END AS fase \gset
\echo '== Fase:' :fase

DROP TABLE IF EXISTS pg_temp.g7;
CREATE TEMP TABLE g7 (id text PRIMARY KEY, consulta text, tipo text, mediana_ms numeric, costo numeric,
                      buffers bigint, filas bigint, acceso text);

-- Ejecuta EXPLAIN (ANALYZE, BUFFERS) p_veces y guarda la mediana del tiempo de ejecución,
-- el costo estimado, los buffers leídos y cómo se accede a las tablas (Seq Scan / Index Scan…).
CREATE OR REPLACE FUNCTION pg_temp.medir(p_id text, p_consulta text, p_tipo text, p_sql text, p_pre text DEFAULT NULL, p_veces int DEFAULT 5)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE j jsonb; t numeric[] := '{}'; i int;
BEGIN
  IF p_pre IS NOT NULL THEN EXECUTE p_pre; END IF;
  FOR i IN 1..p_veces LOOP
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' || p_sql INTO j;
    t := t || (j -> 0 ->> 'Execution Time')::numeric;
  END LOOP;
  IF p_pre IS NOT NULL THEN RESET enable_indexscan; END IF;   -- solo la variante W10S cambia esta opción
  INSERT INTO g7
  SELECT p_id, p_consulta, p_tipo,
         round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x) FROM unnest(t) x)::numeric, 3),
         (j -> 0 -> 'Plan' ->> 'Total Cost')::numeric,
         coalesce(round((j -> 0 -> 'Plan' ->> 'Shared Hit Blocks')::numeric), 0)::bigint + coalesce(round((j -> 0 -> 'Plan' ->> 'Shared Read Blocks')::numeric), 0)::bigint,
         round((j -> 0 -> 'Plan' ->> 'Actual Rows')::numeric)::bigint,   -- PG18 informa filas con decimales (1.00)
         (SELECT string_agg(DISTINCT (n ->> 'Node Type') || coalesce(' ' || (n ->> 'Index Name'), '') || coalesce(' en ' || (n ->> 'Relation Name'), ''), ' + ')
          FROM jsonb_path_query(j, 'strict $.**') n
          WHERE jsonb_typeof(n) = 'object' AND n ? 'Relation Name');
END $$;

-- W01 · Límite diario de retiro (dentro de fin.fn_retirar, RN-37)
--      OLTP crítica · cada retiro, con la cuenta bloqueada (FOR UPDATE)
\echo '== W01 · Límite diario de retiro (dentro de fin.fn_retirar, RN-37)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT coalesce(sum(monto), 0) AS retirado_hoy
FROM fin.transaccion_financiera
WHERE cuenta_origen_id = 30 AND tipo_codigo = 'RETIRO'
  AND estado_codigo = 'POSTED' AND fecha_contable = DATE '2026-07-17';
SELECT pg_temp.medir('W01', $t$Límite diario de retiro (dentro de fin.fn_retirar, RN-37)$t$, $k$OLTP crítica · cada retiro, con la cuenta bloqueada (FOR UPDATE)$k$, $q$
SELECT coalesce(sum(monto), 0) AS retirado_hoy
FROM fin.transaccion_financiera
WHERE cuenta_origen_id = 30 AND tipo_codigo = 'RETIRO'
  AND estado_codigo = 'POSTED' AND fecha_contable = DATE '2026-07-17'
$q$) \gset

-- W02 · Extracto mensual de una cuenta (julio 2026)
--      OLTP · caja, portal y extractos
\echo '== W02 · Extracto mensual de una cuenta (julio 2026)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.registrado_en, t.tipo_codigo, a.naturaleza, a.valor, t.descripcion
FROM fin.asiento_contable a
JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
WHERE a.cuenta_id = 30
  AND a.registrado_en >= TIMESTAMPTZ '2026-07-01 00:00-05' AND a.registrado_en < TIMESTAMPTZ '2026-08-01 00:00-05'
ORDER BY a.registrado_en;
SELECT pg_temp.medir('W02', $t$Extracto mensual de una cuenta (julio 2026)$t$, $k$OLTP · caja, portal y extractos$k$, $q$
SELECT a.registrado_en, t.tipo_codigo, a.naturaleza, a.valor, t.descripcion
FROM fin.asiento_contable a
JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
WHERE a.cuenta_id = 30
  AND a.registrado_en >= TIMESTAMPTZ '2026-07-01 00:00-05' AND a.registrado_en < TIMESTAMPTZ '2026-08-01 00:00-05'
ORDER BY a.registrado_en
$q$) \gset

-- W03 · Saldo según el ledger de una cuenta (RN-48)
--      OLTP · conciliación puntual de una cuenta
\echo '== W03 · Saldo según el ledger de una cuenta (RN-48)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS saldo_ledger
FROM fin.asiento_contable
WHERE cuenta_id = 30;
SELECT pg_temp.medir('W03', $t$Saldo según el ledger de una cuenta (RN-48)$t$, $k$OLTP · conciliación puntual de una cuenta$k$, $q$
SELECT sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS saldo_ledger
FROM fin.asiento_contable
WHERE cuenta_id = 30
$q$) \gset

-- W04 · Últimas 20 transacciones de una cuenta (como origen o destino)
--      OLTP · pantalla de la cuenta
\echo '== W04 · Últimas 20 transacciones de una cuenta (como origen o destino)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT transaccion_id, tipo_codigo, estado_codigo, monto, fecha_contabilizacion
FROM fin.transaccion_financiera
WHERE cuenta_origen_id = 30 OR cuenta_destino_id = 30
ORDER BY fecha_contabilizacion DESC NULLS LAST
LIMIT 20;
SELECT pg_temp.medir('W04', $t$Últimas 20 transacciones de una cuenta (como origen o destino)$t$, $k$OLTP · pantalla de la cuenta$k$, $q$
SELECT transaccion_id, tipo_codigo, estado_codigo, monto, fecha_contabilizacion
FROM fin.transaccion_financiera
WHERE cuenta_origen_id = 30 OR cuenta_destino_id = 30
ORDER BY fecha_contabilizacion DESC NULLS LAST
LIMIT 20
$q$) \gset

-- W05 · Cuentas vigentes de un cliente
--      OLTP · caja y fn_cerrar_cuenta (cliente sin cuentas vigentes)
\echo '== W05 · Cuentas vigentes de un cliente'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.numero_cuenta, c.producto_codigo, c.estado_cuenta, c.saldo_contable, t.rol_titular
FROM core.titularidad_cuenta t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
WHERE t.cliente_id = 7 AND t.vigente_hasta IS NULL;
SELECT pg_temp.medir('W05', $t$Cuentas vigentes de un cliente$t$, $k$OLTP · caja y fn_cerrar_cuenta (cliente sin cuentas vigentes)$k$, $q$
SELECT c.numero_cuenta, c.producto_codigo, c.estado_cuenta, c.saldo_contable, t.rol_titular
FROM core.titularidad_cuenta t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
WHERE t.cliente_id = 7 AND t.vigente_hasta IS NULL
$q$) \gset

-- W06 · Último evento de una cuenta (trigger trg_evento_validar)
--      OLTP · cada evento: bloqueo, desbloqueo, cierre…
\echo '== W06 · Último evento de una cuenta (trigger trg_evento_validar)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT max(ocurrido_en) AS ultimo_evento, count(*) > 0 AS hay_eventos
FROM core.evento_cuenta
WHERE cuenta_id = 30;
SELECT pg_temp.medir('W06', $t$Último evento de una cuenta (trigger trg_evento_validar)$t$, $k$OLTP · cada evento: bloqueo, desbloqueo, cierre…$k$, $q$
SELECT max(ocurrido_en) AS ultimo_evento, count(*) > 0 AS hay_eventos
FROM core.evento_cuenta
WHERE cuenta_id = 30
$q$) \gset

-- W07 · Cola de ajustes pendientes de aprobación
--      OLTP · pantalla del supervisor (RN-44)
\echo '== W07 · Cola de ajustes pendientes de aprobación'
EXPLAIN (ANALYZE, BUFFERS)
SELECT transaccion_id, cuenta_destino_id, cuenta_origen_id, monto, creado_por, fecha_solicitud
FROM fin.transaccion_financiera
WHERE estado_codigo = 'PENDING_APPROVAL'
ORDER BY fecha_solicitud;
SELECT pg_temp.medir('W07', $t$Cola de ajustes pendientes de aprobación$t$, $k$OLTP · pantalla del supervisor (RN-44)$k$, $q$
SELECT transaccion_id, cuenta_destino_id, cuenta_origen_id, monto, creado_por, fecha_solicitud
FROM fin.transaccion_financiera
WHERE estado_codigo = 'PENDING_APPROVAL'
ORDER BY fecha_solicitud
$q$) \gset

-- W08 · Buscar un cliente por documento
--      OLTP · el primer paso de toda atención en caja
\echo '== W08 · Buscar un cliente por documento'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.cliente_id, c.tipo_cliente, c.estado_cliente, pn.nombres, pn.apellidos
FROM core.cliente c
LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
WHERE c.tipo_documento = 'CC' AND c.numero_documento = '1082099316';
SELECT pg_temp.medir('W08', $t$Buscar un cliente por documento$t$, $k$OLTP · el primer paso de toda atención en caja$k$, $q$
SELECT c.cliente_id, c.tipo_cliente, c.estado_cliente, pn.nombres, pn.apellidos
FROM core.cliente c
LEFT JOIN core.persona_natural pn ON pn.cliente_id = c.cliente_id
WHERE c.tipo_documento = 'CC' AND c.numero_documento = '1082099316'
$q$) \gset

-- W09 · Cuentas ACTIVAS sin movimiento en 90 días (G5 I02 / pr_inactivar)
--      Lote · proceso nocturno de inactivación
\echo '== W09 · Cuentas ACTIVAS sin movimiento en 90 días (G5 I02 / pr_inactivar)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.producto_codigo, count(*) AS cuentas_dormidas
FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA'
  AND NOT EXISTS (
    SELECT 1
    FROM fin.asiento_contable a
    JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
    WHERE a.cuenta_id = c.cuenta_id AND t.fecha_contable > DATE '2026-08-31' - 90)
GROUP BY c.producto_codigo
ORDER BY cuentas_dormidas DESC;
SELECT pg_temp.medir('W09', $t$Cuentas ACTIVAS sin movimiento en 90 días (G5 I02 / pr_inactivar)$t$, $k$Lote · proceso nocturno de inactivación$k$, $q$
SELECT c.producto_codigo, count(*) AS cuentas_dormidas
FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA'
  AND NOT EXISTS (
    SELECT 1
    FROM fin.asiento_contable a
    JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
    WHERE a.cuenta_id = c.cuenta_id AND t.fecha_contable > DATE '2026-08-31' - 90)
GROUP BY c.producto_codigo
ORDER BY cuentas_dormidas DESC
$q$) \gset

-- W10 · Movimientos atípicos por cuenta (G5 A06)
--      Analítica · reporte de riesgo
\echo '== W10 · Movimientos atípicos por cuenta (G5 A06)'
EXPLAIN (ANALYZE, BUFFERS)
WITH movs AS (
  SELECT a.cuenta_id, a.transaccion_id, a.valor,
         avg(a.valor)    OVER (PARTITION BY a.cuenta_id) AS media,
         stddev(a.valor) OVER (PARTITION BY a.cuenta_id) AS desviacion,
         count(*)        OVER (PARTITION BY a.cuenta_id) AS n
  FROM fin.asiento_contable a
  WHERE a.cuenta_id IS NOT NULL
)
SELECT cuenta_id, transaccion_id, valor, round(media, 0) AS media_cuenta,
       round((valor - media) / nullif(desviacion, 0), 1) AS desviaciones
FROM movs
WHERE n >= 20 AND valor > media + 4 * desviacion
ORDER BY desviaciones DESC
LIMIT 10;
SELECT pg_temp.medir('W10', $t$Movimientos atípicos por cuenta (G5 A06)$t$, $k$Analítica · reporte de riesgo$k$, $q$
WITH movs AS (
  SELECT a.cuenta_id, a.transaccion_id, a.valor,
         avg(a.valor)    OVER (PARTITION BY a.cuenta_id) AS media,
         stddev(a.valor) OVER (PARTITION BY a.cuenta_id) AS desviacion,
         count(*)        OVER (PARTITION BY a.cuenta_id) AS n
  FROM fin.asiento_contable a
  WHERE a.cuenta_id IS NOT NULL
)
SELECT cuenta_id, transaccion_id, valor, round(media, 0) AS media_cuenta,
       round((valor - media) / nullif(desviacion, 0), 1) AS desviaciones
FROM movs
WHERE n >= 20 AND valor > media + 4 * desviacion
ORDER BY desviaciones DESC
LIMIT 10
$q$) \gset

-- W09R · W09 reescrita: usa asiento_contable.registrado_en (= fecha de contabilización) y evita el join
--      Lote · variante
\echo '== W09R · W09 reescrita: usa asiento_contable.registrado_en (= fecha de contabilización) y evita el join'
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.producto_codigo, count(*) AS cuentas_dormidas
FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA'
  AND NOT EXISTS (
    SELECT 1
    FROM fin.asiento_contable a
    WHERE a.cuenta_id = c.cuenta_id
      AND a.registrado_en >= TIMESTAMPTZ '2026-06-03 00:00-05')
GROUP BY c.producto_codigo
ORDER BY cuentas_dormidas DESC;
SELECT pg_temp.medir('W09R', $t$W09 reescrita: usa asiento_contable.registrado_en (= fecha de contabilización) y evita el join$t$, $k$Lote · variante$k$, $q$
SELECT c.producto_codigo, count(*) AS cuentas_dormidas
FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA'
  AND NOT EXISTS (
    SELECT 1
    FROM fin.asiento_contable a
    WHERE a.cuenta_id = c.cuenta_id
      AND a.registrado_en >= TIMESTAMPTZ '2026-06-03 00:00-05')
GROUP BY c.producto_codigo
ORDER BY cuentas_dormidas DESC
$q$) \gset

-- W10S · W10 con enable_indexscan = off solo en la sesión del reporte
--      Analítica · variante
\echo '== W10S · W10 con enable_indexscan = off solo en la sesión del reporte'
BEGIN;
SET enable_indexscan = off;
EXPLAIN (ANALYZE, BUFFERS)
WITH movs AS (
  SELECT a.cuenta_id, a.transaccion_id, a.valor,
         avg(a.valor)    OVER (PARTITION BY a.cuenta_id) AS media,
         stddev(a.valor) OVER (PARTITION BY a.cuenta_id) AS desviacion,
         count(*)        OVER (PARTITION BY a.cuenta_id) AS n
  FROM fin.asiento_contable a
  WHERE a.cuenta_id IS NOT NULL
)
SELECT cuenta_id, transaccion_id, valor, round(media, 0) AS media_cuenta,
       round((valor - media) / nullif(desviacion, 0), 1) AS desviaciones
FROM movs
WHERE n >= 20 AND valor > media + 4 * desviacion
ORDER BY desviaciones DESC
LIMIT 10;
ROLLBACK;
SELECT pg_temp.medir('W10S', $t$W10 con enable_indexscan = off solo en la sesión del reporte$t$, $k$Analítica · variante$k$, $q$
WITH movs AS (
  SELECT a.cuenta_id, a.transaccion_id, a.valor,
         avg(a.valor)    OVER (PARTITION BY a.cuenta_id) AS media,
         stddev(a.valor) OVER (PARTITION BY a.cuenta_id) AS desviacion,
         count(*)        OVER (PARTITION BY a.cuenta_id) AS n
  FROM fin.asiento_contable a
  WHERE a.cuenta_id IS NOT NULL
)
SELECT cuenta_id, transaccion_id, valor, round(media, 0) AS media_cuenta,
       round((valor - media) / nullif(desviacion, 0), 1) AS desviaciones
FROM movs
WHERE n >= 20 AND valor > media + 4 * desviacion
ORDER BY desviaciones DESC
LIMIT 10
$q$, $p$SET enable_indexscan = off;$p$) \gset

-- =====================================================================
-- Operaciones reales (se ejecutan y se deshacen con ROLLBACK)
--   OP1 · 200 retiros (fin.fn_retirar)       → incluye la consulta W01
--   OP2 · 200 consignaciones (fin.fn_consignar) → mide el costo de escritura de los índices
--   OP3 · core.pr_inactivar_cuentas_sin_movimiento(180 días) → W09 + un evento por cuenta (W06)
-- =====================================================================
\echo '== OP1–OP3 · operaciones reales (con ROLLBACK)'
SELECT min(u.usuario_id) FILTER (WHERE r.codigo = 'CAJERO') AS cajero,
       min(u.usuario_id) FILTER (WHERE r.codigo = 'SUPERVISOR') AS supervisor
FROM seg.usuario u
JOIN seg.usuario_rol ur ON ur.usuario_id = u.usuario_id AND ur.vigente_hasta IS NULL
JOIN seg.rol r ON r.rol_id = ur.rol_id
WHERE u.estado = 'ACTIVO' \gset
DROP TABLE IF EXISTS pg_temp.g7_ops;
CREATE TEMP TABLE g7_ops (id text, consulta text, tipo text, mediana_ms numeric, filas bigint);
CREATE OR REPLACE FUNCTION pg_temp.medir_ops(p_cajero bigint, OUT op1_ms numeric, OUT op2_ms numeric)
LANGUAGE plpgsql AS $$
DECLARE r record; t0 timestamptz; n int; tot interval; op text;
BEGIN
  FOREACH op IN ARRAY ARRAY['OP1', 'OP2'] LOOP
    n := 0; tot := '0';
    FOR r IN SELECT cuenta_id FROM core.cuenta
             WHERE estado_cuenta = 'ACTIVA' AND moneda_codigo = 'COP' AND saldo_contable - saldo_retenido >= 100000
               AND limite_retiro_diario >= 100000
             ORDER BY cuenta_id LIMIT 200 LOOP
      t0 := clock_timestamp();
      IF op = 'OP1' THEN
        PERFORM fin.fn_retirar(p_cajero, r.cuenta_id, 10000, gen_random_uuid(), 'G7 medición');
      ELSE
        PERFORM fin.fn_consignar(p_cajero, r.cuenta_id, 10000, gen_random_uuid(), 'G7 medición');
      END IF;
      n := n + 1; tot := tot + (clock_timestamp() - t0);
    END LOOP;
    IF op = 'OP1' THEN op1_ms := round(extract(epoch FROM tot) * 1000 / n, 3);
    ELSE op2_ms := round(extract(epoch FROM tot) * 1000 / n, 3); END IF;
  END LOOP;
END $$;

BEGIN;
SELECT * FROM pg_temp.medir_ops(:cajero) \gset
ROLLBACK;
BEGIN;
SELECT clock_timestamp() AS t0 \gset
CALL core.pr_inactivar_cuentas_sin_movimiento(:supervisor, 180, NULL) \gset
SELECT round(extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000, 3) AS ms_op3 \gset
ROLLBACK;
INSERT INTO g7_ops VALUES
  ('OP1', 'Retiro en caja (fin.fn_retirar), promedio por operación', 'Operación · 200 ejecuciones', :op1_ms, 200),
  ('OP2', 'Consignación en caja (fin.fn_consignar), promedio por operación', 'Operación · 200 ejecuciones', :op2_ms, 200),
  ('OP3', 'Inactivación de cuentas sin movimiento en 180 días (procedimiento completo)', 'Lote · 1 ejecución', :ms_op3, :p_inactivadas);

-- =====================================================================
-- Resumen y evidencia
-- =====================================================================
\echo '== Resumen de la fase:' :fase
SELECT id, consulta, mediana_ms, costo, buffers, acceso FROM g7
UNION ALL
SELECT id, consulta, mediana_ms, NULL, NULL, NULL FROM g7_ops
ORDER BY id;

\if :con_indices
\copy (SELECT id, consulta, tipo, mediana_ms, costo, buffers, filas, acceso FROM g7 UNION ALL SELECT id, consulta, tipo, mediana_ms, NULL, NULL, filas, NULL FROM g7_ops ORDER BY 1) TO 'evidence/g7_explain_despues.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo 'Guardado en evidence/g7_explain_despues.csv'
\else
\copy (SELECT id, consulta, tipo, mediana_ms, costo, buffers, filas, acceso FROM g7 UNION ALL SELECT id, consulta, tipo, mediana_ms, NULL, NULL, filas, NULL FROM g7_ops ORDER BY 1) TO 'evidence/g7_explain_antes.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo 'Guardado en evidence/g7_explain_antes.csv'
\endif
