# B4 · Equivalencia SQL, Power BI y página

El criterio de B4 es que los indicadores de la página den igual que en Power BI y en SQL.
Comparamos los 13, con los mismos escenarios de B2 y B3:

- **Escenario A:** todo el periodo y todo el banco.
- **Escenario B:** agosto de 2026 y producto AHORROS. Los saldos solo filtran el producto,
  porque son una foto al corte.

**Cómo lo hicimos**

- **SQL:** los valores oficiales de `b2_05_kpi_referencia.sql` (catálogo de B2).
- **Power BI:** lo que dio `equivalencia_b3.dax` en B3.
- **Página:** `pruebas/validar_pagina.py` abre cada página con el filtro puesto en la dirección
  (por ejemplo `estadisticas.html#transacciones?mes=2026-08&producto=AHORROS`), espera a que
  termine de cargar y lee la cifra que queda en cada tarjeta. Revisa dos cosas: que el dato sea
  igual al oficial y que se vea con el formato correcto (miles con punto, decimales con coma y la
  moneda). La salida está en `salidas/validacion_pagina.txt`.

La prueba de la página la corrimos sobre la copia de la base que reconstruimos con
`g8_reconstruir_todo.sql`, la misma de B2, cuyo esquema `bi` dio la misma huella md5 que el del
computador de Juan Diego (`4149f55080d618b5aed9a6ea3414eef5`).

| KPI | A: SQL | A: Power BI | A: Página | B: SQL | B: Power BI | B: Página | ¿Igual? |
|---|---|---|---|---|---|---|---|
| K01 Transacciones contabilizadas | 1.000.000 | 1.000.000 | 1.000.000 | 11.834 | 11.834 | 11.834 | Sí |
| K02 Monto movido COP | 1.767.796.946.066,07 | 1.767.796.946.066,07 | 1.767.796.946.066,07 | 12.643.399.220,02 | 12.643.399.220,02 | 12.643.399.220,02 | Sí |
| K03 Monto movido USD | 1.768.114,58 | 1.768.114,58 | 1.768.114,58 | 18.151,07 | 18.151,07 | 18.151,07 | Sí |
| K04 Ticket promedio COP | 1.775.276,18 | 1.775.276,18 | 1.775.276,18 | 1.077.317,59 | 1.077.317,59 | 1.077.317,59 | Sí |
| K05 Tasa de rechazo % | 2,35 | 2,35 | 2,35 | 6,94 | 6,94 | 6,94 | Sí |
| K06 Reversos | 9.530 | 9.530 | 9.530 | 135 | 135 | 135 | Sí |
| K07 Clientes con movimientos | 9.070 | 9.070 | 9.070 | 3.947 | 3.947 | 3.947 | Sí |
| K08 Cuentas activas | 43.557 | 43.557 | 43.557 | 17.851 | 17.851 | 17.851 | Sí |
| K09 Saldo total COP | 1.004.471.074.520,73 | 1.004.471.074.520,73 | 1.004.471.074.520,73 | 126.700.742.889,73 | 126.700.742.889,73 | 126.700.742.889,73 | Sí |
| K10 Saldo total USD | 1.051.931,27 | 1.051.931,27 | 1.051.931,27 | 253.402,31 | 253.402,31 | 253.402,31 | Sí |
| K11 Cuentas en sobregiro | 1.000 | 1.000 | 1.000 | 0 | 0 | 0 | Sí |
| K12 Puntaje del quality gate | 99,6 | 99,6 | 99,6 | 99,6 | 99,6 | 99,6 | Sí |
| K13 Controles en PASS | 6 | 6 | 6 | 6 | 6 | 6 | Sí |

**Resultado:** 13 de 13 iguales en los dos escenarios, en las tres herramientas.

## Lo que revisamos además

- **Un tercer escenario (C: diciembre de 2025 y oficinas de Caldas)**, para no quedarnos solo
  con los dos de siempre. Lo comparamos entre las funciones del aplicativo y el cálculo directo
  en SQL en `b4_02_validar_estadisticas.sql`: 13 de 13 iguales (por ejemplo, 1.130
  transacciones, 2,16 % de rechazo y 16 cuentas en sobregiro).
- **Las gráficas cuadran con sus indicadores.** En los tres escenarios, la suma de cada serie da
  lo mismo que el indicador del que sale: monto por mes y por tipo = K02; transacciones por tipo,
  por hora y por día = K01; rechazos por motivo = transacciones rechazadas; cuentas por estado y
  por producto = cuentas al corte; saldo por departamento = K09. Son 27 de 27.
- **Permisos:** `banco_bi` puede ejecutar las funciones, nadie más (se quitaron de PUBLIC), y
  `banco_bi` sigue sin poder escribir en `bi`.
- **Filtros con valores inventados:** el servidor responde 422 si alguien pone en la dirección
  un mes, producto o departamento que no existe, y las consultas van con parámetros.

## Algo que corregimos de paso

En Power BI los días de la semana salían en orden alfabético (pendiente de B3). En la página los
ordenamos por `dia_semana`, de lunes a domingo. En el `.pbix` lo corregimos cuando le apliquemos
la paleta.
