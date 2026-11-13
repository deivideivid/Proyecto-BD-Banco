-- =====================================================================
-- B4 · Funciones de la sección Estadísticas del aplicativo
-- Las pantallas no escriben SQL: le piden los datos a estas funciones.
-- Así los indicadores se calculan en un solo lugar, con las mismas reglas
-- de b2_05_kpi_referencia.sql y de las medidas de Power BI (B3).
--
-- Filtros (NULL = sin filtro), los mismos de los tableros de Power BI:
--   p_mes          anio_mes de dim_fecha, por ejemplo '2026-08'
--   p_producto     producto_key, por ejemplo 'AHORROS'
--   p_departamento departamento de la oficina
--   p_oficina      oficina_key (lo va a usar el Supervisor en B5: solo ve su oficina)
-- Igual que en Power BI, los saldos (K08 a K11) son una foto al corte y no
-- se filtran por mes, y K12 y K13 son de toda la base.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';

-- Transacciones con los filtros aplicados (función SQL simple: PostgreSQL la
-- "despliega" dentro de la consulta que la llama y usa los índices).
CREATE OR REPLACE FUNCTION bi.fn_tx_filtradas(
    p_mes text DEFAULT NULL, p_producto text DEFAULT NULL,
    p_departamento text DEFAULT NULL, p_oficina integer DEFAULT NULL)
RETURNS SETOF bi.fact_transaccion
LANGUAGE sql STABLE AS $$
  SELECT f.*
  FROM bi.fact_transaccion f
  WHERE (p_mes IS NULL OR f.fecha_key IN (SELECT d.fecha_key FROM bi.dim_fecha d WHERE d.anio_mes = p_mes))
    AND (p_producto IS NULL OR f.producto_key = p_producto)
    AND (p_departamento IS NULL OR f.oficina_key IN (SELECT o.oficina_key FROM bi.dim_oficina o WHERE o.departamento = p_departamento))
    AND (p_oficina IS NULL OR f.oficina_key = p_oficina)
$$;

-- Saldos al corte con los filtros (el mes no aplica: es una foto).
CREATE OR REPLACE FUNCTION bi.fn_saldos_filtrados(
    p_producto text DEFAULT NULL, p_departamento text DEFAULT NULL, p_oficina integer DEFAULT NULL)
RETURNS SETOF bi.fact_saldo_cuenta
LANGUAGE sql STABLE AS $$
  SELECT s.*
  FROM bi.fact_saldo_cuenta s
  WHERE (p_producto IS NULL OR s.producto_key = p_producto)
    AND (p_departamento IS NULL OR s.oficina_key IN (SELECT o.oficina_key FROM bi.dim_oficina o WHERE o.departamento = p_departamento))
    AND (p_oficina IS NULL OR s.oficina_key = p_oficina)
$$;

-- Los 13 indicadores del catálogo, más los dos de apoyo de Power BI.
CREATE OR REPLACE FUNCTION bi.fn_indicadores(
    p_mes text DEFAULT NULL, p_producto text DEFAULT NULL,
    p_departamento text DEFAULT NULL, p_oficina integer DEFAULT NULL)
RETURNS TABLE (id text, indicador text, valor numeric)
LANGUAGE sql STABLE AS $$
  WITH t AS (
    SELECT count(*) FILTER (WHERE estado = 'POSTED')                                  AS k01,
           coalesce(sum(monto) FILTER (WHERE estado = 'POSTED' AND moneda = 'COP'), 0) AS k02,
           coalesce(sum(monto) FILTER (WHERE estado = 'POSTED' AND moneda = 'USD'), 0) AS k03,
           round(avg(monto) FILTER (WHERE estado = 'POSTED' AND moneda = 'COP'), 2)   AS k04,
           count(*) FILTER (WHERE estado = 'REJECTED')                                AS rech,
           count(*) FILTER (WHERE estado = 'POSTED' AND tipo_key = 'REVERSO')         AS k06,
           count(DISTINCT cliente_key) FILTER (WHERE estado = 'POSTED')               AS k07
    FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina)
  ), s AS (
    SELECT count(*)                                                            AS cuentas,
           count(*) FILTER (WHERE estado_cuenta = 'ACTIVA')                    AS k08,
           coalesce(sum(saldo_contable) FILTER (WHERE moneda = 'COP'), 0)      AS k09,
           coalesce(sum(saldo_contable) FILTER (WHERE moneda = 'USD'), 0)      AS k10,
           count(*) FILTER (WHERE en_sobregiro)                                AS k11
    FROM bi.fn_saldos_filtrados(p_producto, p_departamento, p_oficina)
  )
  SELECT v.id, v.indicador, v.valor
  FROM t, s, LATERAL (VALUES
    ('K01', 'Transacciones contabilizadas', t.k01::numeric),
    ('K02', 'Monto movido COP', t.k02),
    ('K03', 'Monto movido USD', t.k03),
    ('K04', 'Ticket promedio COP', t.k04),
    ('K05', 'Tasa de rechazo %', round(100.0 * t.rech / nullif(t.k01 + t.rech, 0), 2)),
    ('K06', 'Reversos', t.k06::numeric),
    ('K07', 'Clientes con movimientos', t.k07::numeric),
    ('K08', 'Cuentas activas', s.k08::numeric),
    ('K09', 'Saldo total COP', s.k09),
    ('K10', 'Saldo total USD', s.k10),
    ('K11', 'Cuentas en sobregiro', s.k11::numeric),
    ('K12', 'Puntaje del quality gate', (SELECT p.puntaje FROM bi.v_calidad_puntaje p WHERE p.dimension = 'OVERALL')),
    ('K13', 'Controles en PASS', (SELECT count(*) FROM bi.fact_control c WHERE c.resultado = 'PASS')::numeric),
    ('TXR', 'Transacciones rechazadas', t.rech::numeric),
    ('CTA', 'Cuentas al corte', s.cuentas::numeric)
  ) AS v(id, indicador, valor)
$$;

-- Series de las gráficas. Cada una devuelve (orden, etiqueta, valor) y es la
-- misma combinación de campo y medida que la gráfica de Power BI.
CREATE OR REPLACE FUNCTION bi.fn_serie(
    p_serie text, p_mes text DEFAULT NULL, p_producto text DEFAULT NULL,
    p_departamento text DEFAULT NULL, p_oficina integer DEFAULT NULL)
RETURNS TABLE (orden integer, etiqueta text, valor numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
  CASE p_serie
  WHEN 'monto_mes' THEN          -- Resumen: monto movido COP por mes
    RETURN QUERY SELECT 0, d.anio_mes::text, sum(f.monto)
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f JOIN bi.dim_fecha d USING (fecha_key)
      WHERE f.estado = 'POSTED' AND f.moneda = 'COP' GROUP BY d.anio_mes ORDER BY d.anio_mes;
  WHEN 'tx_tipo' THEN            -- Resumen: transacciones por tipo
    RETURN QUERY SELECT 0, t.tipo::text, count(*)::numeric
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f JOIN bi.dim_tipo_transaccion t USING (tipo_key)
      WHERE f.estado = 'POSTED' GROUP BY t.tipo ORDER BY 3 DESC, 2;
  WHEN 'tx_hora' THEN            -- Transacciones: por hora del día
    RETURN QUERY SELECT f.hora::integer, lpad(f.hora::text, 2, '0') || ':00', count(*)::numeric
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f
      WHERE f.estado = 'POSTED' GROUP BY f.hora ORDER BY f.hora;
  WHEN 'tx_dia' THEN             -- Transacciones: por día de la semana (en orden de calendario)
    RETURN QUERY SELECT d.dia_semana::integer, d.nombre_dia::text, count(*)::numeric
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f JOIN bi.dim_fecha d USING (fecha_key)
      WHERE f.estado = 'POSTED' GROUP BY d.dia_semana, d.nombre_dia ORDER BY d.dia_semana;
  WHEN 'rechazo_motivo' THEN     -- Transacciones: rechazos por motivo
    RETURN QUERY SELECT 0, coalesce(f.motivo_rechazo, 'Sin motivo')::text, count(*)::numeric
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f
      WHERE f.estado = 'REJECTED' GROUP BY 2 ORDER BY 3 DESC, 2;
  WHEN 'monto_tipo' THEN         -- Transacciones: monto movido COP por tipo
    RETURN QUERY SELECT 0, t.tipo::text, sum(f.monto)
      FROM bi.fn_tx_filtradas(p_mes, p_producto, p_departamento, p_oficina) f JOIN bi.dim_tipo_transaccion t USING (tipo_key)
      WHERE f.estado = 'POSTED' AND f.moneda = 'COP' GROUP BY t.tipo ORDER BY 3 DESC, 2;
  WHEN 'cuentas_estado' THEN     -- Clientes y cuentas: cuentas por estado (al corte)
    RETURN QUERY SELECT 0, s.estado_cuenta::text, count(*)::numeric
      FROM bi.fn_saldos_filtrados(p_producto, p_departamento, p_oficina) s GROUP BY 2 ORDER BY 3 DESC, 2;
  WHEN 'cuentas_producto' THEN   -- Clientes y cuentas: cuentas por producto
    RETURN QUERY SELECT 0, p.producto::text, count(*)::numeric
      FROM bi.fn_saldos_filtrados(p_producto, p_departamento, p_oficina) s JOIN bi.dim_producto p USING (producto_key)
      GROUP BY 2 ORDER BY 3 DESC, 2;
  WHEN 'saldo_departamento' THEN -- Clientes y cuentas: saldo COP por departamento de la oficina
    RETURN QUERY SELECT 0, o.departamento::text, sum(s.saldo_contable)
      FROM bi.fn_saldos_filtrados(p_producto, p_departamento, p_oficina) s JOIN bi.dim_oficina o USING (oficina_key)
      WHERE s.moneda = 'COP' GROUP BY 2 ORDER BY 3 DESC, 2;
  ELSE
    RAISE EXCEPTION 'Serie desconocida: %', p_serie USING ERRCODE = '22023';
  END CASE;
END $$;

-- Clientes con más saldo en pesos (tabla de la página Clientes y cuentas).
CREATE OR REPLACE FUNCTION bi.fn_top_clientes(
    p_producto text DEFAULT NULL, p_departamento text DEFAULT NULL,
    p_oficina integer DEFAULT NULL, p_limite integer DEFAULT 10)
RETURNS TABLE (cliente text, tipo_cliente text, departamento text, cuentas bigint, saldo_cop numeric)
LANGUAGE sql STABLE AS $$
  SELECT c.cliente::text, c.tipo_cliente::text, c.departamento::text,
         count(*), coalesce(sum(s.saldo_contable) FILTER (WHERE s.moneda = 'COP'), 0)
  FROM bi.fn_saldos_filtrados(p_producto, p_departamento, p_oficina) s
  JOIN bi.dim_cliente c USING (cliente_key)
  GROUP BY c.cliente_key, c.cliente, c.tipo_cliente, c.departamento
  ORDER BY 5 DESC, 1
  LIMIT least(greatest(p_limite, 1), 50)
$$;

-- Opciones de los filtros (lo que sale en las listas desplegables).
CREATE OR REPLACE FUNCTION bi.fn_opciones_filtro()
RETURNS TABLE (filtro text, valor text, etiqueta text)
LANGUAGE sql STABLE AS $$
  SELECT 'mes', anio_mes::text, anio_mes::text FROM (SELECT DISTINCT anio_mes FROM bi.dim_fecha d
         WHERE EXISTS (SELECT 1 FROM bi.fact_transaccion f WHERE f.fecha_key = d.fecha_key)) m
  UNION ALL
  SELECT 'producto', producto_key::text, producto::text FROM bi.dim_producto
  UNION ALL
  SELECT DISTINCT 'departamento', departamento::text, departamento::text FROM bi.dim_oficina
  ORDER BY 1, 2
$$;

-- Permisos: solo el rol de lectura del modelo estrella (banco_bi) puede usarlas.
REVOKE ALL ON FUNCTION bi.fn_tx_filtradas(text, text, text, integer),
               bi.fn_saldos_filtrados(text, text, integer),
               bi.fn_indicadores(text, text, text, integer),
               bi.fn_serie(text, text, text, text, integer),
               bi.fn_top_clientes(text, text, integer, integer),
               bi.fn_opciones_filtro() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION bi.fn_tx_filtradas(text, text, text, integer),
               bi.fn_saldos_filtrados(text, text, integer),
               bi.fn_indicadores(text, text, text, integer),
               bi.fn_serie(text, text, text, text, integer),
               bi.fn_top_clientes(text, text, integer, integer),
               bi.fn_opciones_filtro() TO banco_bi;

\echo 'Funciones de Estadísticas creadas en el esquema bi.'
