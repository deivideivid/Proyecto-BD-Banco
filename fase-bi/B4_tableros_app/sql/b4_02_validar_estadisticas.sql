-- =====================================================================
-- B4 · Validación de las funciones de Estadísticas
-- 1) Los 13 indicadores que entrega el aplicativo, comparados con el cálculo
--    directo en SQL (las mismas consultas de b2_05_kpi_referencia.sql),
--    en tres escenarios:
--      A: todo el periodo y todo el banco
--      B: agosto de 2026 y producto AHORROS (el mismo de B2 y B3)
--      C: diciembre de 2025 y oficinas de Caldas (uno nuevo, para no quedarnos solo con B)
-- 2) Cada gráfica suma lo mismo que su indicador (no se pierde ni se duplica nada).
-- 3) Permisos: solo banco_bi puede ejecutar las funciones.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\pset footer off

CREATE TEMP TABLE escenario (esc text, mes text, producto text, departamento text);
INSERT INTO escenario VALUES ('A', NULL, NULL, NULL), ('B', '2026-08', 'AHORROS', NULL), ('C', '2025-12', NULL, 'Caldas');

-- Cálculo directo, sin pasar por las funciones del aplicativo
CREATE TEMP TABLE referencia AS
WITH tx AS (
  SELECT e.esc, f.* FROM escenario e
  JOIN bi.fact_transaccion f ON true
  JOIN bi.dim_fecha d ON d.fecha_key = f.fecha_key
  JOIN bi.dim_oficina o ON o.oficina_key = f.oficina_key
  WHERE (e.mes IS NULL OR d.anio_mes = e.mes) AND (e.producto IS NULL OR f.producto_key = e.producto)
    AND (e.departamento IS NULL OR o.departamento = e.departamento)
), sa AS (
  SELECT e.esc, s.* FROM escenario e
  JOIN bi.fact_saldo_cuenta s ON true
  JOIN bi.dim_oficina o ON o.oficina_key = s.oficina_key
  WHERE (e.producto IS NULL OR s.producto_key = e.producto) AND (e.departamento IS NULL OR o.departamento = e.departamento)
)
SELECT esc, 'K01' id, count(*)::numeric v FROM tx WHERE estado = 'POSTED' GROUP BY esc
UNION ALL SELECT esc, 'K02', sum(monto) FROM tx WHERE estado = 'POSTED' AND moneda = 'COP' GROUP BY esc
UNION ALL SELECT e.esc, 'K03', coalesce((SELECT sum(monto) FROM tx WHERE tx.esc = e.esc AND estado = 'POSTED' AND moneda = 'USD'), 0) FROM escenario e
UNION ALL SELECT esc, 'K04', round(avg(monto), 2) FROM tx WHERE estado = 'POSTED' AND moneda = 'COP' GROUP BY esc
UNION ALL SELECT esc, 'K05', round(100.0 * count(*) FILTER (WHERE estado = 'REJECTED') / count(*) FILTER (WHERE estado IN ('POSTED','REJECTED')), 2) FROM tx GROUP BY esc
UNION ALL SELECT e.esc, 'K06', (SELECT count(*) FROM tx WHERE tx.esc = e.esc AND estado = 'POSTED' AND tipo_key = 'REVERSO') FROM escenario e
UNION ALL SELECT esc, 'K07', count(DISTINCT cliente_key) FROM tx WHERE estado = 'POSTED' GROUP BY esc
UNION ALL SELECT e.esc, 'K08', (SELECT count(*) FROM sa WHERE sa.esc = e.esc AND estado_cuenta = 'ACTIVA') FROM escenario e
UNION ALL SELECT esc, 'K09', sum(saldo_contable) FROM sa WHERE moneda = 'COP' GROUP BY esc
UNION ALL SELECT e.esc, 'K10', coalesce((SELECT sum(saldo_contable) FROM sa WHERE sa.esc = e.esc AND moneda = 'USD'), 0) FROM escenario e
UNION ALL SELECT e.esc, 'K11', (SELECT count(*) FROM sa WHERE sa.esc = e.esc AND en_sobregiro) FROM escenario e
UNION ALL SELECT esc, 'K12', (SELECT puntaje FROM bi.v_calidad_puntaje WHERE dimension = 'OVERALL') FROM escenario
UNION ALL SELECT esc, 'K13', (SELECT count(*) FROM bi.fact_control WHERE resultado = 'PASS') FROM escenario;

-- Lo que entrega el aplicativo
CREATE TEMP TABLE aplicativo AS
SELECT e.esc, i.id, i.valor v FROM escenario e, bi.fn_indicadores(e.mes, e.producto, e.departamento) i;

CREATE TEMP TABLE resultado (prueba text, detalle text, esperado numeric, obtenido numeric, ok boolean);

INSERT INTO resultado
SELECT 'Indicador ' || r.esc || ' ' || r.id, (SELECT indicador FROM bi.fn_indicadores() x WHERE x.id = r.id LIMIT 1),
       r.v, a.v, r.v IS NOT DISTINCT FROM a.v
FROM referencia r LEFT JOIN aplicativo a USING (esc, id);

-- Cada gráfica cuadra con su indicador
INSERT INTO resultado
SELECT 'Gráfica ' || e.esc || ' ' || g.serie, 'suma de la serie = ' || g.ind,
       (SELECT v FROM aplicativo a WHERE a.esc = e.esc AND a.id = g.ind),
       (SELECT coalesce(sum(valor), 0) FROM bi.fn_serie(g.serie, e.mes, e.producto, e.departamento)),
       (SELECT v FROM aplicativo a WHERE a.esc = e.esc AND a.id = g.ind)
         = (SELECT coalesce(sum(valor), 0) FROM bi.fn_serie(g.serie, e.mes, e.producto, e.departamento))
FROM escenario e
CROSS JOIN (VALUES ('monto_mes', 'K02'), ('tx_tipo', 'K01'), ('tx_hora', 'K01'), ('tx_dia', 'K01'),
                   ('rechazo_motivo', 'TXR'), ('monto_tipo', 'K02'), ('cuentas_estado', 'CTA'),
                   ('cuentas_producto', 'CTA'), ('saldo_departamento', 'K09')) g(serie, ind);

-- Permisos
INSERT INTO resultado
SELECT 'Permiso ' || p.nombre, p.detalle, 1, CASE WHEN p.cumple THEN 1 ELSE 0 END, p.cumple
FROM (VALUES
  ('banco_bi ejecuta', 'banco_bi puede ejecutar bi.fn_indicadores',
     has_function_privilege('banco_bi', 'bi.fn_indicadores(text,text,text,integer)', 'EXECUTE')),
  ('PUBLIC no ejecuta', 'ningún otro usuario puede ejecutar las funciones de Estadísticas',
     NOT EXISTS (SELECT 1 FROM pg_proc pr, aclexplode(coalesce(pr.proacl, acldefault('f', pr.proowner))) a
                 WHERE pr.pronamespace = 'bi'::regnamespace
                   AND pr.proname IN ('fn_tx_filtradas','fn_saldos_filtrados','fn_indicadores','fn_serie','fn_top_clientes','fn_opciones_filtro')
                   AND a.grantee = 0)),
  ('banco_bi solo lee', 'banco_bi no puede escribir en bi.fact_transaccion',
     NOT has_table_privilege('banco_bi', 'bi.fact_transaccion', 'INSERT,UPDATE,DELETE'))
) p(nombre, detalle, cumple);

\echo '== Detalle'
SELECT prueba, detalle, esperado, obtenido, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS resultado FROM resultado ORDER BY prueba;

\echo '== Resumen B4'
SELECT count(*) FILTER (WHERE ok) AS pass, count(*) FILTER (WHERE NOT ok OR ok IS NULL) AS fail, count(*) AS total,
       CASE WHEN bool_and(coalesce(ok, false)) THEN 'B4 ESTADÍSTICAS = PASS' ELSE 'B4 ESTADÍSTICAS = FAIL' END AS veredicto
FROM resultado;
