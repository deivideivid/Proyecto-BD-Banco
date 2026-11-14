# B3 · Equivalencia SQL contra Power BI

La guía de la fase pide que mínimo 7 indicadores den igual en SQL y en Power BI con los mismos
filtros. Comparamos los 13.

**Cómo lo hicimos:** en la vista de consultas DAX de Power BI corrimos
`powerbi/equivalencia_b3.dax`, que calcula cada medida en los dos escenarios. Lo comparamos con
lo que dio `B2_modelo_estrella/sql/b2_05_kpi_referencia.sql` en la base. Los porcentajes están
multiplicados por 100 y todo va redondeado a 2 decimales.

- **Escenario A:** todo el periodo y todo el banco.
- **Escenario B:** agosto de 2026 y producto AHORROS. Los indicadores de saldo solo filtran el
  producto, porque son una foto al corte.

| KPI | A: SQL | A: Power BI | B: SQL | B: Power BI | ¿Igual? |
|---|---|---|---|---|---|
| K01 Transacciones contabilizadas | 1.000.000 | 1.000.000 | 11.834 | 11.834 | Sí |
| K02 Monto movido COP | 1.767.796.946.066,07 | 1.767.796.946.066,07 | 12.643.399.220,02 | 12.643.399.220,02 | Sí |
| K03 Monto movido USD | 1.768.114,58 | 1.768.114,58 | 18.151,07 | 18.151,07 | Sí |
| K04 Ticket promedio COP | 1.775.276,18 | 1.775.276,18 | 1.077.317,59 | 1.077.317,59 | Sí |
| K05 Tasa de rechazo % | 2,35 | 2,35 | 6,94 | 6,94 | Sí |
| K06 Reversos | 9.530 | 9.530 | 135 | 135 | Sí |
| K07 Clientes con movimientos | 9.070 | 9.070 | 3.947 | 3.947 | Sí |
| K08 Cuentas activas | 43.557 | 43.557 | 17.851 | 17.851 | Sí |
| K09 Saldo total COP | 1.004.471.074.520,73 | 1.004.471.074.520,73 | 126.700.742.889,73 | 126.700.742.889,73 | Sí |
| K10 Saldo total USD | 1.051.931,27 | 1.051.931,27 | 253.402,31 | 253.402,31 | Sí |
| K11 Cuentas en sobregiro | 1.000 | 1.000 | 0 | 0 | Sí |
| K12 Puntaje del quality gate | 99,6 | 99,6 | 99,6 | 99,6 | Sí |
| K13 Controles en PASS | 6 | 6 | 6 | 6 | Sí |

**Resultado:** 13 de 13 iguales en los dos escenarios.

En la página Resumen también vimos a simple vista los mismos valores sin filtros: 1 millón de
transacciones, 1,77 billones movidos en pesos, 9.070 clientes con movimientos, 44 mil cuentas
activas, 1,00 billón de saldo en pesos y 2,35 % de rechazo.
