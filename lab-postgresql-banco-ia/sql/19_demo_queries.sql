-- =====================================================================
-- 19_demo_queries.sql · Banco Andino Colombia · G5
-- 30 consultas de negocio: 10 básicas (B), 10 intermedias (I), 10 avanzadas (A)
-- y 7 validaciones cruzadas (VC): el mismo dato calculado por dos caminos
-- distintos debe coincidir.
--
-- Requisitos: modelo (run_all.sql) + lotes 1 y 2 cargados.
-- Uso:  psql -U postgres -d banco_andino_lab -f sql/19_demo_queries.sql
--       (SQL Shell: \i sql/19_demo_queries.sql)
-- Resultados y explicación de cada consulta: evidence/g5_results.md
--
-- Ventana de datos: 2024-09-01 a 2026-08-31. Solo se cuentan transacciones
-- POSTED cuando se habla de dinero (supuesto S5). Los montos no se suman
-- entre monedas: cada consulta filtra COP o agrupa por moneda.
-- =====================================================================

\set QUIET on
\pset footer off
SET timezone = 'America/Bogota';   -- fechas y horas en hora de Colombia
\timing on

-- =====================================================================
-- NIVEL BÁSICO
-- =====================================================================

-- @@ B01 | Clientes por tipo y estado
-- Objetivo: saber cuántos clientes hay de cada tipo y cuántos siguen activos.
-- Tablas: core.cliente · Conceptos: GROUP BY, COUNT, porcentaje con ventana simple
-- Validación: el total debe ser 10.000 y los tipos 8.500 / 1.500.
\echo '== B01 Clientes por tipo y estado'
SELECT tipo_cliente, estado_cliente, count(*) AS clientes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS porcentaje
FROM core.cliente
GROUP BY tipo_cliente, estado_cliente
ORDER BY tipo_cliente, clientes DESC;

-- @@ B02 | Cuentas por producto y estado
-- Objetivo: ver la cartera de cuentas por producto y en qué estado está.
-- Tablas: core.cuenta · Conceptos: GROUP BY de dos columnas, FILTER
-- Validación: el total debe ser 50.000 (ver VC5 para el estado).
\echo '== B02 Cuentas por producto y estado'
SELECT producto_codigo,
       count(*) AS total,
       count(*) FILTER (WHERE estado_cuenta = 'ACTIVA')    AS activas,
       count(*) FILTER (WHERE estado_cuenta = 'BLOQUEADA') AS bloqueadas,
       count(*) FILTER (WHERE estado_cuenta = 'INACTIVA')  AS inactivas,
       count(*) FILTER (WHERE estado_cuenta = 'CERRADA')   AS cerradas
FROM core.cuenta
GROUP BY producto_codigo
ORDER BY total DESC;

-- @@ B03 | Las 10 cuentas en pesos con mayor saldo
-- Objetivo: identificar las cuentas más grandes (clientes clave).
-- Tablas: core.cuenta · Conceptos: WHERE, ORDER BY … DESC, LIMIT
-- Validación: todas en COP, ordenadas de mayor a menor; ninguna CERRADA (una cerrada tiene saldo 0).
\echo '== B03 Top 10 cuentas COP por saldo'
SELECT numero_cuenta, producto_codigo, estado_cuenta, saldo_contable
FROM core.cuenta
WHERE moneda_codigo = 'COP'
ORDER BY saldo_contable DESC
LIMIT 10;

-- @@ B04 | Transacciones de agosto de 2026 por tipo
-- Objetivo: resumen del último mes: cuántas operaciones y cuánto dinero por tipo (en pesos).
-- Tablas: fin.transaccion_financiera, core.cuenta · Conceptos: filtro por periodo, COUNT, SUM, AVG
-- Validación: VC3 compara el total con el ledger.
\echo '== B04 Transacciones POSTED de agosto 2026 por tipo (COP)'
SELECT t.tipo_codigo, count(*) AS transacciones, sum(t.monto) AS monto_total, round(avg(t.monto), 0) AS monto_promedio
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = coalesce(t.cuenta_origen_id, t.cuenta_destino_id)
WHERE t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2026-08-01' AND DATE '2026-08-31'
  AND c.moneda_codigo = 'COP'
GROUP BY t.tipo_codigo
ORDER BY transacciones DESC;

-- @@ B05 | Clientes vinculados por año
-- Objetivo: ver el crecimiento de la base de clientes en el tiempo.
-- Tablas: core.cliente · Conceptos: EXTRACT, GROUP BY, ORDER BY
-- Validación: la suma de todos los años es 10.000.
\echo '== B05 Clientes vinculados por año'
SELECT extract(year FROM fecha_vinculacion)::int AS anio, count(*) AS clientes_nuevos
FROM core.cliente
GROUP BY 1
ORDER BY 1;

-- @@ B06 | Consignaciones por mes en 2025
-- Objetivo: estacionalidad de los depósitos en caja (¿se nota diciembre?).
-- Tablas: fin.transaccion_financiera, core.cuenta · Conceptos: date_trunc, SUM, AVG
-- Validación: 12 filas; diciembre debe destacar.
\echo '== B06 Consignaciones COP por mes en 2025'
SELECT to_char(date_trunc('month', t.fecha_contable), 'YYYY-MM') AS mes,
       count(*) AS consignaciones, sum(t.monto) AS monto_total
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_destino_id
WHERE t.tipo_codigo = 'CONSIGNACION' AND t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
  AND c.moneda_codigo = 'COP'
GROUP BY 1
ORDER BY 1;

-- @@ B07 | Solicitudes rechazadas por motivo
-- Objetivo: entender por qué se rechazan operaciones (fondos, bloqueos, límites).
-- Tablas: fin.transaccion_financiera · Conceptos: WHERE sobre estado, GROUP BY de texto
-- Validación: ninguna rechazada tiene motivo vacío (RN-45).
\echo '== B07 Rechazos por motivo'
SELECT motivo_rechazo, count(*) AS rechazos,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS porcentaje
FROM fin.transaccion_financiera
WHERE estado_codigo = 'REJECTED'
GROUP BY motivo_rechazo
ORDER BY rechazos DESC;

-- @@ B08 | Cuentas usando sobregiro
-- Objetivo: cuentas corrientes con saldo negativo y qué parte de su cupo usan.
-- Tablas: core.cuenta · Conceptos: columnas calculadas, WHERE, ORDER BY sobre expresión
-- Validación: todas son CORRIENTE y ninguna pasa del 100 % del cupo (RN-17, RN-18).
\echo '== B08 Cuentas en sobregiro (las 10 que más usan su cupo)'
SELECT numero_cuenta, producto_codigo, moneda_codigo, saldo_contable, cupo_sobregiro,
       round(100 * -saldo_contable / cupo_sobregiro, 1) AS porcentaje_cupo_usado
FROM core.cuenta
WHERE saldo_contable < 0
ORDER BY porcentaje_cupo_usado DESC
LIMIT 10;

-- @@ B09 | Retiros grandes del último mes
-- Objetivo: listar retiros en caja de 2.000.000 o más en agosto de 2026 (control de efectivo).
-- Tablas: fin.transaccion_financiera, core.cuenta · Conceptos: BETWEEN, condiciones combinadas
-- Validación: ningún retiro supera el límite diario de su cuenta (RN-37).
\echo '== B09 Retiros COP >= 2.000.000 en agosto 2026'
SELECT t.transaccion_id, c.numero_cuenta, t.monto, t.fecha_contabilizacion, c.limite_retiro_diario
FROM fin.transaccion_financiera t
JOIN core.cuenta c ON c.cuenta_id = t.cuenta_origen_id
WHERE t.tipo_codigo = 'RETIRO' AND t.estado_codigo = 'POSTED'
  AND t.fecha_contable BETWEEN DATE '2026-08-01' AND DATE '2026-08-31'
  AND c.moneda_codigo = 'COP' AND t.monto >= 2000000
ORDER BY t.monto DESC
LIMIT 15;

-- @@ B10 | Clientes con datos de contacto incompletos
-- Objetivo: calidad de datos: clientes sin correo o sin teléfono.
-- Tablas: core.cliente · Conceptos: IS NULL, COUNT con FILTER
-- Validación: el total por tipo coincide con B01.
\echo '== B10 Clientes con contacto incompleto'
SELECT tipo_cliente,
       count(*) AS clientes,
       count(*) FILTER (WHERE email IS NULL)    AS sin_email,
       count(*) FILTER (WHERE telefono IS NULL) AS sin_telefono
FROM core.cliente
GROUP BY tipo_cliente;

-- =====================================================================
-- NIVEL INTERMEDIO
-- =====================================================================

-- @@ I01 | Los 10 clientes con mayor saldo en pesos
-- Objetivo: clientes más valiosos por saldo total de sus cuentas (como titular principal vigente).
-- Tablas: core.cliente, persona_natural / persona_juridica, titularidad_cuenta, cuenta
-- Conceptos: JOIN múltiple, LEFT JOIN a subtipos, COALESCE, GROUP BY, HAVING implícito por ORDER
-- Validación: VC4 recalcula el saldo de estos clientes desde el ledger.
\echo '== I01 Top 10 clientes por saldo COP'
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

-- @@ I02 | Cuentas activas sin movimientos en los últimos 90 días
-- Objetivo: detectar cuentas "dormidas" candidatas a inactivación.
-- Tablas: core.cuenta, fin.asiento_contable, fin.transaccion_financiera · Conceptos: NOT EXISTS (anti-join), subconsulta correlacionada
-- Validación: al revisar el extracto de cualquiera de estas cuentas, su último movimiento es anterior al 2026-06-02.
\echo '== I02 Cuentas ACTIVAS sin movimiento desde 2026-06-02 (por producto)'
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

-- @@ I03 | Transferencias regionales entre departamentos
-- Objetivo: ¿entre qué departamentos se mueve más dinero? (según la oficina de cada cuenta)
-- Tablas: transaccion_financiera, cuenta (×2), oficina (×2), municipio (×2), departamento (×2)
-- Conceptos: JOIN múltiple con la misma tabla dos veces (alias), filtro de desigualdad
-- Validación: VC7 (regionales + mismo departamento = total de transferencias).
\echo '== I03 Top 10 rutas de transferencias entre departamentos distintos'
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

-- @@ I04 | Empresas con más de 50 cuentas
-- Objetivo: clientes corporativos grandes (cola larga de cuentas por cliente).
-- Tablas: core.persona_juridica, core.titularidad_cuenta · Conceptos: GROUP BY + HAVING
-- Validación: todos son personas jurídicas; el máximo coincide con el perfil de G4 (300).
\echo '== I04 Personas jurídicas con más de 50 cuentas'
SELECT pj.razon_social, count(*) AS cuentas
FROM core.persona_juridica pj
JOIN core.titularidad_cuenta t ON t.cliente_id = pj.cliente_id AND t.rol_titular = 'PRINCIPAL'
GROUP BY pj.cliente_id, pj.razon_social
HAVING count(*) > 50
ORDER BY cuentas DESC
LIMIT 15;

-- @@ I05 | Participación de cada producto en los depósitos
-- Objetivo: qué producto concentra el dinero de los clientes, por moneda.
-- Tablas: core.cuenta · Conceptos: CTE (WITH), porcentaje sobre el total de la moneda
-- Validación: VC1 obtiene el mismo total desde el ledger por cuenta contable.
\echo '== I05 Participación por producto en los saldos'
WITH saldos AS (
  SELECT moneda_codigo, producto_codigo, sum(saldo_contable) AS saldo
  FROM core.cuenta
  GROUP BY moneda_codigo, producto_codigo
)
SELECT moneda_codigo, producto_codigo, saldo,
       round(100 * saldo / sum(saldo) OVER (PARTITION BY moneda_codigo), 1) AS porcentaje_de_la_moneda
FROM saldos
ORDER BY moneda_codigo, saldo DESC;

-- @@ I06 | Cuentas con saldo por encima del promedio de su producto
-- Objetivo: identificar cuentas "grandes" comparándolas con su propio producto (no con todas).
-- Tablas: core.cuenta · Conceptos: CTE + subconsulta correlacionada en WHERE
-- Validación: cada cuenta contada tiene saldo mayor que el promedio de su producto (columna promedio_producto).
-- Nota de rendimiento: la primera versión calculaba el promedio dentro de la subconsulta para CADA
-- cuenta (50.000 veces) y tardó 2 min 39 s; con el promedio precalculado en una CTE tarda milisegundos.
\echo '== I06 Cuentas COP por encima del promedio de su producto'
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

-- @@ I07 | Flujo neto de dinero por departamento del cliente en 2026
-- Objetivo: ¿en qué regiones entra más dinero del que sale?
-- Tablas: asiento_contable, transaccion_financiera, cuenta, titularidad, cliente, municipio, departamento
-- Conceptos: JOIN de 7 tablas, SUM con CASE (créditos − débitos)
-- Validación: la suma de todos los departamentos = variación de saldo 2026 de las cuentas COP.
\echo '== I07 Flujo neto COP 2026 por departamento del titular principal (top 10)'
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

-- @@ I08 | Usuarios internos que más transacciones registraron en 2026
-- Objetivo: carga de trabajo por empleado y oficina.
-- Tablas: seg.usuario, usuario_rol, rol, ref.oficina, fin.transaccion_financiera · Conceptos: JOIN, GROUP BY, LIMIT
-- Validación: todos tienen un rol vigente con permiso para operar (CAJERO o SUPERVISOR).
\echo '== I08 Top 10 usuarios por transacciones registradas en 2026'
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

-- @@ I09 | Reversos: qué se reversa y cuánto tarda
-- Objetivo: medir errores corregidos: tipo de la transacción original y horas hasta el reverso.
-- Tablas: fin.transaccion_financiera (auto-join) · Conceptos: SELF JOIN, diferencia de fechas, AVG
-- Validación: todo reverso es posterior a su original y por el mismo monto (RN-41).
\echo '== I09 Reversos POSTED por tipo de la transacción original'
SELECT o.tipo_codigo AS tipo_original, count(*) AS reversos,
       round(avg(extract(epoch FROM r.fecha_contabilizacion - o.fecha_contabilizacion) / 3600)::numeric, 1) AS horas_promedio,
       count(*) FILTER (WHERE r.monto <> o.monto) AS con_monto_distinto
FROM fin.transaccion_financiera r
JOIN fin.transaccion_financiera o ON o.transaccion_id = r.transaccion_reversada_id
WHERE r.tipo_codigo = 'REVERSO' AND r.estado_codigo = 'POSTED'
GROUP BY o.tipo_codigo
ORDER BY reversos DESC;

-- @@ I10 | Clientes con cuentas en pesos y en dólares
-- Objetivo: clientes multimoneda (oportunidad comercial).
-- Tablas: core.titularidad_cuenta, core.cuenta, core.cliente · Conceptos: HAVING count(DISTINCT …)
-- Validación: el mismo número se obtiene con INTERSECT (ver comentario).
\echo '== I10 Clientes con cuentas COP y USD'
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

-- @@ A01 | Los 3 clientes con mayor saldo de cada departamento
-- Objetivo: clientes clave por región para la fuerza comercial.
-- Conceptos: función de ventana RANK() OVER (PARTITION BY … ORDER BY …)
-- Validación: máximo 3 filas por departamento y rango 1 = mayor saldo del departamento.
\echo '== A01 Top 3 clientes por saldo COP en cada departamento (5 departamentos más grandes)'
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

-- @@ A02 | Percentiles de monto por tipo de transacción
-- Objetivo: describir la distribución (no solo el promedio): mediana, P90, P99.
-- Conceptos: percentile_cont(…) WITHIN GROUP (ORDER BY …)
-- Validación: mediana < promedio en todos los tipos (distribución sesgada, criterio de G4).
\echo '== A02 Percentiles de monto COP por tipo'
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

-- @@ A03 | Extracto con saldo acumulado de una cuenta
-- Objetivo: el extracto bancario: cada movimiento con el saldo después de aplicarlo.
-- Conceptos: SUM(...) OVER (ORDER BY …) (suma acumulada)
-- Validación: VC2: el último saldo acumulado = saldo_contable de la cuenta.
\echo '== A03 Últimos 10 movimientos de la cuenta con más actividad, con saldo acumulado'
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

-- @@ A04 | Crecimiento mes a mes del número de transacciones
-- Objetivo: tendencia y variación porcentual mensual.
-- Conceptos: LAG() OVER (ORDER BY …)
-- Validación: VC6: la suma de los 24 meses = 1.000.000.
\echo '== A04 Transacciones POSTED por mes y variación frente al mes anterior'
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

-- @@ A05 | Cohortes de clientes por año de vinculación
-- Objetivo: de los clientes que llegaron cada año, ¿qué porcentaje tuvo movimientos en 2026?
-- Conceptos: cohorte temporal simple, EXISTS, agregación condicional
-- Validación: el total de clientes de todas las cohortes = 10.000.
\echo '== A05 Cohortes: % de clientes con movimientos en 2026 según año de vinculación'
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

-- @@ A06 | Anomalías: montos muy por encima de lo normal para la cuenta
-- Objetivo: detectar transacciones atípicas (posible fraude o error): monto > promedio + 4 desviaciones de esa cuenta.
-- Conceptos: AVG() y STDDEV() OVER (PARTITION BY cuenta)
-- Validación: solo se evalúan cuentas con al menos 20 movimientos (estadística estable).
\echo '== A06 Movimientos atípicos (> media + 4 desviaciones de su cuenta), los 10 más extremos'
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

-- @@ A07 | Patrón de fraccionamiento: retiros que casi agotan el límite varios días
-- Objetivo: cuentas que retiran 80 % o más de su límite diario en 2 o más días (señal de alerta).
-- Conceptos: CTE encadenadas, funciones de ventana (row_number, lead) para reconstruir el límite
--            vigente en el tiempo, agregación por cuenta-día, HAVING
-- Validación: ningún día supera el 100 % del límite vigente ese día (RN-37).
-- Nota: la primera versión comparaba con el límite ACTUAL y mostraba días "al 180 %": eran cuentas
-- a las que después les bajaron el límite. Hay que comparar con el límite vigente ese día.
\echo '== A07 Cuentas con 2 o más días retirando >= 80 % de su límite vigente'
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

-- @@ A08 | Media móvil de 7 días de transacciones diarias
-- Objetivo: suavizar la serie diaria para ver la tendencia sin el ruido de fines de semana.
-- Conceptos: AVG() OVER (ORDER BY … ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
-- Validación: la media móvil siempre está entre el mínimo y el máximo de su ventana de 7 días.
\echo '== A08 Transacciones diarias y media móvil de 7 días (últimos 14 días)'
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

-- @@ A09 | Concentración (Pareto): ¿qué porcentaje de cuentas mueve el 80 % del dinero?
-- Objetivo: medir concentración del volumen transado en pesos.
-- Conceptos: SUM() OVER (ORDER BY … ) acumulada, ROW_NUMBER, porcentajes
-- Validación: el acumulado final es 100 %.
\echo '== A09 Pareto del volumen COP por cuenta'
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

-- @@ A10 | Ráfagas: 3 o más débitos de la misma cuenta en menos de 1 hora
-- Objetivo: detectar uso inusualmente rápido de una cuenta (patrón de alerta).
-- Conceptos: COUNT() OVER (PARTITION BY … ORDER BY … RANGE BETWEEN INTERVAL '1 hour' PRECEDING AND CURRENT ROW)
-- Validación: al revisar una cuenta del resultado, sus débitos caen realmente dentro de la misma hora.
\echo '== A10 Cuentas con ráfagas de 3+ débitos en una hora'
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

-- =====================================================================
-- VALIDACIONES CRUZADAS (el mismo dato por dos caminos independientes)
-- =====================================================================
\echo '== Validaciones cruzadas'
WITH
top_cliente AS (   -- cuentas COP vigentes del cliente con mayor saldo (el n.º 1 de I01)
  SELECT t.cuenta_id
  FROM core.titularidad_cuenta t JOIN core.cuenta c ON c.cuenta_id = t.cuenta_id AND c.moneda_codigo = 'COP'
  WHERE t.rol_titular = 'PRINCIPAL' AND t.vigente_hasta IS NULL
    AND t.cliente_id = (SELECT t2.cliente_id FROM core.titularidad_cuenta t2
                        JOIN core.cuenta c2 ON c2.cuenta_id = t2.cuenta_id AND c2.moneda_codigo = 'COP'
                        WHERE t2.rol_titular = 'PRINCIPAL' AND t2.vigente_hasta IS NULL
                        GROUP BY t2.cliente_id ORDER BY sum(c2.saldo_contable) DESC LIMIT 1)),
vc1 AS (   -- I05: saldo AHORROS COP (tabla cuenta) = ledger de la cuenta contable PAS_DEP_AHORROS (tabla asiento)
  SELECT (SELECT sum(saldo_contable) FROM core.cuenta WHERE producto_codigo = 'AHORROS' AND moneda_codigo = 'COP') AS por_cuentas,
         (SELECT sum(CASE a.naturaleza WHEN 'C' THEN a.valor ELSE -a.valor END)
          FROM fin.asiento_contable a JOIN core.cuenta c ON c.cuenta_id = a.cuenta_id
          WHERE a.cuenta_contable_codigo = 'PAS_DEP_AHORROS' AND c.moneda_codigo = 'COP') AS por_ledger),
vc2 AS (   -- A03: saldo acumulado final del extracto = saldo almacenado de la cuenta
  SELECT c.saldo_contable AS por_cuentas,
         (SELECT sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) FROM fin.asiento_contable a WHERE a.cuenta_id = c.cuenta_id) AS por_ledger
  FROM core.cuenta c
  WHERE c.cuenta_id = (SELECT cuenta_id FROM fin.asiento_contable WHERE cuenta_id IS NOT NULL GROUP BY cuenta_id ORDER BY count(*) DESC LIMIT 1)),
vc3 AS (   -- B04: Σ monto de transacciones POSTED = Σ débitos del ledger
  SELECT (SELECT sum(monto) FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED') AS por_cuentas,
         (SELECT sum(valor) FROM fin.asiento_contable WHERE naturaleza = 'D') AS por_ledger),
vc4 AS (   -- I01: saldo del cliente n.º 1 por tabla cuenta = por ledger
  SELECT (SELECT sum(c.saldo_contable) FROM core.cuenta c WHERE c.cuenta_id IN (SELECT cuenta_id FROM top_cliente)) AS por_cuentas,
         (SELECT sum(CASE naturaleza WHEN 'C' THEN valor ELSE -valor END) FROM fin.asiento_contable a
          WHERE a.cuenta_id IN (SELECT cuenta_id FROM top_cliente)) AS por_ledger),
vc5 AS (   -- B02: cuentas por estado (tabla cuenta) = por último evento (tabla evento_cuenta)
  SELECT (SELECT count(*) FROM core.cuenta WHERE estado_cuenta = 'ACTIVA') AS por_cuentas,
         (SELECT count(*) FROM (SELECT DISTINCT ON (cuenta_id) estado_nuevo FROM core.evento_cuenta
                                ORDER BY cuenta_id, ocurrido_en DESC, evento_id DESC) e
          WHERE estado_nuevo = 'ACTIVA') AS por_ledger),
vc6 AS (   -- A04: suma de los 24 meses = total POSTED
  SELECT (SELECT sum(n) FROM (SELECT count(*) AS n FROM fin.transaccion_financiera WHERE estado_codigo = 'POSTED'
                              GROUP BY date_trunc('month', fecha_contable)) m) AS por_cuentas,
         1000000::numeric AS por_ledger),
vc7 AS (   -- I03: transferencias entre departamentos + dentro del mismo = total de transferencias
  SELECT (SELECT count(*) FROM fin.transaccion_financiera t
          JOIN core.cuenta co ON co.cuenta_id = t.cuenta_origen_id JOIN core.cuenta cd ON cd.cuenta_id = t.cuenta_destino_id
          JOIN ref.oficina oo ON oo.oficina_id = co.oficina_id JOIN ref.oficina od ON od.oficina_id = cd.oficina_id
          JOIN ref.municipio mo ON mo.municipio_codigo = oo.municipio_codigo JOIN ref.municipio md ON md.municipio_codigo = od.municipio_codigo
          WHERE t.tipo_codigo = 'TRANSFERENCIA' AND t.estado_codigo = 'POSTED'
            AND mo.departamento_codigo <> md.departamento_codigo)
       + (SELECT count(*) FROM fin.transaccion_financiera t
          JOIN core.cuenta co ON co.cuenta_id = t.cuenta_origen_id JOIN core.cuenta cd ON cd.cuenta_id = t.cuenta_destino_id
          JOIN ref.oficina oo ON oo.oficina_id = co.oficina_id JOIN ref.oficina od ON od.oficina_id = cd.oficina_id
          JOIN ref.municipio mo ON mo.municipio_codigo = oo.municipio_codigo JOIN ref.municipio md ON md.municipio_codigo = od.municipio_codigo
          WHERE t.tipo_codigo = 'TRANSFERENCIA' AND t.estado_codigo = 'POSTED'
            AND mo.departamento_codigo = md.departamento_codigo) AS por_cuentas,
         (SELECT count(*) FROM fin.transaccion_financiera WHERE tipo_codigo = 'TRANSFERENCIA' AND estado_codigo = 'POSTED') AS por_ledger)
SELECT v.id, v.que_compara, v.camino_1, v.camino_2,
       CASE WHEN v.camino_1 = v.camino_2 THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM (
  SELECT 'VC1' AS id, 'I05 · saldo AHORROS COP: tabla cuenta vs ledger PAS_DEP_AHORROS' AS que_compara, por_cuentas AS camino_1, por_ledger AS camino_2 FROM vc1
  UNION ALL SELECT 'VC2', 'A03 · saldo final del extracto vs saldo almacenado', por_ledger, por_cuentas FROM vc2
  UNION ALL SELECT 'VC3', 'B04 · Σ montos POSTED vs Σ débitos del ledger (cuadre técnico)', por_cuentas, por_ledger FROM vc3
  UNION ALL SELECT 'VC4', 'I01 · saldo del cliente n.º 1: tabla cuenta vs ledger', por_cuentas, por_ledger FROM vc4
  UNION ALL SELECT 'VC5', 'B02 · cuentas ACTIVAS: tabla cuenta vs último evento', por_cuentas, por_ledger FROM vc5
  UNION ALL SELECT 'VC6', 'A04 · Σ de los meses vs total POSTED (1.000.000)', por_cuentas, por_ledger FROM vc6
  UNION ALL SELECT 'VC7', 'I03 · transferencias regionales + locales vs total', por_cuentas, por_ledger FROM vc7
) v
ORDER BY v.id;

\timing off
