-- =====================================================================
-- quality_gate.sql · Banco Andino Colombia · G6 (Data Quality e integridad)
--
-- Audita la base SIN corregir nada: primero se evidencia, luego se recomienda.
-- Cada prueba devuelve:
--   test_id | categoría | dimensión | regla | tabla | esperado | obtenido | severidad | resultado | detalle
-- Severidad: CRITICA · ALTA · MEDIA · BAJA.  Resultado: PASS · WARNING · FAIL.
--
-- Puntajes (solo con pruebas ejecutadas), por dimensión y general:
--   peso de la prueba = CRITICA 4 · ALTA 3 · MEDIA 2 · BAJA 1
--   valor             = PASS 1 · WARNING 0,5 · FAIL 0
--   puntaje           = 100 × Σ(peso × valor) / Σ(peso)
-- QUALITY_GATE = FAIL si alguna prueba CRITICA (financiera o referencial) falla.
--
-- Guarda el detalle en evidence/g6_quality_results.csv.
-- Uso (desde la carpeta lab-postgresql-banco-ia):
--   psql -U postgres -d banco_andino_lab -f sql/quality_gate.sql
--   SQL Shell: \cd 'C:/…/lab-postgresql-banco-ia'  \c banco_andino_lab  \i sql/quality_gate.sql
-- Tarda cerca de 1 minuto con el millón de transacciones.
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
SET client_encoding = 'UTF8';
SET statement_timeout = 0;
SET timezone = 'America/Bogota';

-- Permite repetir el gate en la misma sesión (SQL Shell) sin reconectarse
DROP TABLE IF EXISTS pg_temp.qg, pg_temp.m, pg_temp.e, pg_temp.puntaje;

CREATE TEMP TABLE qg (
  test_id    text PRIMARY KEY,
  categoria  text,
  dimension  text,
  regla      text,
  tabla      text,
  esperado   text,
  obtenido   text,
  severidad  text,
  resultado  text,
  detalle    text
);

-- Prueba de conteo: 0 = PASS; si no, FAIL (BAJA → WARNING)
CREATE OR REPLACE FUNCTION pg_temp.cero(p_id text, p_cat text, p_dim text, p_regla text, p_tabla text, p_sev text, p_n bigint, p_detalle text DEFAULT '')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO qg VALUES (p_id, p_cat, p_dim, p_regla, p_tabla, '0', p_n::text, p_sev,
    CASE WHEN p_n = 0 THEN 'PASS' WHEN p_sev = 'BAJA' THEN 'WARNING' ELSE 'FAIL' END, p_detalle)
$$;

-- Prueba con criterio propio
CREATE OR REPLACE FUNCTION pg_temp.prueba(p_id text, p_cat text, p_dim text, p_regla text, p_tabla text, p_sev text,
                               p_esperado text, p_obtenido text, p_resultado text, p_detalle text DEFAULT '')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO qg VALUES (p_id, p_cat, p_dim, p_regla, p_tabla, p_esperado, p_obtenido, p_sev, p_resultado, p_detalle)
$$;

-- Apoyo: movimientos de cuentas de clientes y estado de cada cuenta en el tiempo
CREATE TEMP TABLE m AS
SELECT a.transaccion_id, a.cuenta_id, a.naturaleza, a.valor, t.fecha_contabilizacion AS ts
FROM fin.asiento_contable a JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
WHERE a.cuenta_id IS NOT NULL;
CREATE TEMP TABLE e AS
SELECT cuenta_id, estado_nuevo AS estado, estado_anterior, tipo_evento, ocurrido_en AS desde, evento_id,
       lead(ocurrido_en) OVER w AS hasta,
       lag(estado_nuevo) OVER w AS estado_previo,
       row_number() OVER w AS n
FROM core.evento_cuenta
WINDOW w AS (PARTITION BY cuenta_id ORDER BY ocurrido_en, evento_id);
CREATE INDEX ON e (cuenta_id, desde);
ANALYZE m, e;

-- =====================================================================
-- 1. COMPLETITUD (Data Quality)
-- =====================================================================
SELECT pg_temp.cero('C01', 'Completitud', 'Data Quality', 'Campos críticos vacíos en cliente (documento, municipio, vinculación)', 'core.cliente', 'CRITICA',
  count(*) FILTER (WHERE btrim(numero_documento) = '' OR municipio_codigo IS NULL OR fecha_vinculacion IS NULL)) FROM core.cliente \gset
SELECT pg_temp.cero('C02', 'Completitud', 'Data Quality', 'Nombres o apellidos vacíos en personas naturales', 'core.persona_natural', 'ALTA',
  count(*)) FROM core.persona_natural WHERE btrim(nombres) = '' OR btrim(apellidos) = '' \gset
SELECT pg_temp.cero('C03', 'Completitud', 'Data Quality', 'Razón social o actividad económica vacías en personas jurídicas', 'core.persona_juridica', 'ALTA',
  count(*)) FROM core.persona_juridica WHERE btrim(razon_social) = '' OR actividad_economica IS NULL \gset
SELECT pg_temp.prueba('C04', 'Completitud', 'Data Quality', 'Clientes sin correo electrónico (campo opcional)', 'core.cliente', 'BAJA',
  '≤ 5 %', round(100.0 * count(*) FILTER (WHERE email IS NULL) / count(*), 1) || ' %',
  CASE WHEN count(*) FILTER (WHERE email IS NULL) <= 0.05 * count(*) THEN 'PASS' ELSE 'WARNING' END,
  count(*) FILTER (WHERE email IS NULL) || ' clientes sin correo; se recomienda campaña de actualización de datos') FROM core.cliente \gset
SELECT pg_temp.cero('C05', 'Completitud', 'Data Quality', 'Transacciones POSTED sin fecha contable o de contabilización', 'fin.transaccion_financiera', 'CRITICA',
  count(*)) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED' AND (fecha_contable IS NULL OR fecha_contabilizacion IS NULL) \gset
SELECT pg_temp.cero('C06', 'Completitud', 'Data Quality', 'Transacciones REJECTED sin motivo (RN-45)', 'fin.transaccion_financiera', 'ALTA',
  count(*)) FROM fin.transaccion_financiera WHERE estado_codigo = 'REJECTED' AND (motivo_rechazo IS NULL OR btrim(motivo_rechazo) = '') \gset

-- =====================================================================
-- 2. UNICIDAD (Data Quality · críticas)
-- =====================================================================
SELECT pg_temp.cero('U01', 'Unicidad', 'Data Quality', 'Documentos de cliente duplicados (RN-01)', 'core.cliente', 'CRITICA', count(*))
FROM (SELECT tipo_documento, numero_documento FROM core.cliente WHERE tipo_documento <> 'NIT' GROUP BY 1, 2 HAVING count(*) > 1) x \gset
SELECT pg_temp.cero('U02', 'Unicidad', 'Data Quality', 'NIT duplicados', 'core.cliente', 'CRITICA', count(*))
FROM (SELECT numero_documento FROM core.cliente WHERE tipo_documento = 'NIT' GROUP BY 1 HAVING count(*) > 1) x \gset
SELECT pg_temp.cero('U03', 'Unicidad', 'Data Quality', 'Números de cuenta duplicados (RN-11)', 'core.cuenta', 'CRITICA', count(*))
FROM (SELECT numero_cuenta FROM core.cuenta GROUP BY 1 HAVING count(*) > 1) x \gset
SELECT pg_temp.cero('U04', 'Unicidad', 'Data Quality', 'Claves de idempotencia duplicadas (RN-38)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM (SELECT idempotency_key FROM fin.transaccion_financiera GROUP BY 1 HAVING count(*) > 1) x \gset
SELECT pg_temp.cero('U05', 'Unicidad', 'Data Quality', 'Usuarios internos con login o documento duplicado', 'seg.usuario', 'ALTA',
  (SELECT count(*) FROM (SELECT login FROM seg.usuario GROUP BY 1 HAVING count(*) > 1) a)
  + (SELECT count(*) FROM (SELECT tipo_documento, numero_documento FROM seg.usuario GROUP BY 1, 2 HAVING count(*) > 1) b)) \gset
SELECT pg_temp.cero('U06', 'Unicidad', 'Data Quality', 'Posibles personas repetidas (mismo nombre, apellidos y fecha de nacimiento)', 'core.persona_natural', 'BAJA', count(*))
FROM (SELECT nombres, apellidos, fecha_nacimiento FROM core.persona_natural GROUP BY 1, 2, 3 HAVING count(*) > 1) x \gset
SELECT pg_temp.cero('U07', 'Unicidad', 'Data Quality', 'Transacciones reversadas más de una vez (RN-42)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM (SELECT transaccion_reversada_id FROM fin.transaccion_financiera WHERE transaccion_reversada_id IS NOT NULL GROUP BY 1 HAVING count(*) > 1) x \gset

-- =====================================================================
-- 3. INTEGRIDAD REFERENCIAL (Integrity · críticas)
-- =====================================================================
SELECT pg_temp.cero('R01', 'Integridad referencial', 'Integrity', 'Titularidades con cliente o cuenta inexistente', 'core.titularidad_cuenta', 'CRITICA', count(*))
FROM core.titularidad_cuenta t
LEFT JOIN core.cliente cl ON cl.cliente_id = t.cliente_id LEFT JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
WHERE cl.cliente_id IS NULL OR c.cuenta_id IS NULL \gset
SELECT pg_temp.cero('R02', 'Integridad referencial', 'Integrity', 'Asientos sin transacción o con cuenta inexistente', 'fin.asiento_contable', 'CRITICA', count(*))
FROM fin.asiento_contable a
LEFT JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
LEFT JOIN core.cuenta c ON c.cuenta_id = a.cuenta_id
WHERE t.transaccion_id IS NULL OR (a.cuenta_id IS NOT NULL AND c.cuenta_id IS NULL) \gset
SELECT pg_temp.cero('R03', 'Integridad referencial', 'Integrity', 'Transacciones con cuenta origen/destino o usuario inexistente', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera t
LEFT JOIN core.cuenta o ON o.cuenta_id = t.cuenta_origen_id
LEFT JOIN core.cuenta d ON d.cuenta_id = t.cuenta_destino_id
LEFT JOIN seg.usuario u ON u.usuario_id = t.creado_por
WHERE (t.cuenta_origen_id IS NOT NULL AND o.cuenta_id IS NULL) OR (t.cuenta_destino_id IS NOT NULL AND d.cuenta_id IS NULL) OR u.usuario_id IS NULL \gset
SELECT pg_temp.cero('R04', 'Integridad referencial', 'Integrity', 'Eventos de cuenta huérfanos', 'core.evento_cuenta', 'CRITICA', count(*))
FROM core.evento_cuenta ev LEFT JOIN core.cuenta c ON c.cuenta_id = ev.cuenta_id WHERE c.cuenta_id IS NULL \gset
SELECT pg_temp.cero('R05', 'Integridad referencial', 'Integrity', 'Clientes sin subtipo o con los dos (RN-02)', 'core.cliente', 'CRITICA', count(*))
FROM core.cliente c
WHERE (EXISTS (SELECT 1 FROM core.persona_natural n WHERE n.cliente_id = c.cliente_id))
    = (EXISTS (SELECT 1 FROM core.persona_juridica j WHERE j.cliente_id = c.cliente_id)) \gset
SELECT pg_temp.cero('R06', 'Integridad referencial', 'Integrity', 'Cuentas no cerradas sin titular principal vigente (RN-13)', 'core.cuenta', 'CRITICA', count(*))
FROM core.cuenta c
WHERE c.estado_cuenta <> 'CERRADA'
  AND NOT EXISTS (SELECT 1 FROM core.titularidad_cuenta t WHERE t.cuenta_id = c.cuenta_id AND t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL) \gset
SELECT pg_temp.cero('R07', 'Integridad referencial', 'Integrity', 'Claves foráneas o CHECK sin validar (NOT VALID)', 'pg_constraint', 'ALTA', count(*))
FROM pg_constraint WHERE contype IN ('f', 'c') AND NOT convalidated
  AND connamespace::regnamespace::text IN ('ref', 'seg', 'core', 'fin', 'aud') \gset

-- =====================================================================
-- 4. VALIDEZ (Data Quality)
-- =====================================================================
SELECT pg_temp.cero('V01', 'Validez', 'Data Quality', 'Montos ≤ 0 o con más de 2 decimales (RN-30)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera WHERE monto <= 0 OR monto <> round(monto, 2) \gset
SELECT pg_temp.cero('V02', 'Validez', 'Data Quality', 'NIT con dígito de verificación incorrecto (RN-04)', 'core.cliente', 'ALTA', count(*))
FROM core.cliente WHERE tipo_documento = 'NIT' AND digito_verificacion IS DISTINCT FROM ref.fn_dv_nit(numero_documento) \gset
SELECT pg_temp.cero('V03', 'Validez', 'Data Quality', 'Titulares naturales menores de 18 años al abrir (RN-08)', 'core.titularidad_cuenta', 'ALTA', count(*))
FROM core.titularidad_cuenta t JOIN core.cuenta c USING (cuenta_id) JOIN core.persona_natural p ON p.cliente_id = t.cliente_id
WHERE (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < p.fecha_nacimiento + INTERVAL '18 years' \gset
SELECT pg_temp.cero('V04', 'Validez', 'Data Quality', 'Fechas de nacimiento imposibles (futuras o edad > 110 años)', 'core.persona_natural', 'MEDIA', count(*))
FROM core.persona_natural WHERE fecha_nacimiento > current_date OR fecha_nacimiento < current_date - INTERVAL '110 years' \gset
SELECT pg_temp.cero('V05', 'Validez', 'Data Quality', 'Teléfonos que no son celulares colombianos de 10 dígitos', 'core.cliente', 'BAJA', count(*))
FROM core.cliente WHERE telefono IS NOT NULL AND telefono !~ '^3[0-9]{9}$' \gset
SELECT pg_temp.cero('V06', 'Validez', 'Data Quality', 'Saldo retenido negativo o mayor que el saldo contable positivo', 'core.cuenta', 'ALTA', count(*))
FROM core.cuenta WHERE saldo_retenido < 0 OR (saldo_retenido > 0 AND saldo_retenido > greatest(saldo_contable, 0)) \gset

-- =====================================================================
-- 5. CONSISTENCIA GEOGRÁFICA (Data Quality)
-- =====================================================================
SELECT pg_temp.cero('G01', 'Geográfica', 'Data Quality', 'Municipios cuyo código no empieza por el del departamento (RN-07)', 'ref.municipio', 'ALTA', count(*))
FROM ref.municipio WHERE left(municipio_codigo, 2) <> departamento_codigo \gset
SELECT pg_temp.cero('G02', 'Geográfica', 'Data Quality', 'Clientes u oficinas en municipios fuera del catálogo DIVIPOLA', 'core.cliente / ref.oficina', 'ALTA', count(*))
FROM (SELECT municipio_codigo FROM core.cliente UNION ALL SELECT municipio_codigo FROM ref.oficina) x
WHERE NOT EXISTS (SELECT 1 FROM ref.municipio mu WHERE mu.municipio_codigo = x.municipio_codigo) \gset
SELECT pg_temp.cero('G03', 'Geográfica', 'Data Quality', 'Departamentos del catálogo sin ningún municipio', 'ref.departamento', 'BAJA', count(*))
FROM ref.departamento d WHERE NOT EXISTS (SELECT 1 FROM ref.municipio mu WHERE mu.departamento_codigo = d.departamento_codigo) \gset

-- =====================================================================
-- 6. CONSISTENCIA TEMPORAL (Data Quality · críticas)
-- =====================================================================
SELECT pg_temp.cero('T01', 'Temporal', 'Data Quality', 'Movimientos antes de la apertura o después del cierre (RN-36)', 'fin.asiento_contable', 'CRITICA', count(*))
FROM m JOIN core.cuenta c ON c.cuenta_id = m.cuenta_id
WHERE m.ts < c.fecha_apertura OR (c.fecha_cierre IS NOT NULL AND m.ts > c.fecha_cierre) \gset
SELECT pg_temp.cero('T02', 'Temporal', 'Data Quality', 'Débitos de cuentas que no estaban ACTIVAS (RN-34)', 'fin.asiento_contable', 'CRITICA', count(*))
FROM m WHERE m.naturaleza = 'D'
  AND NOT EXISTS (SELECT 1 FROM e WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado = 'ACTIVA') \gset
SELECT pg_temp.cero('T03', 'Temporal', 'Data Quality', 'Créditos a cuentas que no estaban ACTIVAS ni BLOQUEADAS (RN-35)', 'fin.asiento_contable', 'CRITICA', count(*))
FROM m WHERE m.naturaleza = 'C'
  AND NOT EXISTS (SELECT 1 FROM e WHERE e.cuenta_id = m.cuenta_id AND e.desde <= m.ts AND (e.hasta IS NULL OR m.ts < e.hasta) AND e.estado IN ('ACTIVA', 'BLOQUEADA')) \gset
SELECT pg_temp.cero('T04', 'Temporal', 'Data Quality', 'Primer evento distinto de CREACION (RN-23)', 'core.evento_cuenta', 'ALTA', count(*))
FROM e WHERE n = 1 AND tipo_evento <> 'CREACION' \gset
SELECT pg_temp.cero('T05', 'Temporal', 'Data Quality', 'Eventos cuyo estado anterior no es el estado previo real de la cuenta', 'core.evento_cuenta', 'ALTA', count(*))
FROM e WHERE n > 1 AND estado_anterior IS DISTINCT FROM estado_previo \gset
SELECT pg_temp.cero('T06', 'Temporal', 'Data Quality', 'Fecha contable distinta del día de contabilización (hora Colombia)', 'fin.transaccion_financiera', 'MEDIA', count(*))
FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED' AND fecha_contable <> (fecha_contabilizacion AT TIME ZONE 'America/Bogota')::date \gset
SELECT pg_temp.cero('T07', 'Temporal', 'Data Quality', 'Reversos registrados antes de la transacción original', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera r JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
WHERE r.fecha_solicitud <= o.fecha_contabilizacion \gset
SELECT pg_temp.cero('T08', 'Temporal', 'Data Quality', 'Cuentas abiertas antes de la vinculación del titular', 'core.titularidad_cuenta', 'MEDIA', count(*))
FROM core.titularidad_cuenta t JOIN core.cuenta c USING (cuenta_id) JOIN core.cliente cl USING (cliente_id)
WHERE (c.fecha_apertura AT TIME ZONE 'America/Bogota')::date < cl.fecha_vinculacion \gset

-- =====================================================================
-- 7. CONSISTENCIA FINANCIERA (Integrity · críticas)
-- =====================================================================
SELECT pg_temp.prueba('F01', 'Financiera', 'Integrity', 'Transacciones POSTED cuadradas: Σ débitos = Σ créditos (RN-47)', 'fin.asiento_contable', 'CRITICA',
  '100 %', round(100.0 * count(*) FILTER (WHERE cuadrada) / count(*), 4) || ' %',
  CASE WHEN bool_and(cuadrada) THEN 'PASS' ELSE 'FAIL' END,
  count(*) FILTER (WHERE NOT cuadrada) || ' transacciones descuadradas de ' || count(*)) FROM fin.v_balance_transaccion \gset
SELECT pg_temp.cero('F02', 'Financiera', 'Integrity', 'Transacciones REJECTED o PENDING con asientos (RN-45)', 'fin.asiento_contable', 'CRITICA', count(*))
FROM fin.transaccion_financiera t WHERE t.estado_codigo <> 'POSTED' AND EXISTS (SELECT 1 FROM fin.asiento_contable a WHERE a.transaccion_id = t.transaccion_id) \gset
SELECT pg_temp.cero('F03', 'Financiera', 'Integrity', 'Momentos con saldo por debajo del cupo de sobregiro (RN-31)', 'fin.asiento_contable', 'CRITICA', count(*))
FROM (SELECT m.cuenta_id, sum(CASE m.naturaleza WHEN 'C' THEN m.valor ELSE -m.valor END) OVER (PARTITION BY m.cuenta_id ORDER BY m.ts, m.transaccion_id) AS saldo FROM m) x
JOIN core.cuenta c ON c.cuenta_id = x.cuenta_id WHERE x.saldo < -c.cupo_sobregiro \gset
SELECT pg_temp.cero('F04', 'Financiera', 'Integrity', 'Cuentas CERRADAS con saldo (RN-20)', 'core.cuenta', 'CRITICA', count(*))
FROM core.cuenta WHERE estado_cuenta = 'CERRADA' AND (saldo_contable <> 0 OR saldo_retenido <> 0) \gset
WITH cambios AS (
  SELECT ev.cuenta_id, ev.ocurrido_en, cl.valor_anterior, cl.valor_nuevo, row_number() OVER w AS n, lead(ev.ocurrido_en) OVER w AS siguiente
  FROM core.evento_cuenta ev JOIN core.cambio_limite cl ON cl.evento_id = ev.evento_id
  WINDOW w AS (PARTITION BY ev.cuenta_id ORDER BY ev.ocurrido_en, ev.evento_id)
), limite AS (
  SELECT cuenta_id, NULL::timestamptz AS desde, ocurrido_en AS hasta, valor_anterior AS valor FROM cambios WHERE n = 1
  UNION ALL SELECT cuenta_id, ocurrido_en, siguiente, valor_nuevo FROM cambios
  UNION ALL SELECT c.cuenta_id, NULL, NULL, c.limite_retiro_diario FROM core.cuenta c WHERE NOT EXISTS (SELECT 1 FROM cambios x WHERE x.cuenta_id = c.cuenta_id)
), r AS (
  SELECT cuenta_origen_id AS cuenta_id, sum(monto) AS total, (fecha_contable + 1)::timestamp AT TIME ZONE 'America/Bogota' AS fin_dia
  FROM fin.transaccion_financiera WHERE tipo_codigo = 'RETIRO' AND estado_codigo = 'POSTED' GROUP BY cuenta_origen_id, fecha_contable)
SELECT pg_temp.cero('F05', 'Financiera', 'Integrity', 'Cuenta-día con retiros por encima del límite vigente (RN-37)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM r JOIN limite l ON l.cuenta_id = r.cuenta_id AND (l.desde IS NULL OR l.desde < r.fin_dia) AND (l.hasta IS NULL OR l.hasta >= r.fin_dia)
WHERE r.total > l.valor \gset
SELECT pg_temp.cero('F06', 'Financiera', 'Integrity', 'Transferencias a la misma cuenta o entre monedas distintas (RN-32, RN-33)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera t JOIN core.cuenta o ON o.cuenta_id = t.cuenta_origen_id JOIN core.cuenta d ON d.cuenta_id = t.cuenta_destino_id
WHERE t.tipo_codigo = 'TRANSFERENCIA' AND (o.cuenta_id = d.cuenta_id OR o.moneda_codigo <> d.moneda_codigo) \gset
SELECT pg_temp.cero('F07', 'Financiera', 'Integrity', 'Reversos con monto o cuentas distintos de la original (RN-41)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera r JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
WHERE r.monto <> o.monto OR r.cuenta_origen_id IS DISTINCT FROM o.cuenta_destino_id OR r.cuenta_destino_id IS DISTINCT FROM o.cuenta_origen_id \gset

-- =====================================================================
-- 8. RECONCILIACIÓN DE SALDOS (Integrity · críticas)
-- =====================================================================
SELECT pg_temp.prueba('S01', 'Reconciliación', 'Integrity', 'Saldo almacenado = saldo según el ledger en cada cuenta (RN-48)', 'core.cuenta', 'CRITICA',
  '0 diferencias', count(*) FILTER (WHERE diferencia <> 0) || ' cuentas · diferencia total ' || coalesce(sum(abs(diferencia)), 0),
  CASE WHEN count(*) FILTER (WHERE diferencia <> 0) = 0 THEN 'PASS' ELSE 'FAIL' END,
  count(*) || ' cuentas revisadas') FROM core.v_saldo_vs_ledger \gset
SELECT pg_temp.prueba('S02', 'Reconciliación', 'Integrity', 'Σ saldos por cuenta contable y moneda = Σ del ledger', 'core.cuenta / fin.asiento_contable', 'CRITICA',
  '0 diferencias', count(*) FILTER (WHERE x.saldos IS DISTINCT FROM x.ledger)::text,
  CASE WHEN count(*) FILTER (WHERE x.saldos IS DISTINCT FROM x.ledger) = 0 THEN 'PASS' ELSE 'FAIL' END,
  count(*) || ' combinaciones cuenta contable × moneda')
FROM (
  SELECT p.cuenta_contable_codigo, c.moneda_codigo, sum(c.saldo_contable) AS saldos,
         (SELECT sum(CASE a.naturaleza WHEN 'C' THEN a.valor ELSE -a.valor END)
          FROM fin.asiento_contable a JOIN core.cuenta c2 ON c2.cuenta_id = a.cuenta_id
          WHERE a.cuenta_contable_codigo = p.cuenta_contable_codigo AND c2.moneda_codigo = c.moneda_codigo) AS ledger
  FROM core.cuenta c JOIN core.producto p ON p.producto_codigo = c.producto_codigo
  GROUP BY p.cuenta_contable_codigo, c.moneda_codigo) x \gset
SELECT pg_temp.cero('S03', 'Reconciliación', 'Integrity', 'Estado de la cuenta distinto de su último evento (RN-25)', 'core.cuenta', 'ALTA', count(*))
FROM core.v_estado_vs_eventos WHERE NOT coincide \gset
SELECT pg_temp.cero('S04', 'Reconciliación', 'Integrity', 'Límite diario distinto del último cambio registrado (RN-27)', 'core.cuenta', 'ALTA', count(*))
FROM core.cuenta c
JOIN LATERAL (SELECT cl.valor_nuevo FROM e JOIN core.cambio_limite cl ON cl.evento_id = e.evento_id
              WHERE e.cuenta_id = c.cuenta_id ORDER BY e.desde DESC, e.evento_id DESC LIMIT 1) u ON true
WHERE u.valor_nuevo <> c.limite_retiro_diario \gset
SELECT pg_temp.cero('S05', 'Reconciliación', 'Integrity', 'Fecha de cierre distinta del evento CIERRE', 'core.cuenta', 'MEDIA', count(*))
FROM core.cuenta c LEFT JOIN core.evento_cuenta ev ON ev.cuenta_id = c.cuenta_id AND ev.tipo_evento = 'CIERRE'
WHERE c.fecha_cierre IS DISTINCT FROM ev.ocurrido_en \gset

-- =====================================================================
-- 9. REGLAS DE NEGOCIO (Integrity)
-- =====================================================================
SELECT pg_temp.cero('N01', 'Reglas de negocio', 'Integrity', 'Producto no permitido para el tipo de titular (RN-14, RN-15)', 'core.titularidad_cuenta', 'ALTA', count(*))
FROM core.titularidad_cuenta t JOIN core.cuenta c USING (cuenta_id) JOIN core.producto p USING (producto_codigo) JOIN core.cliente cl USING (cliente_id)
WHERE p.tipo_cliente_permitido IS NOT NULL AND p.tipo_cliente_permitido <> cl.tipo_cliente \gset
SELECT pg_temp.cero('N02', 'Reglas de negocio', 'Integrity', 'Cuentas con más titulares vigentes que el máximo del producto (RN-16)', 'core.titularidad_cuenta', 'ALTA', count(*))
FROM (SELECT c.cuenta_id FROM core.cuenta c JOIN core.producto p USING (producto_codigo)
      JOIN core.titularidad_cuenta t ON t.cuenta_id = c.cuenta_id AND t.vigente_hasta IS NULL
      GROUP BY c.cuenta_id, p.max_titulares HAVING count(*) > p.max_titulares) x \gset
SELECT pg_temp.cero('N03', 'Reglas de negocio', 'Integrity', 'Cupo de sobregiro fuera de cuentas CORRIENTE (RN-17)', 'core.cuenta', 'ALTA', count(*))
FROM core.cuenta c JOIN core.producto p USING (producto_codigo) WHERE c.cupo_sobregiro > 0 AND NOT p.permite_sobregiro \gset
SELECT pg_temp.cero('N04', 'Reglas de negocio', 'Integrity', 'Ajustes POSTED sin aprobación de otro SUPERVISOR (RN-44)', 'fin.transaccion_financiera', 'CRITICA', count(*))
FROM fin.transaccion_financiera t
WHERE t.tipo_codigo = 'AJUSTE' AND t.estado_codigo = 'POSTED'
  AND (t.aprobado_por IS NULL OR t.aprobado_por = t.creado_por
       OR NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id WHERE ur.usuario_id = t.aprobado_por AND r.codigo = 'SUPERVISOR')) \gset
SELECT pg_temp.cero('N05', 'Reglas de negocio', 'Integrity', 'Reversos registrados por usuarios sin rol SUPERVISOR (RN-51)', 'fin.transaccion_financiera', 'ALTA', count(*))
FROM fin.transaccion_financiera t
WHERE t.tipo_codigo = 'REVERSO'
  AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id WHERE ur.usuario_id = t.creado_por AND r.codigo = 'SUPERVISOR') \gset
SELECT pg_temp.cero('N06', 'Reglas de negocio', 'Integrity', 'Usuarios que operaron cuentas de las que son titulares (RN-54)', 'fin.transaccion_financiera', 'ALTA', count(*))
FROM fin.transaccion_financiera t JOIN seg.usuario u ON u.usuario_id = t.creado_por
JOIN core.titularidad_cuenta tc ON tc.cuenta_id IN (t.cuenta_origen_id, t.cuenta_destino_id)
JOIN core.cliente cl ON cl.cliente_id = tc.cliente_id
WHERE cl.tipo_documento = u.tipo_documento AND cl.numero_documento = u.numero_documento \gset
SELECT pg_temp.cero('N07', 'Reglas de negocio', 'Integrity', 'Desbloqueos, cierres o cambios de límite sin SUPERVISOR (RN-28)', 'core.evento_cuenta', 'ALTA', count(*))
FROM core.evento_cuenta ev
WHERE ev.tipo_evento IN ('DESBLOQUEO', 'CIERRE', 'CAMBIO_LIMITE')
  AND NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur JOIN seg.rol r ON r.rol_id = ur.rol_id WHERE ur.usuario_id = ev.registrado_por AND r.codigo = 'SUPERVISOR') \gset
SELECT pg_temp.cero('N08', 'Reglas de negocio', 'Integrity', 'Bloqueos sin motivo (RN-29)', 'core.evento_cuenta', 'MEDIA', count(*))
FROM core.evento_cuenta WHERE tipo_evento = 'BLOQUEO' AND (motivo IS NULL OR btrim(motivo) = '') \gset

-- =====================================================================
-- 10. DISTRIBUCIONES (Data Quality · sin uniformidad artificial)
-- =====================================================================
WITH d AS (SELECT mu.departamento_codigo, count(*) AS n FROM core.cliente c JOIN ref.municipio mu USING (municipio_codigo) GROUP BY 1)
SELECT pg_temp.prueba('D01', 'Distribución', 'Data Quality', 'Clientes por departamento no uniformes', 'core.cliente', 'MEDIA',
  'mayor / promedio > 3', round(max(n)::numeric / avg(n), 1)::text, CASE WHEN max(n)::numeric / avg(n) > 3 THEN 'PASS' ELSE 'WARNING' END) FROM d \gset
WITH k AS (SELECT cliente_id, count(*) AS n FROM core.titularidad_cuenta WHERE rol_titular = 'PRINCIPAL' GROUP BY 1)
SELECT pg_temp.prueba('D02', 'Distribución', 'Data Quality', 'Cuentas por cliente con cola larga', 'core.titularidad_cuenta', 'MEDIA',
  'máximo / mediana ≥ 10', round(max(n) / percentile_cont(0.5) WITHIN GROUP (ORDER BY n)::numeric, 1)::text,
  CASE WHEN max(n) / percentile_cont(0.5) WITHIN GROUP (ORDER BY n) >= 10 THEN 'PASS' ELSE 'WARNING' END) FROM k \gset
WITH h AS (SELECT extract(hour FROM fecha_contabilizacion)::int AS hora, count(*) AS n FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED' GROUP BY 1)
SELECT pg_temp.prueba('D03', 'Distribución', 'Data Quality', 'Patrón horario de transacciones', 'fin.transaccion_financiera', 'MEDIA',
  'pico / valle ≥ 5', round(max(n)::numeric / min(n), 1)::text, CASE WHEN max(n)::numeric / min(n) >= 5 THEN 'PASS' ELSE 'WARNING' END) FROM h \gset
SELECT pg_temp.prueba('D04', 'Distribución', 'Data Quality', 'Montos sesgados: mediana < promedio', 'fin.transaccion_financiera', 'MEDIA',
  'mediana < promedio', percentile_cont(0.5) WITHIN GROUP (ORDER BY monto)::numeric(18,0) || ' < ' || round(avg(monto), 0),
  CASE WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY monto) < avg(monto) THEN 'PASS' ELSE 'WARNING' END)
FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED' \gset
SELECT pg_temp.prueba('D05', 'Distribución', 'Data Quality', 'Mayoría de cuentas ACTIVAS y minorías en otros estados', 'core.cuenta', 'MEDIA',
  'ACTIVA > 50 % y 4 estados', round(100.0 * count(*) FILTER (WHERE estado_cuenta = 'ACTIVA') / count(*), 1) || ' % activas · ' || count(DISTINCT estado_cuenta) || ' estados',
  CASE WHEN count(*) FILTER (WHERE estado_cuenta = 'ACTIVA') > count(*) / 2 AND count(DISTINCT estado_cuenta) >= 4 THEN 'PASS' ELSE 'WARNING' END) FROM core.cuenta \gset

-- =====================================================================
-- 11. DISEÑO (Database Design)
-- =====================================================================
SELECT pg_temp.cero('DS01', 'Diseño', 'Database Design', 'Columnas float, real o money (dinero debe ser NUMERIC)', 'information_schema.columns', 'ALTA', count(*))
FROM information_schema.columns WHERE table_schema IN ('ref', 'seg', 'core', 'fin', 'aud') AND data_type IN ('real', 'double precision', 'money') \gset
SELECT pg_temp.cero('DS02', 'Diseño', 'Database Design', 'Tablas sin clave primaria', 'pg_class', 'ALTA', count(*))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud')
  AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p') \gset
SELECT pg_temp.cero('DS03', 'Diseño', 'Database Design', 'Tablas sin comentario (documentación en la base)', 'pg_class', 'BAJA', count(*))
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud') AND obj_description(c.oid, 'pg_class') IS NULL \gset
SELECT pg_temp.cero('DS04', 'Diseño', 'Database Design', 'Momentos (eventos) guardados sin zona horaria', 'information_schema.columns', 'MEDIA', count(*),
  'Las columnas de momento deben ser timestamptz')
FROM information_schema.columns WHERE table_schema IN ('ref', 'seg', 'core', 'fin', 'aud') AND data_type = 'timestamp without time zone' \gset
SELECT pg_temp.cero('DS05', 'Diseño', 'Database Design', 'Claves foráneas sin índice que las soporte', 'pg_constraint', 'BAJA', count(*),
  'No es un error de integridad: afecta joins y borrados. Se evalúa en G7 con EXPLAIN (decisión DC-06)')
FROM pg_constraint k
WHERE k.contype = 'f' AND k.connamespace::regnamespace::text IN ('ref', 'seg', 'core', 'fin', 'aud')
  AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = k.conrelid
                    AND (i.indkey::int2[])[0:array_length(k.conkey, 1) - 1] @> k.conkey
                    AND k.conkey @> (i.indkey::int2[])[0:array_length(k.conkey, 1) - 1]) \gset
SELECT pg_temp.cero('DS06', 'Diseño', 'Database Design', 'Funciones SECURITY DEFINER sin search_path fijo', 'pg_proc', 'ALTA', count(*))
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud') AND p.prosecdef
  AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg WHERE cfg LIKE 'search_path=%') \gset
SELECT pg_temp.cero('DS07', 'Diseño', 'Database Design', 'Funciones del banco ejecutables por PUBLIC', 'pg_proc', 'ALTA', count(*))
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('ref', 'seg', 'core', 'fin', 'aud') AND p.prokind IN ('f', 'p') AND has_function_privilege('public', p.oid, 'EXECUTE') \gset
SELECT pg_temp.cero('DS08', 'Diseño', 'Database Design', 'Roles de la aplicación con escritura directa en tablas de dinero', 'fin.*', 'CRITICA', count(*))
FROM (VALUES ('banco_consulta'), ('banco_cajero'), ('banco_supervisor'), ('banco_auditor')) r(rol)
CROSS JOIN (VALUES ('fin.transaccion_financiera'), ('fin.asiento_contable'), ('core.cuenta')) t(tabla)
WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.rol)
  AND (has_table_privilege(r.rol, t.tabla, 'INSERT') OR has_table_privilege(r.rol, t.tabla, 'UPDATE') OR has_table_privilege(r.rol, t.tabla, 'DELETE')) \gset

-- =====================================================================
-- 12. AUDITORÍA (Auditability)
-- =====================================================================
SELECT pg_temp.prueba('A01', 'Auditoría', 'Auditability', 'Triggers de auditoría activos en las tablas críticas (RN-52)', 'pg_trigger', 'CRITICA',
  '8 de 8', count(*) FILTER (WHERE tgenabled <> 'D') || ' de 8', CASE WHEN count(*) FILTER (WHERE tgenabled <> 'D') = 8 THEN 'PASS' ELSE 'FAIL' END,
  coalesce(string_agg(tgname, ', ') FILTER (WHERE tgenabled = 'D'), 'ninguno desactivado'))
FROM pg_trigger WHERE tgname LIKE 'trg_auditar_%' AND NOT tgisinternal \gset
SELECT pg_temp.prueba('A02', 'Auditoría', 'Auditability', 'Triggers de inmutabilidad activos (RN-40, RN-53)', 'pg_trigger', 'CRITICA',
  '6 de 6', count(*) FILTER (WHERE tgenabled <> 'D') || ' de 6', CASE WHEN count(*) FILTER (WHERE tgenabled <> 'D') = 6 THEN 'PASS' ELSE 'FAIL' END,
  coalesce(string_agg(tgname, ', ') FILTER (WHERE tgenabled = 'D'), 'ninguno desactivado'))
FROM pg_trigger
WHERE tgname IN ('trg_transaccion_inmutable', 'trg_asiento_inmutable', 'trg_auditoria_inmutable',
                 'trg_transaccion_sin_truncate', 'trg_asiento_sin_truncate', 'trg_auditoria_sin_truncate') \gset
SELECT pg_temp.cero('A03', 'Auditoría', 'Auditability', 'Registros de auditoría incompletos (quién, qué, cuándo, registro, valores)', 'aud.log_auditoria', 'ALTA', count(*))
FROM aud.log_auditoria
WHERE ocurrido_en IS NULL OR usuario_bd IS NULL OR tabla IS NULL OR registro = '{}'::jsonb
   OR (operacion IN ('INSERT', 'UPDATE') AND valores_despues IS NULL)
   OR (operacion IN ('UPDATE', 'DELETE') AND valores_antes IS NULL) \gset
WITH cargadas (tabla) AS (VALUES ('usuario'), ('cliente'), ('cuenta'), ('titularidad_cuenta'), ('evento_cuenta'),
                                 ('transaccion_financiera'), ('asiento_contable'))
SELECT pg_temp.cero('A04', 'Auditoría', 'Auditability', 'Cargas masivas sin rastro en la auditoría (quién cargó, cuándo, cuántas filas)', 'aud.log_auditoria', 'ALTA',
  count(*), coalesce('Sin registro de carga: ' || string_agg(c.tabla, ', '), 'todas las cargas tienen registro'))
FROM cargadas c
WHERE NOT EXISTS (SELECT 1 FROM aud.log_auditoria l WHERE l.tabla = c.tabla AND l.registro ? 'carga') \gset
SELECT pg_temp.cero('A05', 'Auditoría', 'Auditability', 'Transacciones sin usuario interno que las registró o con usuario sin rol', 'fin.transaccion_financiera', 'ALTA', count(*))
FROM fin.transaccion_financiera t
WHERE NOT EXISTS (SELECT 1 FROM seg.usuario_rol ur WHERE ur.usuario_id = t.creado_por) \gset
SELECT pg_temp.cero('A06', 'Auditoría', 'Auditability', 'Asignaciones de rol hechas por el mismo usuario (RN-50)', 'seg.usuario_rol', 'ALTA', count(*))
FROM seg.usuario_rol WHERE asignado_por = usuario_id \gset

-- =====================================================================
-- RESULTADOS Y PUNTAJES
-- =====================================================================
CREATE TEMP TABLE puntaje AS
SELECT dimension,
       count(*) AS pruebas,
       count(*) FILTER (WHERE resultado = 'PASS') AS pass,
       count(*) FILTER (WHERE resultado = 'WARNING') AS warning,
       count(*) FILTER (WHERE resultado = 'FAIL') AS fail,
       round(100.0 * sum(w * v) / sum(w), 1) AS puntaje
FROM (SELECT dimension, resultado,
             CASE severidad WHEN 'CRITICA' THEN 4 WHEN 'ALTA' THEN 3 WHEN 'MEDIA' THEN 2 ELSE 1 END AS w,
             CASE resultado WHEN 'PASS' THEN 1 WHEN 'WARNING' THEN 0.5 ELSE 0 END AS v
      FROM qg) s
GROUP BY ROLLUP (dimension);

\pset footer off
\echo '== Pruebas de calidad (G6)'
SELECT test_id, categoria, regla, esperado, obtenido, severidad, resultado FROM qg
ORDER BY CASE resultado WHEN 'FAIL' THEN 0 WHEN 'WARNING' THEN 1 ELSE 2 END, test_id;

\echo '== Puntajes por dimensión'
SELECT coalesce(dimension, 'OVERALL') AS dimension, pruebas, pass, warning, fail, puntaje
FROM puntaje ORDER BY dimension NULLS LAST;

\echo '== Veredicto'
SELECT count(*) FILTER (WHERE severidad = 'CRITICA' AND resultado = 'FAIL') AS fails_criticos,
       CASE WHEN count(*) FILTER (WHERE severidad = 'CRITICA' AND resultado = 'FAIL') = 0
            THEN 'QUALITY_GATE = PASS' ELSE 'QUALITY_GATE = FAIL' END AS quality_gate
FROM qg;

-- sql/tests/quality_gate_defectos.sql define qg_sin_csv para no sobrescribir la evidencia real
\if :{?qg_sin_csv}
\else
\copy (SELECT test_id, categoria, dimension, regla, tabla, esperado, obtenido, severidad, resultado, detalle FROM qg ORDER BY test_id) TO 'evidence/g6_quality_results.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo 'Detalle guardado en evidence/g6_quality_results.csv'
\endif
