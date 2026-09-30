# G5 — Resultados de las 30 consultas

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G5 — Consultas SQL** |
| Script | [`sql/19_demo_queries.sql`](../sql/19_demo_queries.sql) |
| Datos | Lotes 1 y 2 cargados: 10.000 clientes · 50.000 cuentas · 1.000.000 transacciones POSTED |
| Ejecución | PostgreSQL 16.13 · 2026-09-30 · las 30 consultas + validaciones en 8.5 s (sin índices secundarios) |
| Resultado | **G5 = PASS**: 30 consultas funcionan · 7 validaciones cruzadas en PASS (ver [final](#validaciones-cruzadas)) |

## Cómo usar este documento

Cada consulta tiene su **objetivo de negocio**, los **conceptos SQL** que evalúa, el **resultado real** y **cómo explicarla**. El laboratorio exige que el equipo pueda explicar el resultado de cada una: se recomienda repartirlas (por ejemplo, 10 por integrante) y ejecutarlas en pgAdmin 4 para practicar.

## Resumen

| ID | Nivel | Consulta | Conceptos SQL | Tiempo | Validación cruzada |
|---|---|---|---|---|---|
| [B01](#b01--clientes-por-tipo-y-estado) | Básica | Clientes por tipo y estado | GROUP BY, COUNT, porcentaje con ventana simple | 6 ms | — |
| [B02](#b02--cuentas-por-producto-y-estado) | Básica | Cuentas por producto y estado | GROUP BY de dos columnas, FILTER | 17 ms | VC5 |
| [B03](#b03--las-10-cuentas-en-pesos-con-mayor-saldo) | Básica | Las 10 cuentas en pesos con mayor saldo | WHERE, ORDER BY … DESC, LIMIT | 16 ms | — |
| [B04](#b04--transacciones-de-agosto-de-2026-por-tipo) | Básica | Transacciones de agosto de 2026 por tipo | filtro por periodo, COUNT, SUM, AVG | 76 ms | VC3 |
| [B05](#b05--clientes-vinculados-por-año) | Básica | Clientes vinculados por año | EXTRACT, GROUP BY, ORDER BY | 2 ms | — |
| [B06](#b06--consignaciones-por-mes-en-2025) | Básica | Consignaciones por mes en 2025 | date_trunc, SUM, AVG | 95 ms | — |
| [B07](#b07--solicitudes-rechazadas-por-motivo) | Básica | Solicitudes rechazadas por motivo | WHERE sobre estado, GROUP BY de texto | 47 ms | — |
| [B08](#b08--cuentas-usando-sobregiro) | Básica | Cuentas usando sobregiro | columnas calculadas, WHERE, ORDER BY sobre expresión | 7 ms | — |
| [B09](#b09--retiros-grandes-del-último-mes) | Básica | Retiros grandes del último mes | BETWEEN, condiciones combinadas | 57 ms | — |
| [B10](#b10--clientes-con-datos-de-contacto-incompletos) | Básica | Clientes con datos de contacto incompletos | IS NULL, COUNT con FILTER | 2 ms | — |
| [I01](#i01--los-10-clientes-con-mayor-saldo-en-pesos) | Intermedia | Los 10 clientes con mayor saldo en pesos | JOIN múltiple, LEFT JOIN a subtipos, COALESCE, GROUP BY, HAVING implícito por ORDER | 84 ms | VC4 |
| [I02](#i02--cuentas-activas-sin-movimientos-en-los-últimos-90-días) | Intermedia | Cuentas activas sin movimientos en los últimos 90 días | NOT EXISTS (anti-join), subconsulta correlacionada | 266 ms | — |
| [I03](#i03--transferencias-regionales-entre-departamentos) | Intermedia | Transferencias regionales entre departamentos | JOIN múltiple con la misma tabla dos veces (alias), filtro de desigualdad | 220 ms | VC7 |
| [I04](#i04--empresas-con-más-de-50-cuentas) | Intermedia | Empresas con más de 50 cuentas | GROUP BY + HAVING | 9 ms | — |
| [I05](#i05--participación-de-cada-producto-en-los-depósitos) | Intermedia | Participación de cada producto en los depósitos | CTE (WITH), porcentaje sobre el total de la moneda | 11 ms | VC1 |
| [I06](#i06--cuentas-con-saldo-por-encima-del-promedio-de-su-producto) | Intermedia | Cuentas con saldo por encima del promedio de su producto | CTE + subconsulta correlacionada en WHERE | 39 ms | — |
| [I07](#i07--flujo-neto-de-dinero-por-departamento-del-cliente-en-2026) | Intermedia | Flujo neto de dinero por departamento del cliente en 2026 | JOIN de 7 tablas, SUM con CASE (créditos − débitos) | 530 ms | — |
| [I08](#i08--usuarios-internos-que-más-transacciones-registraron-en-2026) | Intermedia | Usuarios internos que más transacciones registraron en 2026 | JOIN, GROUP BY, LIMIT | 304 ms | — |
| [I09](#i09--reversos-qué-se-reversa-y-cuánto-tarda) | Intermedia | Reversos: qué se reversa y cuánto tarda | SELF JOIN, diferencia de fechas, AVG | 334 ms | — |
| [I10](#i10--clientes-con-cuentas-en-pesos-y-en-dólares) | Intermedia | Clientes con cuentas en pesos y en dólares | HAVING count(DISTINCT …) | 43 ms | — |
| [A01](#a01--los-3-clientes-con-mayor-saldo-de-cada-departamento) | Avanzada | Los 3 clientes con mayor saldo de cada departamento | función de ventana RANK() OVER (PARTITION BY … ORDER BY …) | 74 ms | — |
| [A02](#a02--percentiles-de-monto-por-tipo-de-transacción) | Avanzada | Percentiles de monto por tipo de transacción | percentile_cont(…) WITHIN GROUP (ORDER BY …) | 896 ms | — |
| [A03](#a03--extracto-con-saldo-acumulado-de-una-cuenta) | Avanzada | Extracto con saldo acumulado de una cuenta | SUM(...) OVER (ORDER BY …) (suma acumulada) | 296 ms | VC2 |
| [A04](#a04--crecimiento-mes-a-mes-del-número-de-transacciones) | Avanzada | Crecimiento mes a mes del número de transacciones | LAG() OVER (ORDER BY …) | 180 ms | VC6 |
| [A05](#a05--cohortes-de-clientes-por-año-de-vinculación) | Avanzada | Cohortes de clientes por año de vinculación | cohorte temporal simple, EXISTS, agregación condicional | 420 ms | — |
| [A06](#a06--anomalías-montos-muy-por-encima-de-lo-normal-para-la-cuenta) | Avanzada | Anomalías: montos muy por encima de lo normal para la cuenta | AVG() y STDDEV() OVER (PARTITION BY cuenta) | 1.083 ms | — |
| [A07](#a07--patrón-de-fraccionamiento-retiros-que-casi-agotan-el-límite-varios-días) | Avanzada | Patrón de fraccionamiento: retiros que casi agotan el límite varios días | CTE encadenadas, funciones de ventana (row_number, lead) para reconstruir el límite | 294 ms | — |
| [A08](#a08--media-móvil-de-7-días-de-transacciones-diarias) | Avanzada | Media móvil de 7 días de transacciones diarias | AVG() OVER (ORDER BY … ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) | 110 ms | — |
| [A09](#a09--concentración-pareto-qué-porcentaje-de-cuentas-mueve-el-80--del-dinero) | Avanzada | Concentración (Pareto): ¿qué porcentaje de cuentas mueve el 80 % del dinero? | SUM() OVER (ORDER BY … ) acumulada, ROW_NUMBER, porcentajes | 568 ms | — |
| [A10](#a10--ráfagas-3-o-más-débitos-de-la-misma-cuenta-en-menos-de-1-hora) | Avanzada | Ráfagas: 3 o más débitos de la misma cuenta en menos de 1 hora | COUNT() OVER (PARTITION BY … ORDER BY … RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW) | 638 ms | — |


## Nivel básica

### B01 · Clientes por tipo y estado

- **Objetivo:** saber cuántos clientes hay de cada tipo y cuántos siguen activos.
- **Tablas:** core.cliente
- **Conceptos SQL:** GROUP BY, COUNT, porcentaje con ventana simple
- **Criterio de validación:** el total debe ser 10.000 y los tipos 8.500 / 1.500.
- **Tiempo:** 6 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT tipo_cliente, estado_cliente, count(*) AS clientes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS porcentaje
FROM core.cliente
GROUP BY tipo_cliente, estado_cliente
ORDER BY tipo_cliente, clientes DESC;
```
</details>

**Resultado:**

```
 tipo_cliente | estado_cliente | clientes | porcentaje 
--------------+----------------+----------+------------
 JURIDICA     | ACTIVO         |     1493 |       14.9
 JURIDICA     | INACTIVO       |        7 |        0.1
 NATURAL      | ACTIVO         |     8400 |       84.0
 NATURAL      | INACTIVO       |      100 |        1.0
```

**Cómo explicarla:** Hay 10.000 clientes: 8.500 naturales y 1.500 jurídicas (85 % / 15 %). Los 107 INACTIVOS son clientes a los que se les cerraron todas sus cuentas. La columna de porcentaje usa `sum(count(*)) OVER ()`: el total general calculado sobre el mismo resultado agrupado.

### B02 · Cuentas por producto y estado

- **Objetivo:** ver la cartera de cuentas por producto y en qué estado está.
- **Tablas:** core.cuenta
- **Conceptos SQL:** GROUP BY de dos columnas, FILTER
- **Criterio de validación:** el total debe ser 50.000 (ver VC5 para el estado).
- **Tiempo:** 17 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT producto_codigo,
       count(*) AS total,
       count(*) FILTER (WHERE estado_cuenta = 'ACTIVA')    AS activas,
       count(*) FILTER (WHERE estado_cuenta = 'BLOQUEADA') AS bloqueadas,
       count(*) FILTER (WHERE estado_cuenta = 'INACTIVA')  AS inactivas,
       count(*) FILTER (WHERE estado_cuenta = 'CERRADA')   AS cerradas
FROM core.cuenta
GROUP BY producto_codigo
ORDER BY total DESC;
```
</details>

**Resultado:**

```
 producto_codigo | total | activas | bloqueadas | inactivas | cerradas 
-----------------+-------+---------+------------+-----------+----------
 AHORROS         | 20547 |   17851 |        823 |       903 |      970
 CORRIENTE       | 16033 |   13985 |        635 |       657 |      756
 EMPRESARIAL     | 10686 |    9354 |        424 |       417 |      491
 NOMINA          |  2734 |    2367 |        107 |       113 |      147
```

**Cómo explicarla:** AHORROS es el producto con más cuentas. `FILTER (WHERE …)` cuenta cada estado en una sola pasada por la tabla, sin hacer cuatro consultas.

### B03 · Las 10 cuentas en pesos con mayor saldo

- **Objetivo:** identificar las cuentas más grandes (clientes clave).
- **Tablas:** core.cuenta
- **Conceptos SQL:** WHERE, ORDER BY … DESC, LIMIT
- **Criterio de validación:** todas en COP, ordenadas de mayor a menor; ninguna CERRADA (una cerrada tiene saldo 0).
- **Tiempo:** 16 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT numero_cuenta, producto_codigo, estado_cuenta, saldo_contable
FROM core.cuenta
WHERE moneda_codigo = 'COP'
ORDER BY saldo_contable DESC
LIMIT 10;
```
</details>

**Resultado:**

```
 numero_cuenta | producto_codigo | estado_cuenta | saldo_contable 
---------------+-----------------+---------------+----------------
 20000007263   | CORRIENTE       | BLOQUEADA     |  2671046676.00
 40000010452   | EMPRESARIAL     | BLOQUEADA     |  2029858685.00
 20000010842   | CORRIENTE       | BLOQUEADA     |  1856835421.00
 20000013574   | CORRIENTE       | BLOQUEADA     |  1651691701.00
 40000009888   | EMPRESARIAL     | ACTIVA        |  1434848918.00
 20000013142   | CORRIENTE       | BLOQUEADA     |  1361303420.00
 40000011391   | EMPRESARIAL     | ACTIVA        |  1270208270.00
 20000005579   | CORRIENTE       | ACTIVA        |  1239781352.00
 20000011350   | CORRIENTE       | BLOQUEADA     |  1213719224.00
 20000012595   | CORRIENTE       | BLOQUEADA     |  1210329722.00
```

**Cómo explicarla:** Dato curioso para la defensa: **7 de las 10 cuentas con más saldo están BLOQUEADAS**. Es consecuencia del supuesto S1: una cuenta bloqueada sigue recibiendo dinero pero no puede sacarlo, así que acumula saldo.

### B04 · Transacciones de agosto de 2026 por tipo

- **Objetivo:** resumen del último mes: cuántas operaciones y cuánto dinero por tipo (en pesos).
- **Tablas:** fin.transaccion_financiera, core.cuenta
- **Conceptos SQL:** filtro por periodo, COUNT, SUM, AVG
- **Criterio de validación:** VC3 compara el total con el ledger.
- **Tiempo:** 76 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT t.tipo_codigo, count(*) AS transacciones, sum(t.monto) AS monto_total, round(avg(t.monto), 0) AS monto_promedio
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_origen_id, t.cuenta_destino_id)
WHERE t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2026-08-01' AND DATE '2026-08-31'
  AND c.moneda_codigo = 'COP'
GROUP BY t.tipo_codigo
ORDER BY transacciones DESC;
```
</details>

**Resultado:**

```
  tipo_codigo  | transacciones |  monto_total   | monto_promedio 
---------------+---------------+----------------+----------------
 TRANSFERENCIA |         18479 | 27505030952.00 |        1488448
 CONSIGNACION  |         16177 | 53210969000.00 |        3289298
 DEBITO        |         12860 |  7444545458.59 |         578892
 CREDITO       |         11361 | 24891255626.43 |        2190939
 RETIRO        |          4985 |  4778240000.00 |         958524
 REVERSO       |           663 |   867915433.00 |        1309073
 AJUSTE        |           255 |   105120793.00 |         412238
```

**Cómo explicarla:** En agosto de 2026 las transferencias son las más frecuentes, pero las consignaciones mueven más dinero. Se filtra COP porque sumar pesos con dólares no tiene sentido. La suma total se valida contra el ledger en VC3.

### B05 · Clientes vinculados por año

- **Objetivo:** ver el crecimiento de la base de clientes en el tiempo.
- **Tablas:** core.cliente
- **Conceptos SQL:** EXTRACT, GROUP BY, ORDER BY
- **Criterio de validación:** la suma de todos los años es 10.000.
- **Tiempo:** 2 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT extract(year FROM fecha_vinculacion)::int AS anio, count(*) AS clientes_nuevos
FROM core.cliente
GROUP BY 1
ORDER BY 1;
```
</details>

**Resultado:**

```
 anio | clientes_nuevos 
------+-----------------
 2015 |             327
 2016 |             344
 2017 |             439
 2018 |             565
 2019 |             610
 2020 |             716
 2021 |             726
 2022 |             762
 2023 |             834
 2024 |            1119
 2025 |            1956
 2026 |            1602
```

**Cómo explicarla:** El banco crece: 2025 fue el año con más clientes nuevos (1.956). 2026 va hasta agosto (fin de la ventana de datos).

### B06 · Consignaciones por mes en 2025

- **Objetivo:** estacionalidad de los depósitos en caja (¿se nota diciembre?).
- **Tablas:** fin.transaccion_financiera, core.cuenta
- **Conceptos SQL:** date_trunc, SUM, AVG
- **Criterio de validación:** 12 filas; diciembre debe destacar.
- **Tiempo:** 95 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT to_char(date_trunc('month', t.fecha_contable), 'YYYY-MM') AS mes,
       count(*) AS consignaciones, sum(t.monto) AS monto_total
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_destino_id
WHERE t.tipo_codigo = 'CONSIGNACION' AND t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
  AND c.moneda_codigo = 'COP'
GROUP BY 1
ORDER BY 1;
```
</details>

**Resultado:**

```
   mes   | consignaciones |  monto_total   
---------+----------------+----------------
 2025-01 |           6494 | 20501735000.00
 2025-02 |           6646 | 21023825000.00
 2025-03 |           7518 | 23709407000.00
 2025-04 |           8066 | 25272891000.00
 2025-05 |           8583 | 27481789000.00
 2025-06 |           8921 | 27172889000.00
 2025-07 |           9000 | 28238821000.00
 2025-08 |           8895 | 28374441000.00
 2025-09 |           9356 | 29669032000.00
 2025-10 |          10324 | 32355194000.00
 2025-11 |           9529 | 30587061000.00
 2025-12 |          14692 | 47483822000.00
```

**Cómo explicarla:** Diciembre de 2025 tiene 14.692 consignaciones frente a unas 9.500 en noviembre: la estacionalidad de fin de año que exige G4 se ve en los datos.

### B07 · Solicitudes rechazadas por motivo

- **Objetivo:** entender por qué se rechazan operaciones (fondos, bloqueos, límites).
- **Tablas:** fin.transaccion_financiera
- **Conceptos SQL:** WHERE sobre estado, GROUP BY de texto
- **Criterio de validación:** ninguna rechazada tiene motivo vacío (RN-45).
- **Tiempo:** 47 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT motivo_rechazo, count(*) AS rechazos,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS porcentaje
FROM fin.transaccion_financiera
WHERE estado_codigo = 'REJECTED'
GROUP BY motivo_rechazo
ORDER BY rechazos DESC;
```
</details>

**Resultado:**

```
                  motivo_rechazo                   | rechazos | porcentaje 
---------------------------------------------------+----------+------------
 Fondos insuficientes                              |    17842 |       74.0
 Cuenta bloqueada: no puede originar débitos       |     5239 |       21.7
 Excede el límite diario de retiro                 |      699 |        2.9
 Cuenta bloqueada: el reverso no puede debitarla   |      191 |        0.8
 Rechazado por el supervisor: soporte insuficiente |      127 |        0.5
 Fondos insuficientes para el reverso              |        6 |        0.0
```

**Cómo explicarla:** El 74 % de los rechazos es por fondos insuficientes y el 21,7 % por cuenta bloqueada. Todos tienen motivo (RN-45).

### B08 · Cuentas usando sobregiro

- **Objetivo:** cuentas corrientes con saldo negativo y qué parte de su cupo usan.
- **Tablas:** core.cuenta
- **Conceptos SQL:** columnas calculadas, WHERE, ORDER BY sobre expresión
- **Criterio de validación:** todas son CORRIENTE y ninguna pasa del 100 % del cupo (RN-17, RN-18).
- **Tiempo:** 7 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT numero_cuenta, producto_codigo, moneda_codigo, saldo_contable, cupo_sobregiro,
       round(100 * -saldo_contable / cupo_sobregiro, 1) AS porcentaje_cupo_usado
FROM core.cuenta
WHERE saldo_contable < 0
ORDER BY porcentaje_cupo_usado DESC
LIMIT 10;
```
</details>

**Resultado:**

```
 numero_cuenta | producto_codigo | moneda_codigo | saldo_contable | cupo_sobregiro | porcentaje_cupo_usado 
---------------+-----------------+---------------+----------------+----------------+-----------------------
 20000045874   | CORRIENTE       | COP           |    -4997051.00 |     5000000.00 |                  99.9
 20000035301   | CORRIENTE       | COP           |    -9993158.00 |    10000000.00 |                  99.9
 20000040189   | CORRIENTE       | COP           |    -9982243.00 |    10000000.00 |                  99.8
 20000039021   | CORRIENTE       | COP           |    -4989064.00 |     5000000.00 |                  99.8
 20000043255   | CORRIENTE       | COP           |    -9974751.00 |    10000000.00 |                  99.7
 20000024081   | CORRIENTE       | COP           |     -997134.00 |     1000000.00 |                  99.7
 20000007030   | CORRIENTE       | COP           |    -2987061.00 |     3000000.00 |                  99.6
 20000027276   | CORRIENTE       | COP           |     -996136.00 |     1000000.00 |                  99.6
 20000044715   | CORRIENTE       | COP           |    -4973047.00 |     5000000.00 |                  99.5
 20000035139   | CORRIENTE       | COP           |    -4967520.00 |     5000000.00 |                  99.4
```

**Cómo explicarla:** Todas son cuentas CORRIENTES (única con sobregiro, RN-17) y ninguna pasa del 100 % del cupo; la que más usa llega al 99,9 % (RN-18).

### B09 · Retiros grandes del último mes

- **Objetivo:** listar retiros en caja de 2.000.000 o más en agosto de 2026 (control de efectivo).
- **Tablas:** fin.transaccion_financiera, core.cuenta
- **Conceptos SQL:** BETWEEN, condiciones combinadas
- **Criterio de validación:** ningún retiro supera el límite diario de su cuenta (RN-37).
- **Tiempo:** 57 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT t.transaccion_id, c.numero_cuenta, t.monto, t.fecha_contabilizacion, c.limite_retiro_diario
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_origen_id
WHERE t.tipo_codigo = 'RETIRO' AND t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2026-08-01' AND DATE '2026-08-31'
  AND c.moneda_codigo = 'COP' AND t.monto >= 2000000
ORDER BY t.monto DESC
LIMIT 15;
```
</details>

**Resultado:**

```
 transaccion_id | numero_cuenta |    monto    | fecha_contabilizacion  | limite_retiro_diario 
----------------+---------------+-------------+------------------------+----------------------
         975425 | 20000011031   | 15870000.00 | 2026-08-11 09:35:42-05 |          20000000.00
         986840 | 20000006799   | 14380000.00 | 2026-08-15 09:42:57-05 |          20000000.00
         979974 | 20000046416   | 12490000.00 | 2026-08-13 12:38:49-05 |          20000000.00
        1013280 | 40000011280   | 11320000.00 | 2026-08-28 10:48:40-05 |          50000000.00
        1003304 | 20000005680   | 11000000.00 | 2026-08-23 11:34:57-05 |          20000000.00
         968770 | 40000033709   | 10590000.00 | 2026-08-07 10:17:45-05 |          50000000.00
        1009339 | 40000014240   | 10060000.00 | 2026-08-26 14:18:32-05 |          50000000.00
         979513 | 40000039230   |  9790000.00 | 2026-08-13 10:08:30-05 |          50000000.00
         963223 | 40000033501   |  9640000.00 | 2026-08-04 12:35:03-05 |          50000000.00
        1002678 | 20000001523   |  9530000.00 | 2026-08-22 17:44:05-05 |          20000000.00
        1008326 | 40000020257   |  9490000.00 | 2026-08-26 08:08:06-05 |          50000000.00
        1002320 | 40000024311   |  9300000.00 | 2026-08-22 14:34:54-05 |          50000000.00
        1006664 | 40000022975   |  8950000.00 | 2026-08-25 10:47:58-05 |          50000000.00
        1007369 | 40000035760   |  8690000.00 | 2026-08-25 15:16:10-05 |          50000000.00
         968897 | 20000014508   |  8310000.00 | 2026-08-07 10:54:15-05 |          30000000.00
```

**Cómo explicarla:** Retiros grandes en caja del último mes. El mayor (15.870.000) está por debajo del límite de su cuenta (20.000.000), como exige RN-37.

### B10 · Clientes con datos de contacto incompletos

- **Objetivo:** calidad de datos: clientes sin correo o sin teléfono.
- **Tablas:** core.cliente
- **Conceptos SQL:** IS NULL, COUNT con FILTER
- **Criterio de validación:** el total por tipo coincide con B01.
- **Tiempo:** 2 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT tipo_cliente,
       count(*) AS clientes,
       count(*) FILTER (WHERE email IS NULL)    AS sin_email,
       count(*) FILTER (WHERE telefono IS NULL) AS sin_telefono
FROM core.cliente
GROUP BY tipo_cliente;

-- =====================================================================
-- NIVEL INTERMEDIO
-- =====================================================================
```
</details>

**Resultado:**

```
 tipo_cliente | clientes | sin_email | sin_telefono 
--------------+----------+-----------+--------------
 NATURAL      |     8500 |       714 |            0
 JURIDICA     |     1500 |         0 |            0
```

**Cómo explicarla:** 714 personas naturales no tienen correo (un 8 %, a propósito, para probar calidad de datos). Nadie tiene el teléfono vacío.


## Nivel intermedia

### I01 · Los 10 clientes con mayor saldo en pesos

- **Objetivo:** clientes más valiosos por saldo total de sus cuentas (como titular principal vigente).
- **Tablas:** core.cliente, persona_natural / persona_juridica, titularidad_cuenta, cuenta
- **Conceptos SQL:** JOIN múltiple, LEFT JOIN a subtipos, COALESCE, GROUP BY, HAVING implícito por ORDER
- **Criterio de validación:** VC4 recalcula el saldo de estos clientes desde el ledger.
- **Tiempo:** 84 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT cl.cliente_id, cl.tipo_cliente,
       coalesce(pj.razon_social, pn.nombres || ' ' || pn.apellidos) AS nombre,
       count(*) AS cuentas, sum(c.saldo_contable) AS saldo_total
FROM core.cliente cl
JOIN core.titularidad_cuenta t ON t.cliente_id = cl.cliente_id AND t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id AND c.moneda_codigo = 'COP'
LEFT JOIN core.persona_natural pn  ON pn.cliente_id = cl.cliente_id
LEFT JOIN core.persona_juridica pj ON pj.cliente_id = cl.cliente_id
GROUP BY cl.cliente_id, cl.tipo_cliente, pj.razon_social, pn.nombres, pn.apellidos
ORDER BY saldo_total DESC
LIMIT 10;
```
</details>

**Resultado:**

```
 cliente_id | tipo_cliente |                    nombre                     | cuentas |  saldo_total   
------------+--------------+-----------------------------------------------+---------+----------------
        711 | JURIDICA     | Valencia Ingeniería S.A.S.                    |     282 | 22986405334.64
       4225 | JURIDICA     | Comercializadora Pinzón y Londoño S.A.S.      |     237 | 15587439244.61
       1486 | JURIDICA     | Parra Transportes Ltda.                       |     257 | 14227943354.33
        356 | JURIDICA     | Cardona Soluciones S.A.S.                     |     114 |  9037871016.43
       3423 | JURIDICA     | Comercializadora Bustamante y Rivera Ltda.    |     146 |  8695249171.46
       4295 | JURIDICA     | Inversiones Guerrero S.A.S.                   |     137 |  7550403555.02
       1617 | JURIDICA     | Comercializadora Arenas y Vera S.A.S.         |      84 |  7099654838.92
       3504 | JURIDICA     | Inversiones Saavedra Ltda.                    |     101 |  6560527383.80
       1405 | JURIDICA     | Comercializadora Rueda y Bautista S.A.S.      |      91 |  6024610005.54
       2879 | JURIDICA     | Comercializadora Rodríguez y Hernández S.A.S. |     103 |  6009382665.35
```

**Cómo explicarla:** Los 10 clientes con más dinero son empresas. El primero tiene 282 cuentas vigentes y casi 23 mil millones de pesos. Se usa `LEFT JOIN` a los dos subtipos y `COALESCE` para mostrar el nombre sea persona o empresa. VC4 recalcula su saldo desde el ledger.

### I02 · Cuentas activas sin movimientos en los últimos 90 días

- **Objetivo:** detectar cuentas "dormidas" candidatas a inactivación.
- **Tablas:** core.cuenta, fin.asiento_contable, fin.transaccion_financiera
- **Conceptos SQL:** NOT EXISTS (anti-join), subconsulta correlacionada
- **Criterio de validación:** al revisar el extracto de cualquiera de estas cuentas, su último movimiento es anterior al 2026-06-02.
- **Tiempo:** 266 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT c.producto_codigo, count(*) AS cuentas_dormidas
FROM core.cuenta c
WHERE c.estado_cuenta = 'ACTIVA'
  AND NOT EXISTS (
    SELECT 1
    FROM fin.asiento_contable a
    JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
    WHERE a.cuenta_id = c.cuenta_id AND t.fecha_contable > DATE '2026-08-31' - 90)
GROUP BY c.producto_codigo
ORDER BY cuentas_dormidas DESC;
```
</details>

**Resultado:**

```
 producto_codigo | cuentas_dormidas 
-----------------+------------------
 AHORROS         |             7348
 CORRIENTE       |             3678
 EMPRESARIAL     |             1330
 NOMINA          |                9
```

**Cómo explicarla:** Más de 12.000 cuentas activas no tuvieron movimientos en los últimos 90 días: son candidatas a inactivación (el procedimiento `core.pr_inactivar_cuentas_sin_movimiento` de G3 usa 180 días). `NOT EXISTS` es un anti-join: trae las cuentas para las que **no existe** ningún movimiento reciente.

### I03 · Transferencias regionales entre departamentos

- **Objetivo:** ¿entre qué departamentos se mueve más dinero? (según la oficina de cada cuenta)
- **Tablas:** transaccion_financiera, cuenta (×2), oficina (×2), municipio (×2), departamento (×2)
- **Conceptos SQL:** JOIN múltiple con la misma tabla dos veces (alias), filtro de desigualdad
- **Criterio de validación:** VC7 (regionales + mismo departamento = total de transferencias).
- **Tiempo:** 220 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT dor.nombre AS departamento_origen, dde.nombre AS departamento_destino,
       count(*) AS transferencias, sum(t.monto) AS monto_total
FROM fin.transaccion_financiera t
JOIN core.cuenta co    ON co.cuenta_id = t.cuenta_origen_id
JOIN core.cuenta cd    ON cd.cuenta_id = t.cuenta_destino_id
JOIN ref.oficina oo    ON oo.oficina_id = co.oficina_id
JOIN ref.oficina od    ON od.oficina_id = cd.oficina_id
JOIN ref.municipio mo  ON mo.municipio_codigo = oo.municipio_codigo
JOIN ref.municipio md  ON md.municipio_codigo = od.municipio_codigo
JOIN ref.departamento dor ON dor.departamento_codigo = mo.departamento_codigo
JOIN ref.departamento dde ON dde.departamento_codigo = md.departamento_codigo
WHERE t.tipo_codigo = 'TRANSFERENCIA' AND t.estado_codigo = 'POSTED'
  AND co.moneda_codigo = 'COP'
  AND mo.departamento_codigo <> md.departamento_codigo
GROUP BY dor.nombre, dde.nombre
ORDER BY monto_total DESC
LIMIT 10;
```
</details>

**Resultado:**

```
 departamento_origen | departamento_destino | transferencias |  monto_total   
---------------------+----------------------+----------------+----------------
 Antioquia           | Bogotá, D.C.         |           9109 | 13198208419.00
 Bogotá, D.C.        | Antioquia            |           8876 | 13059541450.00
 Bogotá, D.C.        | Valle del Cauca      |           6263 |  9340851291.00
 Valle del Cauca     | Bogotá, D.C.         |           6419 |  8989840296.00
 Bogotá, D.C.        | Atlántico            |           4703 |  6856460743.00
 Atlántico           | Bogotá, D.C.         |           3954 |  5671215421.00
 Antioquia           | Valle del Cauca      |           3248 |  4787602755.00
 Valle del Cauca     | Antioquia            |           3270 |  4513194473.00
 Tolima              | Bogotá, D.C.         |           2030 |  3395688727.00
 Antioquia           | Atlántico            |           2122 |  2966653703.00
```

**Cómo explicarla:** La ruta con más dinero es Antioquia ↔ Bogotá, en ambos sentidos. La misma tabla se une dos veces con alias distintos (origen y destino). VC7 comprueba que regionales + locales = total de transferencias.

### I04 · Empresas con más de 50 cuentas

- **Objetivo:** clientes corporativos grandes (cola larga de cuentas por cliente).
- **Tablas:** core.persona_juridica, core.titularidad_cuenta
- **Conceptos SQL:** GROUP BY + HAVING
- **Criterio de validación:** todos son personas jurídicas; el máximo coincide con el perfil de G4 (300).
- **Tiempo:** 9 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT pj.razon_social, count(*) AS cuentas
FROM core.persona_juridica pj
JOIN core.titularidad_cuenta t ON t.cliente_id = pj.cliente_id AND t.rol_titular = 'PRINCIPAL'
GROUP BY pj.cliente_id, pj.razon_social
HAVING count(*) > 50
ORDER BY cuentas DESC
LIMIT 15;
```
</details>

**Resultado:**

```
                 razon_social                  | cuentas 
-----------------------------------------------+---------
 Valencia Ingeniería S.A.S.                    |     300
 Comercializadora López y Ramírez S.A.S.       |     279
 Parra Transportes Ltda.                       |     272
 Comercializadora Pinzón y Londoño S.A.S.      |     248
 Correa Alimentos Ltda.                        |     187
 Comercializadora Guerra y Suárez S.A.S.       |     172
 Vallejo Ingeniería Ltda.                      |     164
 Comercializadora Sandoval y Gutiérrez S.A.S.  |     155
 Comercializadora Bustamante y Rivera Ltda.    |     155
 Castro Transportes S.A.S.                     |     151
 Inversiones Guerrero S.A.S.                   |     151
 Cardona Construcciones Ltda.                  |     142
 Solano Ingeniería Ltda.                       |     135
 Gil Consultores S.A.S.                        |     133
 Comercializadora Fernández y Sepúlveda S.A.S. |     133
```

**Cómo explicarla:** `HAVING` filtra **después** de agrupar (WHERE no puede usar `count(*)`). La empresa con más cuentas tiene 300, el mismo máximo que midió el perfil de G4.

### I05 · Participación de cada producto en los depósitos

- **Objetivo:** qué producto concentra el dinero de los clientes, por moneda.
- **Tablas:** core.cuenta
- **Conceptos SQL:** CTE (WITH), porcentaje sobre el total de la moneda
- **Criterio de validación:** VC1 obtiene el mismo total desde el ledger por cuenta contable.
- **Tiempo:** 11 ms

<details><summary>Ver la consulta</summary>

```sql
WITH saldos AS (
  SELECT moneda_codigo, producto_codigo, sum(saldo_contable) AS saldo
  FROM core.cuenta
  GROUP BY moneda_codigo, producto_codigo
)
SELECT moneda_codigo, producto_codigo, saldo,
       round(100 * saldo / sum(saldo) OVER (PARTITION BY moneda_codigo), 1) AS porcentaje_de_la_moneda
FROM saldos
ORDER BY moneda_codigo, saldo DESC;
```
</details>

**Resultado:**

```
 moneda_codigo | producto_codigo |      saldo      | porcentaje_de_la_moneda 
---------------+-----------------+-----------------+-------------------------
 COP           | EMPRESARIAL     | 404750308404.00 |                    40.3
 COP           | CORRIENTE       | 350427554464.00 |                    34.9
 COP           | AHORROS         | 126700742889.73 |                    12.6
 COP           | NOMINA          | 122592468763.00 |                    12.2
 USD           | EMPRESARIAL     |       798528.96 |                    75.9
 USD           | AHORROS         |       253402.31 |                    24.1
```

**Cómo explicarla:** En pesos, las cuentas EMPRESARIALES concentran el 40 % del dinero; en dólares, el 76 %. La CTE (`WITH`) calcula los saldos una vez y la ventana saca el porcentaje dentro de cada moneda. VC1 obtiene el mismo saldo desde el ledger.

### I06 · Cuentas con saldo por encima del promedio de su producto

- **Objetivo:** identificar cuentas "grandes" comparándolas con su propio producto (no con todas).
- **Tablas:** core.cuenta
- **Conceptos SQL:** CTE + subconsulta correlacionada en WHERE
- **Criterio de validación:** cada cuenta contada tiene saldo mayor que el promedio de su producto (columna promedio_producto).
- **Tiempo:** 39 ms

<details><summary>Ver la consulta</summary>

```sql
WITH promedios AS (
  SELECT producto_codigo, avg(saldo_contable) AS promedio
  FROM core.cuenta
  WHERE moneda_codigo = 'COP'
  GROUP BY producto_codigo
)
SELECT c.producto_codigo, count(*) AS cuentas_sobre_promedio,
       round((SELECT p.promedio FROM promedios p WHERE p.producto_codigo = c.producto_codigo), 0) AS promedio_producto
FROM core.cuenta c
WHERE c.moneda_codigo = 'COP'
  AND c.saldo_contable > (SELECT p.promedio FROM promedios p WHERE p.producto_codigo = c.producto_codigo)
GROUP BY c.producto_codigo
ORDER BY cuentas_sobre_promedio DESC;
```
</details>

**Resultado:**

```
 producto_codigo | cuentas_sobre_promedio | promedio_producto 
-----------------+------------------------+-------------------
 CORRIENTE       |                   3580 |          21856643
 AHORROS         |                   3526 |           6289127
 EMPRESARIAL     |                   2893 |          38591753
 NOMINA          |                   1170 |          44839967
```

**Cómo explicarla:** Cada cuenta se compara con el promedio de **su** producto, no con el de todas. Lección de rendimiento: la primera versión recalculaba el promedio 50.000 veces y tardó **2 min 39 s**; con la CTE tarda milisegundos. Es un buen ejemplo para G7.

### I07 · Flujo neto de dinero por departamento del cliente en 2026

- **Objetivo:** ¿en qué regiones entra más dinero del que sale?
- **Tablas:** asiento_contable, transaccion_financiera, cuenta, titularidad, cliente, municipio, departamento
- **Conceptos SQL:** JOIN de 7 tablas, SUM con CASE (créditos − débitos)
- **Criterio de validación:** la suma de todos los departamentos = variación de saldo 2026 de las cuentas COP.
- **Tiempo:** 530 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT d.nombre AS departamento,
       sum(CASE a.naturaleza WHEN 'C' THEN a.valor ELSE 0 END) AS entradas,
       sum(CASE a.naturaleza WHEN 'D' THEN a.valor ELSE 0 END) AS salidas,
       sum(CASE a.naturaleza WHEN 'C' THEN a.valor ELSE -a.valor END) AS flujo_neto
FROM fin.asiento_contable a
JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
JOIN core.cuenta c ON c.cuenta_id = a.cuenta_id
JOIN core.titularidad_cuenta ti ON ti.cuenta_id = c.cuenta_id AND ti.rol_titular = 'PRINCIPAL'
JOIN core.cliente cl ON cl.cliente_id = ti.cliente_id
JOIN ref.municipio mu ON mu.municipio_codigo = cl.municipio_codigo
JOIN ref.departamento d ON d.departamento_codigo = mu.departamento_codigo
WHERE t.fecha_contable >= DATE '2026-01-01' AND c.moneda_codigo = 'COP'
GROUP BY d.nombre
ORDER BY flujo_neto DESC
LIMIT 10;
```
</details>

**Resultado:**

```
    departamento    |    entradas     |    salidas     |   flujo_neto    
--------------------+-----------------+----------------+-----------------
 Bogotá, D.C.       | 213245754397.55 | 83914407820.52 | 129331346577.03
 Antioquia          | 107124661808.16 | 41344456689.59 |  65780205118.57
 Valle del Cauca    |  76393983580.63 | 28753144584.87 |  47640838995.76
 Atlántico          |  47608007516.28 | 17667218731.43 |  29940788784.85
 Tolima             |  24369434863.85 |  9652353312.42 |  14717081551.43
 Bolívar            |  20947414036.48 |  7462923039.67 |  13484490996.81
 Boyacá             |  20339617951.90 |  7979575223.00 |  12360042728.90
 Santander          |  17449788643.91 |  6593972374.93 |  10855816268.98
 Risaralda          |  13021569476.56 |  4923451978.00 |   8098117498.56
 Norte de Santander |  11943931956.01 |  4136485305.11 |   7807446650.90
```

**Cómo explicarla:** Todos los departamentos tienen flujo positivo en 2026: los saldos empezaron en 0 en septiembre de 2024 y el banco crece, así que entra más dinero del que sale. Bogotá lidera. Une 7 tablas para llegar del asiento contable al departamento del cliente.

### I08 · Usuarios internos que más transacciones registraron en 2026

- **Objetivo:** carga de trabajo por empleado y oficina.
- **Tablas:** seg.usuario, usuario_rol, rol, ref.oficina, fin.transaccion_financiera
- **Conceptos SQL:** JOIN, GROUP BY, LIMIT
- **Criterio de validación:** todos tienen un rol vigente con permiso para operar (CAJERO o SUPERVISOR).
- **Tiempo:** 304 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT u.login, r.codigo AS rol, o.nombre AS oficina, count(*) AS transacciones
FROM fin.transaccion_financiera t
JOIN seg.usuario u      ON u.usuario_id = t.creado_por
JOIN seg.usuario_rol ur ON ur.usuario_id = u.usuario_id AND ur.vigente_hasta IS NULL
JOIN seg.rol r          ON r.rol_id = ur.rol_id
LEFT JOIN ref.oficina o ON o.oficina_id = u.oficina_id
WHERE t.fecha_solicitud >= TIMESTAMPTZ '2026-01-01 00:00:00-05'
GROUP BY u.login, r.codigo, o.nombre
ORDER BY transacciones DESC
LIMIT 10;
```
</details>

**Resultado:**

```
   login   |  rol   |          oficina           | transacciones 
-----------+--------+----------------------------+---------------
 jjimenez2 | CAJERO | Oficina Ibagué             |          6862
 lpineda   | CAJERO | Oficina Ibagué             |          6755
 auribe    | CAJERO | Oficina Bello              |          4870
 mperea    | CAJERO | Oficina Bello              |          4785
 ssierra   | CAJERO | Oficina Medellín Sur       |          4249
 mguerrero | CAJERO | Oficina Medellín Sur       |          4226
 dochoa    | CAJERO | Oficina Medellín Occidente |          4114
 mcordoba  | CAJERO | Oficina Medellín Occidente |          4086
 iruiz     | CAJERO | Oficina Sincelejo          |          3999
 agomez3   | CAJERO | Oficina Sincelejo          |          3960
```

**Cómo explicarla:** Los cajeros más ocupados están en Ibagué y Bello. Se une con los roles vigentes para mostrar que quien registra transacciones es CAJERO o SUPERVISOR (RN-51).

### I09 · Reversos: qué se reversa y cuánto tarda

- **Objetivo:** medir errores corregidos: tipo de la transacción original y horas hasta el reverso.
- **Tablas:** fin.transaccion_financiera (auto-join)
- **Conceptos SQL:** SELF JOIN, diferencia de fechas, AVG
- **Criterio de validación:** todo reverso es posterior a su original y por el mismo monto (RN-41).
- **Tiempo:** 334 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT o.tipo_codigo AS tipo_original, count(*) AS reversos,
       round(avg(extract(epoch FROM r.fecha_contabilizacion - o.fecha_contabilizacion) / 3600)::numeric, 1) AS horas_promedio,
       count(*) FILTER (WHERE r.monto <> o.monto) AS con_monto_distinto
FROM fin.transaccion_financiera r
JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
WHERE r.tipo_codigo = 'REVERSO' AND r.estado_codigo = 'POSTED'
GROUP BY o.tipo_codigo
ORDER BY reversos DESC;
```
</details>

**Resultado:**

```
 tipo_original | reversos | horas_promedio | con_monto_distinto 
---------------+----------+----------------+--------------------
 DEBITO        |     6779 |          145.7 |                  0
 CONSIGNACION  |     2751 |           23.9 |                  0
```

**Cómo explicarla:** Solo se reversaron débitos (unos 6 días después, 146 horas en promedio: cobros no reconocidos) y consignaciones (1 día después: consignaciones erradas). La columna `con_monto_distinto` = 0 prueba RN-41. Es un *self join*: la tabla transacciones unida consigo misma.

### I10 · Clientes con cuentas en pesos y en dólares

- **Objetivo:** clientes multimoneda (oportunidad comercial).
- **Tablas:** core.titularidad_cuenta, core.cuenta, core.cliente
- **Conceptos SQL:** HAVING count(DISTINCT …)
- **Criterio de validación:** el mismo número se obtiene con INTERSECT (ver comentario).
- **Tiempo:** 43 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT cl.tipo_cliente, count(*) AS clientes_multimoneda
FROM (
  SELECT t.cliente_id
  FROM core.titularidad_cuenta t
  JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id
  WHERE t.rol_titular = 'PRINCIPAL'
  GROUP BY t.cliente_id
  HAVING count(DISTINCT c.moneda_codigo) = 2
) x
JOIN core.cliente cl ON cl.cliente_id = x.cliente_id
GROUP BY cl.tipo_cliente;
-- Alternativa equivalente: (clientes con COP) INTERSECT (clientes con USD).

-- =====================================================================
-- NIVEL AVANZADO
-- =====================================================================
```
</details>

**Resultado:**

```
 tipo_cliente | clientes_multimoneda 
--------------+----------------------
 JURIDICA     |                  193
 NATURAL      |                  324
```

**Cómo explicarla:** 517 clientes tienen cuentas en pesos y en dólares. `count(DISTINCT moneda) = 2` dentro de `HAVING` lo resuelve en una consulta; con `INTERSECT` se obtiene lo mismo.


## Nivel avanzada

### A01 · Los 3 clientes con mayor saldo de cada departamento

- **Objetivo:** clientes clave por región para la fuerza comercial.
- **Conceptos SQL:** función de ventana RANK() OVER (PARTITION BY … ORDER BY …)
- **Criterio de validación:** máximo 3 filas por departamento y rango 1 = mayor saldo del departamento.
- **Tiempo:** 74 ms

<details><summary>Ver la consulta</summary>

```sql
WITH saldo_cliente AS (
  SELECT cl.cliente_id, d.nombre AS departamento, sum(c.saldo_contable) AS saldo
  FROM core.cliente cl
  JOIN ref.municipio mu ON mu.municipio_codigo = cl.municipio_codigo
  JOIN ref.departamento d ON d.departamento_codigo = mu.departamento_codigo
  JOIN core.titularidad_cuenta t ON t.cliente_id = cl.cliente_id AND t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL
  JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id AND c.moneda_codigo = 'COP'
  GROUP BY cl.cliente_id, d.nombre
), ranking AS (
  SELECT departamento, cliente_id, saldo,
         rank() OVER (PARTITION BY departamento ORDER BY saldo DESC) AS puesto,
         count(*) OVER (PARTITION BY departamento) AS clientes_departamento
  FROM saldo_cliente
)
SELECT departamento, puesto, cliente_id, saldo
FROM ranking
WHERE puesto <= 3
  AND departamento IN (SELECT departamento FROM ranking GROUP BY departamento ORDER BY max(clientes_departamento) DESC LIMIT 5)
ORDER BY departamento, puesto;
```
</details>

**Resultado:**

```
  departamento   | puesto | cliente_id |     saldo      
-----------------+--------+------------+----------------
 Antioquia       |      1 |        356 |  9037871016.43
 Antioquia       |      2 |       3423 |  8695249171.46
 Antioquia       |      3 |       4295 |  7550403555.02
 Atlántico       |      1 |        711 | 22986405334.64
 Atlántico       |      2 |        461 |  5773872769.29
 Atlántico       |      3 |       1514 |  3325988271.48
 Bogotá, D.C.    |      1 |       1486 | 14227943354.33
 Bogotá, D.C.    |      2 |       1405 |  6024610005.54
 Bogotá, D.C.    |      3 |       2879 |  6009382665.35
 Bolívar         |      1 |       2307 |  2251961380.00
 Bolívar         |      2 |       2650 |  1887711787.00
 Bolívar         |      3 |        785 |  1263245843.22
 Valle del Cauca |      1 |       1093 |  5319686421.35
 Valle del Cauca |      2 |       1922 |  4313169445.35
 Valle del Cauca |      3 |       1575 |  4308964806.16
```

**Cómo explicarla:** `RANK() OVER (PARTITION BY departamento ORDER BY saldo DESC)` numera los clientes **dentro de cada departamento**. El cliente más grande del banco (Atlántico) es el puesto 1 de su región.

### A02 · Percentiles de monto por tipo de transacción

- **Objetivo:** describir la distribución (no solo el promedio): mediana, P90, P99.
- **Conceptos SQL:** percentile_cont(…) WITHIN GROUP (ORDER BY …)
- **Criterio de validación:** mediana < promedio en todos los tipos (distribución sesgada, criterio de G4).
- **Tiempo:** 896 ms

<details><summary>Ver la consulta</summary>

```sql
SELECT t.tipo_codigo, count(*) AS n,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY t.monto)::numeric(18,0) AS mediana,
       round(avg(t.monto), 0) AS promedio,
       percentile_cont(0.9)  WITHIN GROUP (ORDER BY t.monto)::numeric(18,0) AS p90,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY t.monto)::numeric(18,0) AS p99
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_origen_id, t.cuenta_destino_id)
WHERE t.estado_codigo = 'POSTED' AND c.moneda_codigo = 'COP'
GROUP BY t.tipo_codigo
ORDER BY n DESC;
```
</details>

**Resultado:**

```
  tipo_codigo  |   n    | mediana | promedio |   p90   |   p99    
---------------+--------+---------+----------+---------+----------
 TRANSFERENCIA | 278395 |  792359 |  1478145 | 3370984 | 10770178
 CONSIGNACION  | 242833 | 1792000 |  3193342 | 7305800 | 21669400
 DEBITO        | 193794 |  210465 |   486829 | 1035458 |  3477959
 CREDITO       | 188538 | 1290123 |  2122697 | 4455031 | 14367009
 RETIRO        |  78519 |  480000 |   918181 | 2270000 |  5830000
 REVERSO       |   9479 |  420319 |  1284203 | 3108200 | 13043560
 AJUSTE        |   4229 |  265126 |   477416 | 1101758 |  2874101
```

**Cómo explicarla:** En todos los tipos la mediana es menor que el promedio y el P99 es muy superior: muchas operaciones pequeñas y pocas grandes (distribución sesgada, criterio de G4).

### A03 · Extracto con saldo acumulado de una cuenta

- **Objetivo:** el extracto bancario: cada movimiento con el saldo después de aplicarlo.
- **Conceptos SQL:** SUM(...) OVER (ORDER BY …) (suma acumulada)
- **Criterio de validación:** VC2: el último saldo acumulado = saldo_contable de la cuenta.
- **Tiempo:** 296 ms

<details><summary>Ver la consulta</summary>

```sql
WITH cuenta_elegida AS (
  SELECT cuenta_id FROM fin.asiento_contable WHERE cuenta_id IS NOT NULL
  GROUP BY cuenta_id ORDER BY count(*) DESC LIMIT 1
), extracto AS (
  SELECT t.fecha_contabilizacion, t.tipo_codigo, a.naturaleza,
         CASE a.naturaleza WHEN 'C' THEN a.valor ELSE -a.valor END AS movimiento,
         sum(CASE a.naturaleza WHEN 'C' THEN a.valor ELSE -a.valor END)
           OVER (ORDER BY t.fecha_contabilizacion, t.transaccion_id) AS saldo_acumulado
  FROM fin.asiento_contable a
  JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
  WHERE a.cuenta_id = (SELECT cuenta_id FROM cuenta_elegida)
)
SELECT * FROM extracto ORDER BY fecha_contabilizacion DESC LIMIT 10;
```
</details>

**Resultado:**

```
 fecha_contabilizacion  |  tipo_codigo  | naturaleza | movimiento  | saldo_acumulado 
------------------------+---------------+------------+-------------+-----------------
 2026-08-31 21:56:27-05 | TRANSFERENCIA | C          |   879097.00 |   1434848918.00
 2026-08-31 19:47:46-05 | TRANSFERENCIA | D          | -6391109.00 |   1433969821.00
 2026-08-31 18:21:23-05 | TRANSFERENCIA | D          |  -703189.00 |   1440360930.00
 2026-08-31 17:28:24-05 | TRANSFERENCIA | C          |   925752.00 |   1441064119.00
 2026-08-31 15:56:42-05 | TRANSFERENCIA | D          | -1160035.00 |   1440138367.00
 2026-08-31 13:45:15-05 | CREDITO       | C          |  2256367.00 |   1441298402.00
 2026-08-31 06:20:50-05 | TRANSFERENCIA | D          | -1456688.00 |   1439042035.00
 2026-08-30 10:40:50-05 | TRANSFERENCIA | D          | -1138751.00 |   1440498723.00
 2026-08-29 23:48:37-05 | DEBITO        | D          |  -184460.00 |   1441637474.00
 2026-08-29 14:33:25-05 | DEBITO        | D          | -1276575.00 |   1441821934.00
```

**Cómo explicarla:** Es un extracto bancario: `SUM(...) OVER (ORDER BY fecha)` va sumando movimiento por movimiento. El último saldo (1.434.848.918) es igual al saldo guardado en la cuenta (VC2).

### A04 · Crecimiento mes a mes del número de transacciones

- **Objetivo:** tendencia y variación porcentual mensual.
- **Conceptos SQL:** LAG() OVER (ORDER BY …)
- **Criterio de validación:** VC6: la suma de los 24 meses = 1.000.000.
- **Tiempo:** 180 ms

<details><summary>Ver la consulta</summary>

```sql
WITH mensual AS (
  SELECT date_trunc('month', fecha_contable)::date AS mes, count(*) AS transacciones
  FROM fin.transaccion_financiera
  WHERE estado_codigo = 'POSTED'
  GROUP BY 1
)
SELECT to_char(mes, 'YYYY-MM') AS mes, transacciones,
       lag(transacciones) OVER (ORDER BY mes) AS mes_anterior,
       round(100.0 * (transacciones - lag(transacciones) OVER (ORDER BY mes)) / lag(transacciones) OVER (ORDER BY mes), 1) AS variacion_pct
FROM mensual
ORDER BY mes;
```
</details>

**Resultado:**

```
   mes   | transacciones | mes_anterior | variacion_pct 
---------+---------------+--------------+---------------
 2024-09 |         20955 |              |              
 2024-10 |         27148 |        20955 |          29.6
 2024-11 |         27934 |        27148 |           2.9
 2024-12 |         39278 |        27934 |          40.6
 2025-01 |         27322 |        39278 |         -30.4
 2025-02 |         29089 |        27322 |           6.5
 2025-03 |         31652 |        29089 |           8.8
 2025-04 |         34078 |        31652 |           7.7
 2025-05 |         35962 |        34078 |           5.5
 2025-06 |         37572 |        35962 |           4.5
 2025-07 |         38152 |        37572 |           1.5
 2025-08 |         37878 |        38152 |          -0.7
 2025-09 |         39407 |        37878 |           4.0
 2025-10 |         42923 |        39407 |           8.9
 2025-11 |         39964 |        42923 |          -6.9
 2025-12 |         60264 |        39964 |          50.8
 2026-01 |         40914 |        60264 |         -32.1
 2026-02 |         43801 |        40914 |           7.1
 2026-03 |         48939 |        43801 |          11.7
 2026-04 |         52124 |        48939 |           6.5
 2026-05 |         53607 |        52124 |           2.8
 2026-06 |         62398 |        53607 |          16.4
 2026-07 |         63572 |        62398 |           1.9
 2026-08 |         65067 |        63572 |           2.4
```

**Cómo explicarla:** `LAG()` trae el valor del mes anterior para calcular la variación. Diciembre sube más del 40 % y enero cae un 30 %. VC6: la suma de los 24 meses es exactamente 1.000.000.

### A05 · Cohortes de clientes por año de vinculación

- **Objetivo:** de los clientes que llegaron cada año, ¿qué porcentaje tuvo movimientos en 2026?
- **Conceptos SQL:** cohorte temporal simple, EXISTS, agregación condicional
- **Criterio de validación:** el total de clientes de todas las cohortes = 10.000.
- **Tiempo:** 420 ms

<details><summary>Ver la consulta</summary>

```sql
WITH activos_2026 AS (
  SELECT DISTINCT ti.cliente_id
  FROM fin.asiento_contable a
  JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
  JOIN core.titularidad_cuenta ti ON ti.cuenta_id = a.cuenta_id
  WHERE t.fecha_contable >= DATE '2026-01-01'
)
SELECT extract(year FROM cl.fecha_vinculacion)::int AS cohorte,
       count(*) AS clientes,
       count(ac.cliente_id) AS con_movimientos_2026,
       round(100.0 * count(ac.cliente_id) / count(*), 1) AS porcentaje_activos
FROM core.cliente cl
LEFT JOIN activos_2026 ac ON ac.cliente_id = cl.cliente_id
GROUP BY 1
ORDER BY 1;
```
</details>

**Resultado:**

```
 cohorte | clientes | con_movimientos_2026 | porcentaje_activos 
---------+----------+----------------------+--------------------
    2015 |      327 |                  320 |               97.9
    2016 |      344 |                  330 |               95.9
    2017 |      439 |                  421 |               95.9
    2018 |      565 |                  545 |               96.5
    2019 |      610 |                  584 |               95.7
    2020 |      716 |                  682 |               95.3
    2021 |      726 |                  688 |               94.8
    2022 |      762 |                  723 |               94.9
    2023 |      834 |                  795 |               95.3
    2024 |     1119 |                 1054 |               94.2
    2025 |     1956 |                 1779 |               91.0
    2026 |     1602 |                 1141 |               71.2
```

**Cómo explicarla:** Análisis de cohortes: de los clientes de 2015 a 2024, más del 94 % se movió en 2026; de los que llegaron en 2026, el 71 % (muchos acaban de abrir su cuenta).

### A06 · Anomalías: montos muy por encima de lo normal para la cuenta

- **Objetivo:** detectar transacciones atípicas (posible fraude o error): monto > promedio + 4 desviaciones de esa cuenta.
- **Conceptos SQL:** AVG() y STDDEV() OVER (PARTITION BY cuenta)
- **Criterio de validación:** solo se evalúan cuentas con al menos 20 movimientos (estadística estable).
- **Tiempo:** 1.083 ms

<details><summary>Ver la consulta</summary>

```sql
WITH movs AS (
  SELECT a.cuenta_id, a.transaccion_id, a.valor,
         avg(a.valor)    OVER (PARTITION BY a.cuenta_id) AS media,
         stddev(a.valor) OVER (PARTITION BY a.cuenta_id) AS desviacion,
         count(*)        OVER (PARTITION BY a.cuenta_id) AS n
  FROM fin.asiento_contable a
  WHERE a.cuenta_id IS NOT NULL
)
SELECT cuenta_id, transaccion_id, valor, round(media, 0) AS media_cuenta,
       round((valor - media) / nullif(desviacion, 0), 1) AS desviaciones
FROM movs
WHERE n >= 20 AND valor > media + 4 * desviacion
ORDER BY desviaciones DESC
LIMIT 10;
```
</details>

**Resultado:**

```
 cuenta_id | transaccion_id |    valor     | media_cuenta | desviaciones 
-----------+----------------+--------------+--------------+--------------
      4308 |         147221 | 106499000.00 |      2157484 |         23.0
     26966 |         729026 | 161262000.00 |      2344057 |         20.5
     17945 |         745233 |  74019000.00 |      2013336 |         19.7
     13149 |         144945 |  79873531.00 |      1891732 |         19.7
      8541 |         903872 |  88972000.00 |      2114339 |         19.5
      5789 |         792961 | 111060000.00 |      2389317 |         19.0
     10940 |          65496 |  87702000.00 |      2146727 |         18.2
     19530 |         879700 | 176974000.00 |      2784846 |         17.7
     27284 |         999920 |  97211000.00 |      2350063 |         17.6
      4396 |         584574 | 236487177.00 |      2674736 |         17.5
```

**Cómo explicarla:** Detección de anomalías con estadística: para cada cuenta se calcula su promedio y desviación estándar (`AVG` y `STDDEV` como ventanas) y se marcan los movimientos a más de 4 desviaciones. El más extremo está a 23 desviaciones del comportamiento normal de su cuenta.

### A07 · Patrón de fraccionamiento: retiros que casi agotan el límite varios días

- **Objetivo:** cuentas que retiran 80 % o más de su límite diario en 2 o más días (señal de alerta).
- **Conceptos SQL:** CTE encadenadas, funciones de ventana (row_number, lead) para reconstruir el límite
- **Criterio de validación:** ningún día supera el 100 % del límite vigente ese día (RN-37).
- **Tiempo:** 294 ms

<details><summary>Ver la consulta</summary>

```sql
WITH cambios AS (
  SELECT ev.cuenta_id, ev.ocurrido_en, cl.valor_anterior, cl.valor_nuevo,
         row_number() OVER w AS n, lead(ev.ocurrido_en) OVER w AS siguiente
  FROM core.evento_cuenta ev JOIN core.cambio_limite cl ON cl.evento_id = ev.evento_id
  WINDOW w AS (PARTITION BY ev.cuenta_id ORDER BY ev.ocurrido_en, ev.evento_id)
), limite AS (              -- tramos de tiempo con el límite que regía
  SELECT cuenta_id, NULL::timestamptz AS desde, ocurrido_en AS hasta, valor_anterior AS valor FROM cambios WHERE n = 1
  UNION ALL SELECT cuenta_id, ocurrido_en, siguiente, valor_nuevo FROM cambios
  UNION ALL SELECT c.cuenta_id, NULL, NULL, c.limite_retiro_diario FROM core.cuenta c
            WHERE NOT EXISTS (SELECT 1 FROM cambios x WHERE x.cuenta_id = c.cuenta_id)
), por_dia AS (
  SELECT t.cuenta_origen_id AS cuenta_id, t.fecha_contable, sum(t.monto) AS retirado,
         (t.fecha_contable + 1)::timestamp AT TIME ZONE 'America/Bogota' AS fin_dia
  FROM fin.transaccion_financiera t
  WHERE t.tipo_codigo = 'RETIRO' AND t.estado_codigo = 'POSTED'
  GROUP BY 1, 2
), con_limite AS (
  SELECT p.cuenta_id, p.fecha_contable, p.retirado, l.valor AS limite_vigente
  FROM por_dia p
  JOIN limite l ON l.cuenta_id = p.cuenta_id
               AND (l.desde IS NULL OR l.desde < p.fin_dia) AND (l.hasta IS NULL OR l.hasta >= p.fin_dia)
), alertas AS (
  SELECT cuenta_id, count(*) AS dias_alerta, max(round(100 * retirado / limite_vigente, 1)) AS max_pct_limite
  FROM con_limite
  WHERE retirado >= 0.8 * limite_vigente
  GROUP BY cuenta_id
  HAVING count(*) >= 2
)
SELECT count(*) AS cuentas_alerta, max(dias_alerta) AS max_dias_en_una_cuenta, max(max_pct_limite) AS max_pct_limite
FROM alertas;
```
</details>

**Resultado:**

```
 cuentas_alerta | max_dias_en_una_cuenta | max_pct_limite 
----------------+------------------------+----------------
             75 |                      9 |          100.0
```

**Cómo explicarla:** 75 cuentas retiraron 80 % o más de su límite en 2 días o más: patrón de alerta (fraccionamiento). El máximo es exactamente 100 %: nadie supera el límite **vigente ese día** (RN-37). La primera versión usaba el límite actual y daba días al 180 %: error de lógica corregido.

### A08 · Media móvil de 7 días de transacciones diarias

- **Objetivo:** suavizar la serie diaria para ver la tendencia sin el ruido de fines de semana.
- **Conceptos SQL:** AVG() OVER (ORDER BY … ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
- **Criterio de validación:** la media móvil siempre está entre el mínimo y el máximo de su ventana de 7 días.
- **Tiempo:** 110 ms

<details><summary>Ver la consulta</summary>

```sql
WITH diario AS (
  SELECT fecha_contable, count(*) AS transacciones
  FROM fin.transaccion_financiera
  WHERE estado_codigo = 'POSTED'
  GROUP BY fecha_contable
), movil AS (
  SELECT fecha_contable, transacciones,
         round(avg(transacciones) OVER (ORDER BY fecha_contable ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 0) AS media_movil_7d
  FROM diario
)
SELECT fecha_contable, to_char(fecha_contable, 'TMDay') AS dia, transacciones, media_movil_7d
FROM movil
ORDER BY fecha_contable DESC
LIMIT 14;
```
</details>

**Resultado:**

```
 fecha_contable |    dia    | transacciones | media_movil_7d 
----------------+-----------+---------------+----------------
 2026-08-31     | Monday    |          5592 |           2445
 2026-08-30     | Sunday    |          1364 |           1949
 2026-08-29     | Saturday  |          1526 |           1878
 2026-08-28     | Friday    |          2490 |           1870
 2026-08-27     | Thursday  |          2099 |           1877
 2026-08-26     | Wednesday |          2075 |           1887
 2026-08-25     | Tuesday   |          1967 |           1869
 2026-08-24     | Monday    |          2122 |           1865
 2026-08-23     | Sunday    |           867 |           1902
 2026-08-22     | Saturday  |          1468 |           1961
 2026-08-21     | Friday    |          2538 |           2073
 2026-08-20     | Thursday  |          2174 |           2445
 2026-08-19     | Wednesday |          1946 |           2428
 2026-08-18     | Tuesday   |          1941 |           2425
```

**Cómo explicarla:** La media móvil de 7 días (`ROWS BETWEEN 6 PRECEDING AND CURRENT ROW`) suaviza la caída de sábados y domingos. El 31 de agosto sube por fin de mes y pago de nómina.

### A09 · Concentración (Pareto): ¿qué porcentaje de cuentas mueve el 80 % del dinero?

- **Objetivo:** medir concentración del volumen transado en pesos.
- **Conceptos SQL:** SUM() OVER (ORDER BY … ) acumulada, ROW_NUMBER, porcentajes
- **Criterio de validación:** el acumulado final es 100 %.
- **Tiempo:** 568 ms

<details><summary>Ver la consulta</summary>

```sql
WITH volumen AS (
  SELECT a.cuenta_id, sum(a.valor) AS volumen
  FROM fin.asiento_contable a
  JOIN core.cuenta c ON c.cuenta_id = a.cuenta_id AND c.moneda_codigo = 'COP'
  GROUP BY a.cuenta_id
), acumulado AS (
  SELECT cuenta_id, volumen,
         row_number() OVER (ORDER BY volumen DESC) AS puesto,
         count(*) OVER () AS total_cuentas,
         sum(volumen) OVER (ORDER BY volumen DESC ROWS UNBOUNDED PRECEDING) / sum(volumen) OVER () AS pct_acumulado
  FROM volumen
)
SELECT min(puesto) AS cuentas_para_80pct,
       max(total_cuentas) AS cuentas_con_movimiento,
       round(100.0 * min(puesto) / max(total_cuentas), 1) AS porcentaje_de_cuentas
FROM acumulado
WHERE pct_acumulado >= 0.8;
```
</details>

**Resultado:**

```
 cuentas_para_80pct | cuentas_con_movimiento | porcentaje_de_cuentas 
--------------------+------------------------+-----------------------
               7579 |                  38749 |                  19.6
```

**Cómo explicarla:** El 19,6 % de las cuentas mueve el 80 % del dinero: la regla de Pareto (80/20) aparece en los datos. Se ordena por volumen y se acumula con una ventana.

### A10 · Ráfagas: 3 o más débitos de la misma cuenta en menos de 1 hora

- **Objetivo:** detectar uso inusualmente rápido de una cuenta (patrón de alerta).
- **Conceptos SQL:** COUNT() OVER (PARTITION BY … ORDER BY … RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW)
- **Criterio de validación:** al revisar una cuenta del resultado, sus débitos caen realmente dentro de la misma hora.
- **Tiempo:** 638 ms

<details><summary>Ver la consulta</summary>

```sql
WITH debitos AS (
  SELECT a.cuenta_id, t.fecha_contabilizacion AS ts,
         count(*) OVER (PARTITION BY a.cuenta_id ORDER BY t.fecha_contabilizacion
                        RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW) AS debitos_ultima_hora
  FROM fin.asiento_contable a
  JOIN fin.transaccion_financiera t ON t.transaccion_id = a.transaccion_id
  WHERE a.cuenta_id IS NOT NULL AND a.naturaleza = 'D'
)
SELECT cuenta_id, max(debitos_ultima_hora) AS max_debitos_en_1h, min(ts) FILTER (WHERE debitos_ultima_hora >= 3) AS primera_rafaga
FROM debitos
GROUP BY cuenta_id
HAVING max(debitos_ultima_hora) >= 3
ORDER BY max_debitos_en_1h DESC, cuenta_id
LIMIT 10;
```
</details>

**Resultado:**

```
 cuenta_id | max_debitos_en_1h |     primera_rafaga     
-----------+-------------------+------------------------
      2401 |                 4 | 2026-07-30 16:27:35-05
     10940 |                 4 | 2024-09-24 15:26:16-05
     20491 |                 4 | 2024-10-31 06:45:37-05
     26554 |                 4 | 2025-07-11 17:10:16-05
     30718 |                 4 | 2025-12-01 13:07:56-05
     33998 |                 4 | 2026-02-12 11:21:50-05
       127 |                 3 | 2024-12-30 17:18:24-05
      1307 |                 3 | 2025-06-13 09:08:34-05
      1372 |                 3 | 2025-02-24 13:42:32-05
      3163 |                 3 | 2025-02-15 19:11:56-05
```

**Cómo explicarla:** `RANGE BETWEEN INTERVAL '1 hour' PRECEDING` cuenta cuántos débitos tuvo la cuenta en la hora anterior a cada débito. Hay cuentas con 4 débitos en menos de una hora: patrón de uso inusualmente rápido.


## Validaciones cruzadas

Una validación cruzada calcula **el mismo dato por dos caminos independientes** (por ejemplo, desde la tabla de cuentas y desde el ledger). Si coinciden, el resultado de la consulta es confiable. El laboratorio pide al menos 5; hay 7.

```
 id  |                           que_compara                           |     camino_1     |     camino_2     | resultado 
-----+-----------------------------------------------------------------+------------------+------------------+-----------
 VC1 | I05 · saldo AHORROS COP: tabla cuenta vs ledger PAS_DEP_AHORROS |  126700742889.73 |  126700742889.73 | PASS
 VC2 | A03 · saldo final del extracto vs saldo almacenado              |    1434848918.00 |    1434848918.00 | PASS
 VC3 | B04 · Σ montos POSTED vs Σ débitos del ledger (cuadre técnico)  | 1767798714180.65 | 1767798714180.65 | PASS
 VC4 | I01 · saldo del cliente n.º 1: tabla cuenta vs ledger           |   22986405334.64 |   22986405334.64 | PASS
 VC5 | B02 · cuentas ACTIVAS: tabla cuenta vs último evento            |            43557 |            43557 | PASS
 VC6 | A04 · Σ de los meses vs total POSTED (1.000.000)                |          1000000 |          1000000 | PASS
 VC7 | I03 · transferencias regionales + locales vs total              |           279544 |           279544 | PASS
```

| ID | Qué demuestra |
|---|---|
| VC1 | El saldo por producto (I05) coincide con la contabilidad: la tabla de cuentas y el ledger dicen lo mismo. |
| VC2 | El extracto con saldo acumulado (A03) termina exactamente en el saldo guardado. |
| VC3 | El dinero de todas las transacciones POSTED es igual al total de débitos del ledger (doble partida). |
| VC4 | El saldo del cliente n.º 1 (I01) es el mismo calculado desde las cuentas o desde los asientos. |
| VC5 | El conteo de cuentas por estado (B02) coincide con el último evento de cada cuenta. |
| VC6 | La serie mensual (A04) suma exactamente el millón de transacciones. |
| VC7 | Las transferencias regionales (I03) más las locales son todas las transferencias: no se pierde ninguna en los joins. |

## Hallazgos de rendimiento (insumo para G7)

Sin índices secundarios (decisión de G3), estas son las consultas más lentas; serán candidatas del análisis `EXPLAIN (ANALYZE, BUFFERS)` de G7:

| Consulta | Tiempo | Posible causa |
|---|---|---|
| A06 · Anomalías: montos muy por encima de lo normal para la cuenta | 1.083 ms | Ventanas sobre 1,28 millones de movimientos de clientes |
| A02 · Percentiles de monto por tipo de transacción | 896 ms | Percentiles: ordenar todos los montos por tipo |
| A10 · Ráfagas: 3 o más débitos de la misma cuenta en menos de 1 hora | 638 ms | Ventana por cuenta ordenada por fecha sobre todos los débitos |
| A09 · Concentración (Pareto): ¿qué porcentaje de cuentas mueve el 80 % del dinero? | 568 ms | Agregar 2 millones de asientos por cuenta |
| I07 · Flujo neto de dinero por departamento del cliente en 2026 | 530 ms | Unir 7 tablas sobre los asientos de 2026 |

Además, I06 y A07 muestran dos errores típicos corregidos durante G5: una subconsulta correlacionada que recalculaba un promedio 50.000 veces (2 min 39 s → milisegundos) y una comparación contra el valor actual en lugar del vigente en la fecha.

## Verificación del gate G5

| Criterio del laboratorio | Resultado | Evidencia |
|---|---|---|
| 30 consultas: 10 básicas, 10 intermedias y 10 avanzadas | **Cumple** | B01–B10, I01–I10, A01–A10 |
| Todas funcionan sobre el millón de transacciones | **Cumple** | Resultados de este documento |
| Cada resultado se puede explicar | **Cumple** | Sección "Cómo explicarla" de cada consulta |
| Al menos 5 con validación cruzada | **Cumple** | 7 validaciones (VC1–VC7), todas PASS |
| Evidencia mínima: `sql/19_demo_queries.sql` + `evidence/g5_results.md` | **Cumple** | Ambos archivos |

**QUALITY GATE G5 = PASS**

## Matriz IA: nuevas entradas de G5

| ID | Prompt | Recomendación de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-28 | P-09 (4) | Subconsulta correlacionada que calcula el promedio del producto dentro del `WHERE` (I06). | **Modificar** | 2 min 39 s en la primera ejecución | Se precalcula el promedio en una CTE y la subconsulta solo lo consulta: milisegundos. |
| IA-29 | P-09 (4) | Comparar los retiros del día con el límite actual de la cuenta (A07). | **Rechazar / corregir** | Días "al 180 %" que no violaban RN-37 | Se compara con el límite vigente ese día, reconstruido desde los eventos. |
| IA-30 | P-09 (4) | Validación cruzada del saldo AHORROS sumando pesos y dólares (VC1). | **Corregir** | El ledger no separa moneda por cuenta contable | Se filtra COP en los dos caminos (decisión DM-09 de G2). |
| IA-31 | P-09 (4) | Crear índices ya para acelerar I02, I09 y A06. | **Rechazar** (por ahora) | Tiempos medidos arriba | Se hace en G7 con `EXPLAIN` antes y después, como exige el laboratorio. |
