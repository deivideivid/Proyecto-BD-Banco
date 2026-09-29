-- =====================================================================
-- Banco Andino Colombia · Carga del LOTE 2 (transacciones sintéticas)
--   1.000.000 transacciones POSTED + rechazadas y pendientes adicionales
--   2.000.000 asientos contables (doble partida)
--
-- Requisitos:
--   1. Tablas creadas con sql/tablas_banco_andino.sql
--   2. Lote 1 cargado con sql/load/carga_lote1.sql
--   3. CSV generados con: python src/generate_transactions.py
--
-- Ejecutar DESDE LA RAÍZ DEL REPOSITORIO (las rutas de \copy son relativas):
--   psql -h localhost -U postgres -d banco_andino_lab -f sql/load/carga_lote2_transacciones.sql
--
-- La carga va en una sola transacción: si algo falla, no queda nada a medias.
-- Tiempo aproximado: 3-6 min en local; en la nube depende de la velocidad de subida.
-- =====================================================================

\set ON_ERROR_STOP on
\timing on
SET client_encoding = 'UTF8';
SET statement_timeout = 0;

BEGIN;

-- 0. Protección: este lote solo se carga una vez y sobre el lote 1
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM fin.transaccion_financiera) THEN
    RAISE EXCEPTION 'fin.transaccion_financiera ya tiene datos: el lote 2 ya fue cargado';
  END IF;
  IF (SELECT count(*) FROM core.cuenta) <> 50000 THEN
    RAISE EXCEPTION 'Primero carga el lote 1 (se esperaban 50.000 cuentas)';
  END IF;
END $$;

-- 1. Transacciones (hash_solicitud queda NULL)
\copy fin.transaccion_financiera (transaccion_id, tipo_codigo, estado_codigo, cuenta_origen_id, cuenta_destino_id, monto, idempotency_key, transaccion_reversada_id, descripcion, fecha_solicitud, fecha_contabilizacion, fecha_contable, creado_por, aprobado_por, motivo_rechazo) FROM 'data/lote2/transaccion_financiera.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 2. Asientos contables
\copy fin.asiento_contable (transaccion_id, linea, cuenta_contable_codigo, cuenta_id, naturaleza, valor, registrado_en) FROM 'data/lote2/asiento_contable.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

-- 3. Saldo de cada cuenta = Σ créditos − Σ débitos de sus asientos (RN-48)
UPDATE core.cuenta c
SET saldo_contable = s.saldo
FROM (
  SELECT cuenta_id, sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS saldo
  FROM fin.asiento_contable
  WHERE cuenta_id IS NOT NULL
  GROUP BY cuenta_id
) s
WHERE s.cuenta_id = c.cuenta_id
  AND c.saldo_contable <> s.saldo;

-- 4. Sincronizar la secuencia de identidad
SELECT setval(pg_get_serial_sequence('fin.transaccion_financiera', 'transaccion_id'),
              (SELECT max(transaccion_id) FROM fin.transaccion_financiera));

COMMIT;

-- 5. Limpieza y estadísticas (fuera de la transacción)
VACUUM (ANALYZE) core.cuenta;
ANALYZE fin.transaccion_financiera, fin.asiento_contable;

-- =====================================================================
-- 6. VALIDACIÓN DEL LOTE — resultado esperado: todas las filas en PASS
-- =====================================================================

-- Estado de cada cuenta en el tiempo (a partir de sus eventos)
CREATE TEMP TABLE tmp_estado AS
SELECT cuenta_id, estado_nuevo AS estado, ocurrido_en AS desde,
       lead(ocurrido_en) OVER (PARTITION BY cuenta_id ORDER BY ocurrido_en, evento_id) AS hasta,
       lead(tipo_evento) OVER (PARTITION BY cuenta_id ORDER BY ocurrido_en, evento_id) AS siguiente_evento
FROM core.evento_cuenta;
CREATE INDEX ON tmp_estado (cuenta_id, desde);

-- Límite diario vigente en el tiempo (a partir de los cambios de límite)
CREATE TEMP TABLE tmp_limite AS
WITH cambios AS (
  SELECT e.cuenta_id, e.ocurrido_en, cl.valor_anterior, cl.valor_nuevo,
         row_number() OVER w AS n, lead(e.ocurrido_en) OVER w AS siguiente
  FROM core.evento_cuenta e
  JOIN core.cambio_limite cl ON cl.evento_id = e.evento_id
  WINDOW w AS (PARTITION BY e.cuenta_id ORDER BY e.ocurrido_en, e.evento_id)
)
SELECT cuenta_id, NULL::timestamptz AS desde, ocurrido_en AS hasta, valor_anterior AS valor FROM cambios WHERE n = 1
UNION ALL
SELECT cuenta_id, ocurrido_en, siguiente, valor_nuevo FROM cambios
UNION ALL
SELECT c.cuenta_id, NULL, NULL, c.limite_retiro_diario FROM core.cuenta c
WHERE NOT EXISTS (SELECT 1 FROM cambios x WHERE x.cuenta_id = c.cuenta_id);
CREATE INDEX ON tmp_limite (cuenta_id);

-- Movimientos que afectan cuentas de clientes, con su fecha contable
CREATE TEMP TABLE tmp_mov AS
SELECT a.transaccion_id, a.cuenta_id, a.naturaleza, a.valor, t.fecha_contabilizacion AS ts
FROM fin.asiento_contable a
JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
WHERE a.cuenta_id IS NOT NULL;
ANALYZE tmp_estado, tmp_limite, tmp_mov;

WITH controles (orden, control, esperado, obtenido) AS (
  VALUES
  (1,  'S5 transacciones POSTED',                                    1000000::bigint,
       (SELECT count(*) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED')),
  (2,  'Asientos contables (2 por transacción POSTED)',              2000000,
       (SELECT count(*) FROM fin.asiento_contable)),
  (3,  'RN-45 REJECTED/PENDING con asientos',                        0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        WHERE t.estado_codigo <> 'POSTED'
          AND EXISTS (SELECT 1 FROM fin.asiento_contable a WHERE a.transaccion_id = t.transaccion_id))),
  (4,  'RN-46 POSTED sin débito o sin crédito',                      0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        LEFT JOIN (SELECT transaccion_id, bool_or(naturaleza = 'D') AS hay_d, bool_or(naturaleza = 'C') AS hay_c
                   FROM fin.asiento_contable GROUP BY transaccion_id) a ON a.transaccion_id = t.transaccion_id
        WHERE t.estado_codigo = 'POSTED' AND NOT (coalesce(a.hay_d, false) AND coalesce(a.hay_c, false)))),
  (5,  'RN-47 transacciones descuadradas (Σ D ≠ Σ C)',               0,
       (SELECT count(*) FROM (
          SELECT transaccion_id FROM fin.asiento_contable GROUP BY transaccion_id
          HAVING sum(valor) FILTER (WHERE naturaleza = 'D') <> sum(valor) FILTER (WHERE naturaleza = 'C')) x)),
  (6,  'Asientos cuyo valor ≠ monto de la transacción',              0,
       (SELECT count(*) FROM fin.asiento_contable a JOIN fin.transaccion_financiera t USING (transaccion_id)
        WHERE a.valor <> t.monto)),
  (7,  'RN-48 saldo almacenado ≠ saldo según asientos',              0,
       (SELECT count(*) FROM core.cuenta c
        LEFT JOIN (SELECT cuenta_id, sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) AS saldo
                   FROM tmp_mov GROUP BY cuenta_id) s ON s.cuenta_id = c.cuenta_id
        WHERE c.saldo_contable <> coalesce(s.saldo, 0))),
  (8,  'RN-31 momentos con saldo por debajo del cupo de sobregiro',  0,
       (SELECT count(*) FROM (
          SELECT m.cuenta_id,
                 sum(CASE m.naturaleza WHEN 'C' THEN m.valor ELSE -m.valor END)
                   OVER (PARTITION BY m.cuenta_id ORDER BY m.ts, m.transaccion_id) AS saldo
          FROM tmp_mov m) x
        JOIN core.cuenta c ON c.cuenta_id = x.cuenta_id
        WHERE x.saldo < -c.cupo_sobregiro)),
  (9,  'RN-32/33 transferencias a la misma cuenta u otra moneda',    0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        JOIN core.cuenta o ON o.cuenta_id = t.cuenta_origen_id
        JOIN core.cuenta d ON d.cuenta_id = t.cuenta_destino_id
        WHERE t.tipo_codigo = 'TRANSFERENCIA' AND (o.moneda_codigo <> d.moneda_codigo OR o.cuenta_id = d.cuenta_id))),
  (10, 'RN-34 débitos POSTED sobre cuenta no ACTIVA',                0,
       (SELECT count(*) FROM tmp_mov m
        WHERE m.naturaleza = 'D'
          AND NOT EXISTS (SELECT 1 FROM tmp_estado e
                          WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts
                            AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado = 'ACTIVA'))),
  (11, 'RN-35 créditos POSTED sobre cuenta no ACTIVA/BLOQUEADA',     0,
       (SELECT count(*) FROM tmp_mov m
        WHERE m.naturaleza = 'C'
          AND NOT EXISTS (SELECT 1 FROM tmp_estado e
                          WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts
                            AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado IN ('ACTIVA', 'BLOQUEADA')))),
  (12, 'RN-36 movimientos antes de la apertura o después del cierre', 0,
       (SELECT count(*) FROM tmp_mov m JOIN core.cuenta c ON c.cuenta_id = m.cuenta_id
        WHERE m.ts < c.fecha_apertura OR (c.fecha_cierre IS NOT NULL AND m.ts > c.fecha_cierre))),
  (13, 'RN-37 cuenta-día con retiros sobre el límite vigente',       0,
       (SELECT count(*) FROM (
          SELECT cuenta_origen_id AS cuenta_id, fecha_contable,
                 (fecha_contable + 1)::timestamp AT TIME ZONE 'America/Bogota' AS fin_dia, sum(monto) AS total
          FROM fin.transaccion_financiera
          WHERE tipo_codigo = 'RETIRO' AND estado_codigo = 'POSTED'
          GROUP BY cuenta_origen_id, fecha_contable) r
        JOIN tmp_limite l ON l.cuenta_id = r.cuenta_id
                         AND (l.desde IS NULL OR l.desde < r.fin_dia)
                         AND (l.hasta IS NULL OR l.hasta >= r.fin_dia)
        WHERE r.total > l.valor)),
  (14, 'RN-41 reversos con monto o cuentas distintos a la original', 0,
       (SELECT count(*) FROM fin.transaccion_financiera r
        JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
        WHERE r.monto <> o.monto
           OR r.cuenta_origen_id IS DISTINCT FROM o.cuenta_destino_id
           OR r.cuenta_destino_id IS DISTINCT FROM o.cuenta_origen_id
           OR o.estado_codigo <> 'POSTED'
           OR r.fecha_solicitud <= o.fecha_contabilizacion)),
  (15, 'RN-41 asientos del reverso que no espejan la original',      0,
       (SELECT count(*) FROM (
          (SELECT r.transaccion_id, a.cuenta_contable_codigo, a.cuenta_id,
                  CASE a.naturaleza WHEN 'D' THEN 'C' ELSE 'D' END AS naturaleza, a.valor
           FROM fin.transaccion_financiera r
           JOIN fin.asiento_contable a ON a.transaccion_id = r.transaccion_reversada_id
           WHERE r.tipo_codigo = 'REVERSO' AND r.estado_codigo = 'POSTED')
          EXCEPT
          (SELECT a.transaccion_id, a.cuenta_contable_codigo, a.cuenta_id, a.naturaleza::text, a.valor
           FROM fin.transaccion_financiera r
           JOIN fin.asiento_contable a ON a.transaccion_id = r.transaccion_id
           WHERE r.tipo_codigo = 'REVERSO' AND r.estado_codigo = 'POSTED')) x)),
  (16, 'RN-42 reversos de un reverso',                               0,
       (SELECT count(*) FROM fin.transaccion_financiera r
        JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
        WHERE o.tipo_codigo = 'REVERSO')),
  (17, 'RN-44 ajustes POSTED sin aprobación de otro SUPERVISOR',     0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        WHERE t.tipo_codigo = 'AJUSTE' AND t.estado_codigo = 'POSTED'
          AND (t.aprobado_por IS NULL OR t.aprobado_por = t.creado_por
               OR NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol ro ON ro.rol_id = ur.rol_id
                              WHERE ur.usuario_id = t.aprobado_por AND ro.codigo = 'SUPERVISOR')))),
  (18, 'RN-51 reversos registrados por usuario sin rol SUPERVISOR',  0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        WHERE t.tipo_codigo = 'REVERSO'
          AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol ro ON ro.rol_id = ur.rol_id
                          WHERE ur.usuario_id = t.creado_por AND ro.codigo = 'SUPERVISOR'))),
  (19, 'RN-20 cuentas CERRADA con saldo distinto de 0',              0,
       (SELECT count(*) FROM core.cuenta WHERE estado_cuenta = 'CERRADA' AND saldo_contable <> 0)),
  (20, 'RN-54 operaciones sobre cuentas donde el usuario es titular', 0,
       (SELECT count(*) FROM fin.transaccion_financiera t
        JOIN seg.usuario u ON u.usuario_id = t.creado_por
        JOIN core.titularidad_cuenta tc ON tc.cuenta_id IN (t.cuenta_origen_id, t.cuenta_destino_id)
        JOIN core.cliente cl ON cl.cliente_id = tc.cliente_id
        WHERE cl.tipo_documento = u.tipo_documento AND cl.numero_documento = u.numero_documento)),
  (21, 'Solicitudes fuera de la ventana 2024-09-01 a 2026-08-31',    0,
       (SELECT count(*) FROM fin.transaccion_financiera
        WHERE fecha_solicitud <  '2024-09-01 00:00:00-05'
           OR fecha_solicitud >= '2026-09-01 00:00:00-05')),
  (22, 'fecha_contable ≠ día de contabilización (hora Colombia)',   0,
       (SELECT count(*) FROM fin.transaccion_financiera
        WHERE estado_codigo = 'POSTED'
          AND fecha_contable <> (fecha_contabilizacion AT TIME ZONE 'America/Bogota')::date)),
  (23, 'Movimientos en los 180 días previos a una inactivación',     0,
       (SELECT count(*) FROM tmp_mov m
        JOIN tmp_estado e ON e.cuenta_id = m.cuenta_id AND e.siguiente_evento = 'INACTIVACION'
        WHERE m.ts >= e.hasta - INTERVAL '180 days' AND m.ts < e.hasta)),
  (24, 'Cuentas con saldo que viola el cupo de sobregiro hoy',       0,
       (SELECT count(*) FROM core.cuenta WHERE saldo_disponible < -cupo_sobregiro))
)
SELECT control, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM controles
ORDER BY orden;

-- =====================================================================
-- 7. Distribuciones (informativas: deben verse NO uniformes)
-- =====================================================================
SELECT tipo_codigo, estado_codigo, count(*) AS transacciones
FROM fin.transaccion_financiera
GROUP BY ROLLUP (tipo_codigo, estado_codigo)
ORDER BY tipo_codigo NULLS LAST, estado_codigo NULLS LAST;

SELECT motivo_rechazo, count(*) AS rechazadas
FROM fin.transaccion_financiera
WHERE estado_codigo = 'REJECTED'
GROUP BY motivo_rechazo ORDER BY rechazadas DESC;

-- Estacionalidad: diciembre y quincenas más altos
SELECT to_char(fecha_contable, 'YYYY-MM') AS mes, count(*) AS posted
FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED'
GROUP BY 1 ORDER BY 1;

SELECT CASE WHEN extract(day FROM fecha_contable) IN (1, 2, 15, 16)
              OR fecha_contable >= (date_trunc('month', fecha_contable) + INTERVAL '1 month - 2 days')::date
            THEN 'quincena / fin de mes' ELSE 'resto de días' END AS tipo_dia,
       round(count(*)::numeric / count(DISTINCT fecha_contable), 0) AS promedio_diario
FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED'
GROUP BY 1;

-- Cola larga: transacciones por cuenta
WITH por_cuenta AS (
  SELECT cuenta_id, count(DISTINCT transaccion_id) AS n FROM tmp_mov GROUP BY cuenta_id
)
SELECT count(*) AS cuentas_con_movimientos,
       round(avg(n), 1) AS promedio,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY n) AS mediana,
       percentile_cont(0.95) WITHIN GROUP (ORDER BY n) AS p95,
       max(n) AS maximo
FROM por_cuenta;

-- Tamaño de la base (para decidir dónde alojarla)
SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano_base;
SELECT n.nspname || '.' || c.relname AS tabla,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano_total
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname IN ('core', 'fin', 'seg', 'ref', 'aud')
ORDER BY pg_total_relation_size(c.oid) DESC LIMIT 6;
