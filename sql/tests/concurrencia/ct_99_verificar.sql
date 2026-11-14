-- =====================================================================
-- Pruebas de concurrencia · Verificación del resultado (después de CT-1 a CT-4)
-- CT-0 es la línea base: toda la contabilidad de las cuentas de prueba cuadra.
-- =====================================================================
\set QUIET on
WITH ctx AS (SELECT clave, valor, llave FROM public.ct_ctx),
c AS (SELECT (SELECT valor FROM ctx WHERE clave='c1') c1, (SELECT valor FROM ctx WHERE clave='c2') c2,
             (SELECT valor FROM ctx WHERE clave='c3') c3, (SELECT valor FROM ctx WHERE clave='c4') c4,
             (SELECT valor FROM ctx WHERE clave='tx_a_reversar') tx,
             (SELECT llave FROM ctx WHERE clave='llave_ct3') k3),
pruebas (orden, prueba, descripcion, esperado, obtenido) AS (
  SELECT 1, 'CT-1', 'Doble retiro simultáneo: solo pasa uno; saldo final 20.000',
         '1 retiro · saldo 20000.00',
         (SELECT count(*) FROM fin.transaccion_financiera WHERE cuenta_origen_id = c.c1 AND tipo_codigo = 'RETIRO')
         || ' retiro · saldo ' || (SELECT saldo_contable FROM core.cuenta WHERE cuenta_id = c.c1)
  FROM c
  UNION ALL
  SELECT 2, 'CT-2', 'Transferencias cruzadas sin interbloqueo; c2 = 450.000 y c3 = 550.000',
         '2 transferencias · 450000.00 / 550000.00',
         (SELECT count(*) FROM fin.transaccion_financiera WHERE tipo_codigo = 'TRANSFERENCIA'
            AND (cuenta_origen_id, cuenta_destino_id) IN ((c.c2, c.c3), (c.c3, c.c2)))
         || ' transferencias · ' || (SELECT saldo_contable FROM core.cuenta WHERE cuenta_id = c.c2)
         || ' / ' || (SELECT saldo_contable FROM core.cuenta WHERE cuenta_id = c.c3)
  FROM c
  UNION ALL
  SELECT 3, 'CT-3', 'Misma solicitud simultánea (misma clave): un solo movimiento',
         '1 transacción con la clave K',
         (SELECT count(*) FROM fin.transaccion_financiera WHERE idempotency_key = c.k3) || ' transacción con la clave K'
  FROM c
  UNION ALL
  SELECT 4, 'CT-4', 'Doble reverso simultáneo: solo queda uno',
         '1 reverso de la transacción',
         (SELECT count(*) FROM fin.transaccion_financiera WHERE transaccion_reversada_id = c.tx) || ' reverso de la transacción'
  FROM c
  UNION ALL
  SELECT 0, 'CT-0', 'Línea base: saldo = ledger y todo cuadra en las cuentas de prueba',
         '0 diferencias · 0 descuadres',
         (SELECT count(*) FROM core.v_saldo_vs_ledger WHERE diferencia <> 0 AND cuenta_id IN (c.c1, c.c2, c.c3, c.c4))
         || ' diferencias · '
         || (SELECT count(*) FROM fin.v_balance_transaccion WHERE NOT cuadrada)
         || ' descuadres'
  FROM c
)
SELECT prueba, descripcion, esperado, obtenido,
       CASE WHEN esperado = obtenido THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM pruebas ORDER BY orden;
