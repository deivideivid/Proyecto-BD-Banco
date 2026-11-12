# B2 · Catálogo de indicadores

Estos son los indicadores que van a mostrar Power BI (B3) y la sección Estadísticas del
aplicativo (B4). Los calculamos primero en SQL (`sql/b2_05_kpi_referencia.sql`) y esos valores
son los oficiales: Power BI y el aplicativo tienen que dar exactamente lo mismo.

**Escenarios de prueba**

- **A:** todo el periodo y todo el banco.
- **B:** agosto de 2026 y producto AHORROS. Los indicadores al corte (K08 a K11) solo filtran el
  producto, porque son una foto.

| ID | Indicador | Fórmula | Tabla | A | B |
|---|---|---|---|---|---|
| K01 | Transacciones contabilizadas | Conteo con estado POSTED | fact_transaccion | 1.000.000 | 11.834 |
| K02 | Monto movido COP | Suma de monto, POSTED, moneda COP | fact_transaccion | 1.767.796.946.066,07 | 12.643.399.220,02 |
| K03 | Monto movido USD | Suma de monto, POSTED, moneda USD | fact_transaccion | 1.768.114,58 | 18.151,07 |
| K04 | Ticket promedio COP | Promedio de monto, POSTED, COP | fact_transaccion | 1.775.276,18 | 1.077.317,59 |
| K05 | Tasa de rechazo % | Rechazadas / (contabilizadas + rechazadas) × 100 | fact_transaccion | 2,35 | 6,94 |
| K06 | Reversos | Conteo POSTED de tipo REVERSO | fact_transaccion | 9.530 | 135 |
| K07 | Clientes con movimientos | Clientes distintos con al menos una POSTED (por titular principal de la cuenta) | fact_transaccion | 9.070 | 3.947 |
| K08 | Cuentas activas | Cuentas con estado ACTIVA al corte | fact_saldo_cuenta | 43.557 | 17.851 |
| K09 | Saldo total COP | Suma de saldo contable al corte, COP | fact_saldo_cuenta | 1.004.471.074.520,73 | 126.700.742.889,73 |
| K10 | Saldo total USD | Suma de saldo contable al corte, USD | fact_saldo_cuenta | 1.051.931,27 | 253.402,31 |
| K11 | Cuentas en sobregiro | Cuentas con saldo contable negativo al corte | fact_saldo_cuenta | 1.000 | 0 |
| K12 | Puntaje del quality gate | Fórmula de G6 con peso por severidad | calidad_prueba | 99,6 | 99,6 |
| K13 | Controles en PASS | Controles de cuadre y calidad que pasan (de 6) | fact_control | 6 | 6 |

Algunas cosas que notamos:

- El ticket promedio COP (K04) da 1.775.276, el mismo promedio que medimos en el perfil de
  datos de G4. Es una buena señal de que el modelo no perdió ni duplicó nada.
- En el escenario B la tasa de rechazo (6,94 %) es casi el triple de la general (2,35 %). Al
  revisarlo vimos que en agosto de 2026, en ahorros, el motivo más común fue "cuenta bloqueada:
  no puede originar débitos" (464 de 882 rechazos), seguido de fondos insuficientes (396). Lo
  vamos a mostrar en la página de Transacciones.
- Las 1.000 cuentas en sobregiro (K11) son todas corrientes: en ahorros (B) da 0, porque ese
  producto no permite sobregiro.
