-- =====================================================================
-- Banco Andino Colombia · Perfil de datos de G4
--
-- Mide los datos cargados (lotes 1 y 2) contra los criterios del gate G4 y
-- los controles de distribución obligatorios del laboratorio, y guarda el
-- resultado en evidence/g4_data_profile.csv (métrica · esperado · obtenido · PASS/FAIL).
--
-- Requisitos: modelo (sql/run_all.sql) + lote 1 + lote 2 cargados.
-- Ejecutar DESDE LA CARPETA lab-postgresql-banco-ia (la ruta del CSV es relativa):
--   SQL Shell:  \cd 'C:/…/lab-postgresql-banco-ia'   y luego   \i sql/load/perfil_datos_g4.sql
--   PowerShell: psql -U postgres -d banco_andino_lab -f sql/load/perfil_datos_g4.sql
-- Tarda alrededor de 1 minuto con el millón de transacciones.
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
SET client_encoding = 'UTF8';
SET statement_timeout = 0;

-- ---------------------------------------------------------------------
-- Tablas de apoyo (temporales)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE p (
  orden      int,
  categoria  text,
  metrica    text,
  esperado   text,
  obtenido   text,
  resultado  text
);

-- Movimientos que afectan cuentas de clientes, con su momento contable
CREATE TEMP TABLE m AS
SELECT a.transaccion_id, a.cuenta_id, a.naturaleza, a.valor, t.fecha_contabilizacion AS ts
FROM fin.asiento_contable a
JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
WHERE a.cuenta_id IS NOT NULL;

-- Estado de cada cuenta en el tiempo (a partir de sus eventos)
CREATE TEMP TABLE e AS
SELECT cuenta_id, estado_nuevo AS estado, ocurrido_en AS desde,
       lead(ocurrido_en) OVER (PARTITION BY cuenta_id ORDER BY ocurrido_en, evento_id) AS hasta
FROM core.evento_cuenta;
CREATE INDEX ON e (cuenta_id, desde);

-- Transacciones POSTED con hora y día en Colombia
CREATE TEMP TABLE tp AS
SELECT transaccion_id, tipo_codigo, monto, fecha_contable,
       extract(hour FROM fecha_contabilizacion AT TIME ZONE 'America/Bogota')::int AS hora,
       cuenta_origen_id, cuenta_destino_id
FROM fin.transaccion_financiera
WHERE estado_codigo = 'POSTED';
ANALYZE m, e, tp;

-- Utilidad: registra una métrica con su criterio
CREATE FUNCTION pg_temp.metrica(p_orden int, p_categoria text, p_metrica text, p_esperado text, p_obtenido text, p_ok boolean)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO p VALUES (p_orden, p_categoria, p_metrica, p_esperado, p_obtenido, CASE WHEN p_ok THEN 'PASS' ELSE 'FAIL' END)
$$;

-- ---------------------------------------------------------------------
-- 1. Conteos objetivo
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(101, 'Conteos', 'Clientes', '10000', count(*)::text, count(*) = 10000) FROM core.cliente \gset
SELECT pg_temp.metrica(102, 'Conteos', 'Personas naturales (≈85 %)', '8500', count(*)::text, count(*) = 8500) FROM core.persona_natural \gset
SELECT pg_temp.metrica(103, 'Conteos', 'Personas jurídicas (≈15 %)', '1500', count(*)::text, count(*) = 1500) FROM core.persona_juridica \gset
SELECT pg_temp.metrica(104, 'Conteos', 'Cuentas', '50000', count(*)::text, count(*) = 50000) FROM core.cuenta \gset
SELECT pg_temp.metrica(105, 'Conteos', 'Transacciones POSTED (supuesto S5)', '1000000', count(*)::text, count(*) = 1000000) FROM tp \gset
SELECT pg_temp.metrica(106, 'Conteos', 'Asientos contables (ledger)', '2000000', count(*)::text, count(*) = 2000000) FROM fin.asiento_contable \gset
SELECT pg_temp.metrica(107, 'Conteos', 'Usuarios internos (cantidad razonable)', 'entre 100 y 1000', count(*)::text, count(*) BETWEEN 100 AND 1000) FROM seg.usuario \gset
SELECT pg_temp.metrica(108, 'Conteos', 'Transacciones REJECTED y PENDING (adicionales, sin asientos)', '> 0',
  count(*)::text, count(*) > 0) FROM fin.transaccion_financiera WHERE estado_codigo <> 'POSTED' \gset

-- ---------------------------------------------------------------------
-- 2. Duplicados críticos
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(201, 'Duplicados', 'Documentos de cliente repetidos (incluye NIT)', '0', count(*)::text, count(*) = 0)
FROM (SELECT tipo_documento, numero_documento FROM core.cliente GROUP BY 1, 2 HAVING count(*) > 1) x \gset
SELECT pg_temp.metrica(202, 'Duplicados', 'Números de cuenta repetidos', '0', count(*)::text, count(*) = 0)
FROM (SELECT numero_cuenta FROM core.cuenta GROUP BY 1 HAVING count(*) > 1) x \gset
SELECT pg_temp.metrica(203, 'Duplicados', 'Claves de idempotencia repetidas', '0', count(*)::text, count(*) = 0)
FROM (SELECT idempotency_key FROM fin.transaccion_financiera GROUP BY 1 HAVING count(*) > 1) x \gset
SELECT pg_temp.metrica(204, 'Duplicados', 'Documentos de usuario interno repetidos', '0', count(*)::text, count(*) = 0)
FROM (SELECT tipo_documento, numero_documento FROM seg.usuario GROUP BY 1, 2 HAVING count(*) > 1) x \gset

-- ---------------------------------------------------------------------
-- 3. Huérfanos
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(301, 'Huérfanos', 'Clientes sin subtipo o con ambos', '0', count(*)::text, count(*) = 0)
FROM core.cliente c
WHERE (EXISTS (SELECT 1 FROM core.persona_natural n WHERE n.cliente_id = c.cliente_id))
    = (EXISTS (SELECT 1 FROM core.persona_juridica j WHERE j.cliente_id = c.cliente_id)) \gset
SELECT pg_temp.metrica(302, 'Huérfanos', 'Cuentas no cerradas sin titular principal vigente', '0', count(*)::text, count(*) = 0)
FROM core.cuenta c
WHERE c.estado_cuenta <> 'CERRADA'
  AND NOT EXISTS (SELECT 1 FROM core.titularidad_cuenta t
                  WHERE t.cuenta_id = c.cuenta_id AND t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL) \gset
SELECT pg_temp.metrica(303, 'Huérfanos', 'Cuentas sin evento de creación', '0', count(*)::text, count(*) = 0)
FROM core.cuenta c
WHERE NOT EXISTS (SELECT 1 FROM core.evento_cuenta ev WHERE ev.cuenta_id = c.cuenta_id AND ev.tipo_evento = 'CREACION') \gset
SELECT pg_temp.metrica(304, 'Huérfanos', 'Transacciones POSTED sin asientos', '0', count(*)::text, count(*) = 0)
FROM tp WHERE NOT EXISTS (SELECT 1 FROM fin.asiento_contable a WHERE a.transaccion_id = tp.transaccion_id) \gset
SELECT pg_temp.metrica(305, 'Huérfanos', 'Transacciones REJECTED o PENDING con asientos', '0', count(*)::text, count(*) = 0)
FROM fin.transaccion_financiera t
WHERE t.estado_codigo <> 'POSTED' AND EXISTS (SELECT 1 FROM fin.asiento_contable a WHERE a.transaccion_id = t.transaccion_id) \gset
SELECT pg_temp.metrica(306, 'Huérfanos', 'Municipios de clientes y oficinas fuera del catálogo', '0', count(*)::text, count(*) = 0)
FROM (SELECT municipio_codigo FROM core.cliente UNION ALL SELECT municipio_codigo FROM ref.oficina) x
WHERE NOT EXISTS (SELECT 1 FROM ref.municipio mu WHERE mu.municipio_codigo = x.municipio_codigo) \gset

-- ---------------------------------------------------------------------
-- 4. Violaciones temporales
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(401, 'Temporal', 'Movimientos antes de la apertura o después del cierre', '0', count(*)::text, count(*) = 0)
FROM m JOIN core.cuenta c ON c.cuenta_id = m.cuenta_id
WHERE m.ts < c.fecha_apertura OR (c.fecha_cierre IS NOT NULL AND m.ts > c.fecha_cierre) \gset
SELECT pg_temp.metrica(402, 'Temporal', 'Débitos desde una cuenta que no estaba ACTIVA (bloqueos respetados)', '0', count(*)::text, count(*) = 0)
FROM m
WHERE m.naturaleza = 'D'
  AND NOT EXISTS (SELECT 1 FROM e WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts
                    AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado = 'ACTIVA') \gset
SELECT pg_temp.metrica(403, 'Temporal', 'Créditos a una cuenta que no estaba ACTIVA ni BLOQUEADA', '0', count(*)::text, count(*) = 0)
FROM m
WHERE m.naturaleza = 'C'
  AND NOT EXISTS (SELECT 1 FROM e WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts
                    AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado IN ('ACTIVA', 'BLOQUEADA')) \gset
SELECT pg_temp.metrica(404, 'Temporal', 'Apertura de cuenta anterior a la vinculación del titular', '0', count(*)::text, count(*) = 0)
FROM core.titularidad_cuenta t JOIN core.cuenta c USING (cuenta_id) JOIN core.cliente cl USING (cliente_id)
WHERE (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < cl.fecha_vinculacion \gset
SELECT pg_temp.metrica(405, 'Temporal', 'Meses con actividad (mínimo 24)', '≥ 24', count(DISTINCT date_trunc('month', fecha_contable))::text,
  count(DISTINCT date_trunc('month', fecha_contable)) >= 24) FROM tp \gset
SELECT pg_temp.metrica(406, 'Temporal', 'Reversos con fecha anterior a la transacción original', '0', count(*)::text, count(*) = 0)
FROM fin.transaccion_financiera r JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
WHERE r.fecha_solicitud <= o.fecha_contabilizacion \gset

-- ---------------------------------------------------------------------
-- 5. Violaciones financieras
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(501, 'Financiera', 'Transacciones POSTED descuadradas (Σ D ≠ Σ C)', '0', count(*)::text, count(*) = 0)
FROM fin.v_balance_transaccion WHERE NOT cuadrada \gset
SELECT pg_temp.metrica(502, 'Financiera', 'Cuentas con saldo distinto del ledger (RN-48)', '0', count(*)::text, count(*) = 0)
FROM core.v_saldo_vs_ledger WHERE diferencia <> 0 \gset
SELECT pg_temp.metrica(503, 'Financiera', 'Momentos con saldo negativo sin sobregiro (o por debajo del cupo)', '0', count(*)::text, count(*) = 0)
FROM (SELECT m.cuenta_id,
             sum(CASE m.naturaleza WHEN 'C' THEN m.valor ELSE -m.valor END)
               OVER (PARTITION BY m.cuenta_id ORDER BY m.ts, m.transaccion_id) AS saldo
      FROM m) x
JOIN core.cuenta c ON c.cuenta_id = x.cuenta_id
WHERE x.saldo < -c.cupo_sobregiro \gset
SELECT pg_temp.metrica(504, 'Financiera', 'Transferencias con origen = destino o entre monedas distintas', '0', count(*)::text, count(*) = 0)
FROM tp JOIN core.cuenta o ON o.cuenta_id = tp.cuenta_origen_id JOIN core.cuenta d ON d.cuenta_id = tp.cuenta_destino_id
WHERE tp.tipo_codigo = 'TRANSFERENCIA' AND (o.cuenta_id = d.cuenta_id OR o.moneda_codigo <> d.moneda_codigo) \gset
SELECT pg_temp.metrica(505, 'Financiera', 'Cuentas CERRADAS con saldo distinto de 0', '0', count(*)::text, count(*) = 0)
FROM core.cuenta WHERE estado_cuenta = 'CERRADA' AND saldo_contable <> 0 \gset
WITH cambios AS (
  SELECT ev.cuenta_id, ev.ocurrido_en, cl.valor_anterior, cl.valor_nuevo,
         row_number() OVER w AS n, lead(ev.ocurrido_en) OVER w AS siguiente
  FROM core.evento_cuenta ev JOIN core.cambio_limite cl ON cl.evento_id = ev.evento_id
  WINDOW w AS (PARTITION BY ev.cuenta_id ORDER BY ev.ocurrido_en, ev.evento_id)
), limite AS (            -- límite vigente en cada tramo de tiempo
  SELECT cuenta_id, NULL::timestamptz AS desde, ocurrido_en AS hasta, valor_anterior AS valor FROM cambios WHERE n = 1
  UNION ALL SELECT cuenta_id, ocurrido_en, siguiente, valor_nuevo FROM cambios
  UNION ALL SELECT c.cuenta_id, NULL, NULL, c.limite_retiro_diario FROM core.cuenta c
            WHERE NOT EXISTS (SELECT 1 FROM cambios x WHERE x.cuenta_id = c.cuenta_id)
), r AS (
  SELECT cuenta_origen_id AS cuenta_id, sum(monto) AS total,
         (fecha_contable + 1)::timestamp AT TIME ZONE 'America/Bogota' AS fin_dia
  FROM tp WHERE tipo_codigo = 'RETIRO' GROUP BY cuenta_origen_id, fecha_contable)
SELECT pg_temp.metrica(506, 'Financiera', 'Cuenta-día con retiros por encima del límite diario vigente', '0', count(*)::text, count(*) = 0)
FROM r JOIN limite l ON l.cuenta_id = r.cuenta_id
                     AND (l.desde IS NULL OR l.desde < r.fin_dia) AND (l.hasta IS NULL OR l.hasta >= r.fin_dia)
WHERE r.total > l.valor \gset
SELECT pg_temp.metrica(507, 'Financiera', 'Montos con más de 2 decimales o ≤ 0', '0', count(*)::text, count(*) = 0)
FROM fin.transaccion_financiera WHERE monto <= 0 OR monto <> round(monto, 2) \gset

-- ---------------------------------------------------------------------
-- 6. Datos 100 % sintéticos (0 PII real)
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(601, 'Privacidad', 'Correos fuera del dominio reservado example.com', '0', count(*)::text, count(*) = 0)
FROM core.cliente WHERE email IS NOT NULL AND email NOT LIKE '%@example.com' \gset
SELECT pg_temp.metrica(602, 'Privacidad', 'Cédulas de clientes fuera del rango sintético 1.000.000.000–1.299.999.999', '0', count(*)::text, count(*) = 0)
FROM core.cliente WHERE tipo_documento = 'CC' AND numero_documento::bigint NOT BETWEEN 1000000000 AND 1299999999 \gset
SELECT pg_temp.metrica(603, 'Privacidad', 'NIT fuera del rango sintético 960.000.000–989.999.999', '0', count(*)::text, count(*) = 0)
FROM core.cliente WHERE tipo_documento = 'NIT' AND numero_documento::bigint NOT BETWEEN 960000000 AND 989999999 \gset

-- ---------------------------------------------------------------------
-- 7. Controles de distribución obligatorios (no deben verse uniformes)
-- ---------------------------------------------------------------------
-- Clientes por departamento: el más poblado muy por encima del promedio
WITH d AS (SELECT mu.departamento_codigo, count(*) AS n FROM core.cliente c JOIN ref.municipio mu USING (municipio_codigo) GROUP BY 1)
SELECT pg_temp.metrica(701, 'Distribución', 'Clientes por departamento: mayor / promedio', '> 3 (no uniforme)',
  round(max(n)::numeric / avg(n), 1)::text || ' (' || count(*) || ' departamentos, máx ' || max(n) || ', mín ' || min(n) || ')',
  max(n)::numeric / avg(n) > 3) FROM d \gset

-- Cuentas por cliente: cola larga
WITH k AS (SELECT cliente_id, count(*) AS n FROM core.titularidad_cuenta WHERE rol_titular = 'PRINCIPAL' GROUP BY 1)
SELECT pg_temp.metrica(702, 'Distribución', 'Cuentas por cliente: máximo / mediana', '≥ 10 (cola larga)',
  round(max(n) / percentile_cont(0.5) WITHIN GROUP (ORDER BY n)::numeric, 1)::text
    || ' (mediana ' || percentile_cont(0.5) WITHIN GROUP (ORDER BY n) || ', p95 ' || percentile_cont(0.95) WITHIN GROUP (ORDER BY n) || ', máx ' || max(n) || ')',
  max(n) / percentile_cont(0.5) WITHIN GROUP (ORDER BY n) >= 10) FROM k \gset

-- Transacciones por cuenta: algunas muy activas y otras casi inactivas
WITH k AS (
  SELECT c.cuenta_id, count(DISTINCT m.transaccion_id) AS n
  FROM core.cuenta c LEFT JOIN m ON m.cuenta_id = c.cuenta_id GROUP BY 1)
SELECT pg_temp.metrica(703, 'Distribución', 'Transacciones por cuenta: p99 / mediana', '≥ 5',
  round(percentile_cont(0.99) WITHIN GROUP (ORDER BY n)::numeric / nullif(percentile_cont(0.5) WITHIN GROUP (ORDER BY n), 0)::numeric, 1)::text
    || ' (mediana ' || percentile_cont(0.5) WITHIN GROUP (ORDER BY n) || ', p99 ' || percentile_disc(0.99) WITHIN GROUP (ORDER BY n)
    || ', máx ' || max(n) || ', cuentas con ≤ 2 movimientos: ' || count(*) FILTER (WHERE n <= 2) || ')',
  percentile_cont(0.99) WITHIN GROUP (ORDER BY n) / nullif(percentile_cont(0.5) WITHIN GROUP (ORDER BY n), 0) >= 5) FROM k \gset

-- Transacciones por hora: patrón horario
WITH h AS (SELECT hora, count(*) AS n FROM tp GROUP BY 1)
SELECT pg_temp.metrica(704, 'Distribución', 'Transacciones por hora: hora pico / hora más baja', '≥ 5 (patrón horario)',
  round(max(n)::numeric / min(n), 1)::text || ' (pico a las ' || (array_agg(hora ORDER BY n DESC))[1] || ' h, mínimo a las '
    || (array_agg(hora ORDER BY n))[1] || ' h)',
  max(n)::numeric / min(n) >= 5) FROM h \gset

-- Día de la semana: domingos más bajos
WITH w AS (SELECT extract(isodow FROM fecha_contable) AS dow, count(*)::numeric / count(DISTINCT fecha_contable) AS diario FROM tp GROUP BY 1)
SELECT pg_temp.metrica(705, 'Distribución', 'Promedio diario domingo / lunes a viernes', '< 0,7',
  round((SELECT diario FROM w WHERE dow = 7) / (SELECT avg(diario) FROM w WHERE dow <= 5), 2)::text,
  (SELECT diario FROM w WHERE dow = 7) / (SELECT avg(diario) FROM w WHERE dow <= 5) < 0.7) \gset

-- Quincenas y fin de mes
WITH q AS (
  SELECT (extract(day FROM fecha_contable) IN (1, 2, 15, 16)
          OR fecha_contable >= (date_trunc('month', fecha_contable) + INTERVAL '1 month - 2 days')::date) AS quincena,
         count(*)::numeric / count(DISTINCT fecha_contable) AS diario
  FROM tp GROUP BY 1)
SELECT pg_temp.metrica(706, 'Distribución', 'Promedio diario en quincena y fin de mes / resto de días', '> 1,2',
  round((SELECT diario FROM q WHERE quincena) / (SELECT diario FROM q WHERE NOT quincena), 2)::text,
  (SELECT diario FROM q WHERE quincena) / (SELECT diario FROM q WHERE NOT quincena) > 1.2) \gset

-- Estacionalidad mensual: diciembre por encima de sus meses vecinos
WITH mm AS (SELECT date_trunc('month', fecha_contable)::date AS mes, count(*) AS n FROM tp GROUP BY 1)
SELECT pg_temp.metrica(707, 'Distribución', 'Diciembre / promedio de noviembre y enero (cada año)', '> 1,2 en ambos diciembres',
  string_agg(to_char(d.mes, 'YYYY-MM') || ': ' || round(d.n::numeric / ((nov.n + ene.n) / 2.0), 2), ' · ' ORDER BY d.mes),
  bool_and(d.n::numeric / ((nov.n + ene.n) / 2.0) > 1.2))
FROM mm d
JOIN mm nov ON nov.mes = (d.mes - INTERVAL '1 month')::date
JOIN mm ene ON ene.mes = (d.mes + INTERVAL '1 month')::date
WHERE extract(month FROM d.mes) = 12 \gset

-- Montos sesgados: muchas pequeñas, pocas grandes (solo COP para no mezclar monedas)
WITH x AS (
  SELECT tp.monto FROM tp
  JOIN core.cuenta c ON c.cuenta_id = coalesce(tp.cuenta_origen_id, tp.cuenta_destino_id)
  WHERE c.moneda_codigo = 'COP')
SELECT pg_temp.metrica(708, 'Distribución', 'Montos COP: mediana < promedio y P99 ≥ 10 × mediana', 'verdadero',
  'mediana ' || percentile_disc(0.5) WITHIN GROUP (ORDER BY monto) || ' · promedio ' || round(avg(monto), 0)
    || ' · P95 ' || percentile_disc(0.95) WITHIN GROUP (ORDER BY monto) || ' · P99 ' || percentile_disc(0.99) WITHIN GROUP (ORDER BY monto)
    || ' · máx ' || max(monto),
  percentile_cont(0.5) WITHIN GROUP (ORDER BY monto) < avg(monto)
  AND percentile_cont(0.99) WITHIN GROUP (ORDER BY monto) >= 10 * percentile_cont(0.5) WITHIN GROUP (ORDER BY monto)) FROM x \gset

-- Estados: mayoría activas, minorías bloqueadas / inactivas / cerradas
SELECT pg_temp.metrica(709, 'Distribución', 'Estados de cuenta: ACTIVA > 50 % y las demás presentes', 'verdadero',
  string_agg(estado_cuenta || ' ' || round(100.0 * n / total, 1) || ' %', ' · ' ORDER BY n DESC),
  bool_or(estado_cuenta = 'ACTIVA' AND n > total / 2) AND count(*) >= 4)
FROM (SELECT estado_cuenta, count(*) AS n, sum(count(*)) OVER () AS total FROM core.cuenta GROUP BY 1) s \gset

-- Tipos de transacción: mezcla realista
SELECT pg_temp.metrica(710, 'Distribución', 'Tipos de transacción POSTED presentes (7 tipos)', '7',
  count(*)::text || ' (' || string_agg(tipo_codigo || ' ' || round(100.0 * n / total, 1) || ' %', ' · ' ORDER BY n DESC) || ')',
  count(*) = 7)
FROM (SELECT tipo_codigo, count(*) AS n, sum(count(*)) OVER () AS total FROM tp GROUP BY 1) s \gset

-- ---------------------------------------------------------------------
-- 8. Casos extremos válidos (deben existir, pocos)
-- ---------------------------------------------------------------------
SELECT pg_temp.metrica(801, 'Casos extremos', 'Cuentas usando sobregiro hoy (saldo negativo dentro del cupo)', '> 0 y < 5 % de las cuentas',
  count(*)::text, count(*) > 0 AND count(*) < 2500) FROM core.cuenta WHERE saldo_contable < 0 AND saldo_contable >= -cupo_sobregiro \gset
SELECT pg_temp.metrica(802, 'Casos extremos', 'Días en que una cuenta retiró su límite diario completo', '> 0',
  count(*)::text, count(*) > 0)
FROM (SELECT cuenta_origen_id, fecha_contable, sum(monto) AS total FROM tp WHERE tipo_codigo = 'RETIRO' GROUP BY 1, 2) r
JOIN core.cuenta c ON c.cuenta_id = r.cuenta_origen_id WHERE r.total = c.limite_retiro_diario \gset
SELECT pg_temp.metrica(803, 'Casos extremos', 'Cuentas cerradas que trasladaron su saldo antes del cierre', '> 0',
  count(DISTINCT c.cuenta_id)::text, count(DISTINCT c.cuenta_id) > 0)
FROM core.cuenta c JOIN m ON m.cuenta_id = c.cuenta_id WHERE c.estado_cuenta = 'CERRADA' \gset
SELECT pg_temp.metrica(804, 'Casos extremos', 'Reversos rechazados por cuenta bloqueada (RN-43)', '> 0',
  count(*)::text, count(*) > 0)
FROM fin.transaccion_financiera WHERE tipo_codigo = 'REVERSO' AND estado_codigo = 'REJECTED' \gset

-- ---------------------------------------------------------------------
-- Resultado
-- ---------------------------------------------------------------------
INSERT INTO p
SELECT 999, 'Veredicto', 'QUALITY GATE G4', '0 FAIL',
       count(*) FILTER (WHERE resultado = 'FAIL') || ' FAIL de ' || count(*) || ' métricas',
       CASE WHEN count(*) FILTER (WHERE resultado = 'FAIL') = 0 THEN 'PASS' ELSE 'FAIL' END
FROM p;

\pset footer off
SELECT categoria, metrica, esperado, obtenido, resultado FROM p ORDER BY orden;

\copy (SELECT categoria, metrica, esperado, obtenido, resultado FROM p ORDER BY orden) TO 'evidence/g4_data_profile.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo 'Perfil guardado en evidence/g4_data_profile.csv'
