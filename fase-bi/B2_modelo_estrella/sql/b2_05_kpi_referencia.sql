-- =====================================================================
-- B2 · Valores oficiales de los indicadores (calculados en SQL sobre bi)
-- Contra estos valores comparamos Power BI (B3) y el aplicativo (B4).
-- Escenario A: todo el periodo y todo el banco.
-- Escenario B: agosto de 2026 (anio_mes = '2026-08') y producto AHORROS.
--   Los indicadores de saldo son una foto al corte: en B solo filtran el producto.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
\pset footer off

CREATE TEMP VIEW tx_a AS SELECT f.* FROM bi.fact_transaccion f;
CREATE TEMP VIEW tx_b AS SELECT f.* FROM bi.fact_transaccion f JOIN bi.dim_fecha d USING (fecha_key)
  WHERE d.anio_mes = '2026-08' AND f.producto_key = 'AHORROS';
CREATE TEMP VIEW sa_a AS SELECT * FROM bi.fact_saldo_cuenta;
CREATE TEMP VIEW sa_b AS SELECT * FROM bi.fact_saldo_cuenta WHERE producto_key = 'AHORROS';

CREATE TEMP TABLE kpi (id text, indicador text, escenario_a numeric, escenario_b numeric);
INSERT INTO kpi VALUES
 ('K01', 'Transacciones contabilizadas',
   (SELECT count(*) FROM tx_a WHERE estado = 'POSTED'), (SELECT count(*) FROM tx_b WHERE estado = 'POSTED')),
 ('K02', 'Monto movido COP',
   (SELECT sum(monto) FROM tx_a WHERE estado = 'POSTED' AND moneda = 'COP'), (SELECT sum(monto) FROM tx_b WHERE estado = 'POSTED' AND moneda = 'COP')),
 ('K03', 'Monto movido USD',
   (SELECT coalesce(sum(monto), 0) FROM tx_a WHERE estado = 'POSTED' AND moneda = 'USD'), (SELECT coalesce(sum(monto), 0) FROM tx_b WHERE estado = 'POSTED' AND moneda = 'USD')),
 ('K04', 'Ticket promedio COP',
   (SELECT round(avg(monto), 2) FROM tx_a WHERE estado = 'POSTED' AND moneda = 'COP'), (SELECT round(avg(monto), 2) FROM tx_b WHERE estado = 'POSTED' AND moneda = 'COP')),
 ('K05', 'Tasa de rechazo %',
   (SELECT round(100.0 * count(*) FILTER (WHERE estado = 'REJECTED') / count(*) FILTER (WHERE estado IN ('POSTED','REJECTED')), 2) FROM tx_a),
   (SELECT round(100.0 * count(*) FILTER (WHERE estado = 'REJECTED') / count(*) FILTER (WHERE estado IN ('POSTED','REJECTED')), 2) FROM tx_b)),
 ('K06', 'Reversos',
   (SELECT count(*) FROM tx_a WHERE estado = 'POSTED' AND tipo_key = 'REVERSO'), (SELECT count(*) FROM tx_b WHERE estado = 'POSTED' AND tipo_key = 'REVERSO')),
 ('K07', 'Clientes con movimientos',
   (SELECT count(DISTINCT cliente_key) FROM tx_a WHERE estado = 'POSTED'), (SELECT count(DISTINCT cliente_key) FROM tx_b WHERE estado = 'POSTED')),
 ('K08', 'Cuentas activas (al corte)',
   (SELECT count(*) FROM sa_a WHERE estado_cuenta = 'ACTIVA'), (SELECT count(*) FROM sa_b WHERE estado_cuenta = 'ACTIVA')),
 ('K09', 'Saldo total COP (al corte)',
   (SELECT sum(saldo_contable) FROM sa_a WHERE moneda = 'COP'), (SELECT sum(saldo_contable) FROM sa_b WHERE moneda = 'COP')),
 ('K10', 'Saldo total USD (al corte)',
   (SELECT coalesce(sum(saldo_contable), 0) FROM sa_a WHERE moneda = 'USD'), (SELECT coalesce(sum(saldo_contable), 0) FROM sa_b WHERE moneda = 'USD')),
 ('K11', 'Cuentas en sobregiro (al corte)',
   (SELECT count(*) FROM sa_a WHERE en_sobregiro), (SELECT count(*) FROM sa_b WHERE en_sobregiro)),
 ('K12', 'Puntaje del quality gate',
   (SELECT puntaje FROM bi.v_calidad_puntaje WHERE dimension = 'OVERALL'), (SELECT puntaje FROM bi.v_calidad_puntaje WHERE dimension = 'OVERALL')),
 ('K13', 'Controles de cuadre y calidad en PASS',
   (SELECT count(*) FROM bi.fact_control WHERE resultado = 'PASS'), (SELECT count(*) FROM bi.fact_control WHERE resultado = 'PASS'));

\echo '== Valores oficiales de los indicadores (A: todo · B: 2026-08 y AHORROS)'
SELECT id, indicador, escenario_a, escenario_b FROM kpi ORDER BY id;
