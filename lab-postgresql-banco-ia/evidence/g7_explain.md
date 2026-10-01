# G7 — Rendimiento e índices: EXPLAIN antes y después

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G7 — Performance, índices y seguridad** (parte 1: rendimiento; la seguridad está en [`g7_security.md`](g7_security.md)) |
| Fecha | 2026-10-01 |
| Workload | [`sql/perf/g7_workload.sql`](../sql/perf/g7_workload.sql): 10 consultas (W01–W10), 2 variantes y 3 operaciones reales |
| Cambios | [`sql/12_indexes.sql`](../sql/12_indexes.sql) (6 índices) · [`sql/15_procedures.sql`](../sql/15_procedures.sql) (procedimiento reescrito) · [`sql/perf/g7_aplicar.sql`](../sql/perf/g7_aplicar.sql) |
| Evidencia | PostgreSQL 16 (medición de referencia, secciones 2–7): [`g7_explain_pg16_antes.csv`](g7_explain_pg16_antes.csv) · [`g7_explain_pg16_despues.csv`](g7_explain_pg16_despues.csv) · planes completos en [`g7_planes_antes.txt`](g7_planes_antes.txt) y [`g7_planes_despues.txt`](g7_planes_despues.txt)<br>PostgreSQL 18.6 (PC del equipo, sección 10): [`g7_explain_antes.csv`](g7_explain_antes.csv) · [`g7_explain_despues.csv`](g7_explain_despues.csv) |
| Resultado | **10 consultas analizadas antes y después**. Se crearon 6 índices, cada uno justificado por una consulta. En 3 casos la decisión fue **no crear índice**. El retiro en caja pasó de **94,9 ms a 1,2 ms**. |

## 1. Método

1. **Workload.** Se eligieron 10 consultas representativas: 7 de operación diaria (OLTP), 1 de lote nocturno y 2 de reporte. Entre ellas están las que ejecutan por dentro las funciones del banco (`fn_retirar`, el trigger de eventos y el procedimiento de inactivación) y la consulta más lenta de G5.
2. **Antes.** Cada consulta se corrió con `EXPLAIN (ANALYZE, BUFFERS)` **5 veces** y se tomó la **mediana** del tiempo de ejecución, con caché caliente. No había índices secundarios: es la decisión de G3, documentada en `12_indexes.sql`.
3. **Análisis.** Para cada consulta se identificaron el cuello de botella, la causa, la selectividad y las columnas de filtro, join y orden (Prompt 6).
4. **Cambio mínimo.** Se creó un índice solo cuando una consulta lo justificaba. Cuando la mejor opción era otra (reescribir la consulta, o nada), se documentó.
5. **Después.** Se repitió el mismo script. El script detecta solo en qué fase está.
6. **Costo.** Se midió el tamaño de cada índice, el tiempo de creación, el tiempo de carga masiva y la latencia de una escritura real (consignación).

Entorno de la medición de referencia: PostgreSQL 16.13, 2 vCPU, 7 GB de RAM y configuración por defecto (`shared_buffers` 128 MB, `work_mem` 4 MB). La misma medición se repitió en el PostgreSQL 18.6 del equipo (Windows) con el mismo script: los tiempos absolutos cambian, pero los planes y las conclusiones se mantienen (sección 10).

## 2. Resultados antes y después

| ID | Consulta | Tipo | Antes (ms) | Después (ms) | Mejora | Buffers antes → después | Acceso después | Clasificación |
|---|---|---|---|---|---|---|---|---|
| W01 | Límite diario de retiro (`fn_retirar`, RN-37) | OLTP | 59,9 | 0,011 | × 5.446 | 16.911 → 4 | Index Scan IX-1 | **Crítica** |
| W02 | Extracto mensual de una cuenta | OLTP | 92,4 | 0,017 | × 5.435 | 20.859 → 28 | Index Scan IX-3 | **Relevante** |
| W03 | Saldo según el ledger de una cuenta (RN-48) | OLTP | 79,7 | 0,054 | × 1.476 | 20.822 → 106 | Index Scan IX-3 | **Relevante** |
| W04 | Últimas 20 transacciones (origen o destino) | OLTP | 55,4 | 0,110 | × 504 | 16.985 → 112 | BitmapOr IX-1 + IX-2 | **Relevante** |
| W05 | Cuentas vigentes de un cliente | OLTP | 2,3 | 0,024 | × 97 | 476 → 38 | Index Scan IX-4 | **Menor** |
| W06 | Último evento de la cuenta (trigger) | OLTP | 5,0 | 0,006 | × 840 | 1.261 → 4 | Index Only Scan IX-5 | **Relevante** |
| W07 | Cola de ajustes pendientes | OLTP | 54,3 | 0,019 | × 2.859 | 16.985 → 47 | Index Scan IX-6 (parcial) | **Relevante** |
| W08 | Buscar cliente por documento | OLTP | 0,028 | 0,011 | igual | 6 → 6 | Index Scan `uq_cliente_documento` | **NO crear índice** |
| W09 | Cuentas ACTIVAS sin movimiento en 90 días | Lote | 428,7 | 418,2 | × 1,0 | 39.162 → 39.178 | Seq Scan (no usa el índice) | **No concluyente** |
| W09R | W09 reescrita (sin join) | Lote | 152,5 | 74,3 | **× 5,8** frente a W09 | 22.251 → 132.248 | Index Only Scan IX-3 | **Relevante** (reescritura + IX-3) |
| W10 | Movimientos atípicos (G5 A06) | Reporte | 1.346,7 | **2.760,8** | **× 0,5 (regresión)** | 20.822 → 1.277.467 | Index Scan IX-3 | **NO crear índice** (ver §5) |
| W10S | W10 con `enable_indexscan = off` en su sesión | Reporte | 1.431,9 | 1.426,1 | igual que antes | 20.822 → 20.829 | Seq Scan | Mitigación |

**Operaciones reales** (se ejecutan y se deshacen con `ROLLBACK`):

| ID | Operación | Antes | Después | Mejora |
|---|---|---|---|---|
| OP1 | Retiro en caja `fin.fn_retirar` (promedio de 200) | 94,9 ms | **1,17 ms** | **× 81** |
| OP2 | Consignación en caja `fin.fn_consignar` (promedio de 200) | 1,32 ms | 1,18 ms | sin costo medible de escritura |
| OP3 | `pr_inactivar_cuentas_sin_movimiento(180 días)`: 4.018 cuentas | 22,7 s | **1,1 s** | **× 20,7** |

## 3. Análisis por consulta (Prompt 6)

**W01 · Límite diario de retiro.** Se ejecuta dentro de `fn_retirar` **en cada retiro**, con la cuenta bloqueada (`FOR UPDATE`).

- **Antes:** `Parallel Seq Scan` de 1.024.178 transacciones (16.911 buffers, unos 132 MB) para encontrar **1** fila. Mientras tanto, nadie más puede operar esa cuenta.
- **Selectividad:** altísima. La cuenta 30 tiene 31 transacciones como origen y 1 de ellas ese día.
- **Columnas:** filtro `cuenta_origen_id =` y `fecha_contable =`. `tipo_codigo` y `estado_codigo` tienen muy pocos valores (7 y 3), así que van como filtro residual y no en el índice.
- **Índice IX-1** `(cuenta_origen_id, fecha_contable)`: el plan pasa a `Index Scan` con 4 buffers. El retiro completo (OP1) baja de 94,9 a 1,17 ms.
- **Clasificación: crítica.** Era un cuello de botella de concurrencia: cada retiro mantenía el bloqueo 95 ms.

**W02 · Extracto mensual** y **W03 · Saldo según el ledger (RN-48).**

- **Antes:** `Seq Scan` de los 2.000.000 de asientos (20.859 buffers) para devolver 5 y 103 filas.
- **Índice IX-3** `(cuenta_id, registrado_en) WHERE cuenta_id IS NOT NULL`. Lo usan W02 (filtro por cuenta y rango de fechas, orden por fecha: el índice entrega las filas ya ordenadas), W03 y W09R.
- **Es parcial:** el 36 % de las líneas (720.456) son de cuentas contables internas, como caja, que tienen `cuenta_id` NULL. Ninguna consulta por cuenta las necesita.
- **Clasificación: relevante.** Son consultas frecuentes de caja y conciliación.

**W04 · Historial de la cuenta (origen OR destino).**

- **Antes:** `Seq Scan`.
- Con solo IX-1 el `OR` seguiría obligando a recorrer la tabla. Por eso existe **IX-2** `(cuenta_destino_id, fecha_contable)`: el plan combina los dos índices (`BitmapOr`) y lee 112 buffers.
- **Clasificación: relevante.**

**W05 · Cuentas de un cliente.**

- La PK de `titularidad_cuenta` empieza por `cuenta_id`, así que buscar por cliente recorría las 51.551 filas.
- **IX-4** `(cliente_id)`: 2,3 → 0,024 ms.
- **Clasificación: menor**, porque ya era rápida.
- **Se crea igual** porque cuesta casi nada (592 kB; la tabla casi no se escribe) y también lo usa `fn_cerrar_cuenta` para saber si el cliente queda sin cuentas vigentes.

**W06 · Último evento de la cuenta.** Lo ejecuta el trigger `trg_evento_validar` en **cada** evento: bloqueo, desbloqueo, cierre, inactivación…

- **Antes:** `Seq Scan` de 112.145 eventos.
- **IX-5** `(cuenta_id, ocurrido_en)`: `Index Only Scan` con 4 buffers.
- **Clasificación: relevante;** en los procesos por lotes es crítica. Es la razón principal de que OP3 (4.018 eventos de inactivación) baje de 22,7 s a 1,1 s.

**W07 · Cola de ajustes pendientes.** El supervisor la consulta para aprobar ajustes (RN-44).

- **Antes:** `Seq Scan` del millón para encontrar 74 filas (0,007 %).
- **IX-6** parcial `(fecha_solicitud) WHERE estado_codigo = 'PENDING_APPROVAL'`: ocupa **16 kB**. Solo guarda las pendientes y ya entrega el orden.
- **Clasificación: relevante,** con costo prácticamente nulo.

**W08 · Buscar cliente por documento.**

- Ya usa `uq_cliente_documento`, el índice que crea la restricción UNIQUE de RN-01: 6 buffers.
- **Decisión: NO crear índice.** Un índice nuevo sería un duplicado.

**W09 · Cuentas sin movimiento (I02 de G5 y el procedimiento de inactivación).**

- La condición es por **fecha de transacción**: el 18 % de las transacciones (185.488) caen en la ventana. Con esa baja selectividad, el planificador sigue prefiriendo leer las tablas completas aunque exista IX-3: 428,7 → 418,2 ms.
- **Índice solo: no concluyente.**
- La mejora real vino de **reescribirla**. `asiento_contable.registrado_en` siempre es igual a `fecha_contabilizacion` de su transacción: lo garantiza `fn_contabilizar`, y se verificó en los 2.000.000 de asientos con 0 diferencias. Así se puede filtrar en el asiento y quitar el join (W09R):
  - Sin índice: 152,5 ms.
  - Con IX-3: 74,3 ms (`Nested Loop Anti Join` + `Index Only Scan`).
  - Mismo resultado: **12.365 cuentas** en las dos versiones.
- Se actualizó `core.pr_inactivar_cuentas_sin_movimiento` (`sql/15_procedures.sql`) con esta forma.
- Nota: W09R lee **más** buffers (132.248) pero tarda **menos**, porque son lecturas de índice en memoria. **Buffers y tiempo no son lo mismo.**

**W10 · Movimientos atípicos (A06 de G5).** Ver la sección 5.

## 4. Costo de los índices (escritura y almacenamiento)

| Índice | Tabla | Justificado por | Tamaño | Creación | Entradas |
|---|---|---|---|---|---|
| IX-1 `ix_transaccion_origen_fecha` | transaccion_financiera | W01, W04 | 20 MB | 0,83 s | 1.024.178 |
| IX-2 `ix_transaccion_destino_fecha` | transaccion_financiera | W04 | 23 MB | 0,77 s | 1.024.178 |
| IX-3 `ix_asiento_cuenta_fecha` (parcial) | asiento_contable | W02, W03, W09R | 39 MB | 1,10 s | 1.279.544 de 2.000.000 |
| IX-4 `ix_titularidad_cliente` | titularidad_cuenta | W05 | 0,6 MB | 0,02 s | 51.551 |
| IX-5 `ix_evento_cuenta_fecha` | evento_cuenta | W06 | 3,4 MB | 0,05 s | 112.145 |
| IX-6 `ix_transaccion_pendientes` (parcial) | transaccion_financiera | W07 | 16 kB | 0,06 s | 74 |
| **Total** | | | **≈ 86 MB (+18 % sobre 475 MB)** | **≈ 3 s** | |

Costo de escritura medido:

- **Operación en línea:** una consignación escribe 1 transacción y 2 asientos, y por eso actualiza también IX-1/IX-2/IX-3. Pasó de 1,32 a 1,18 ms (OP2). El costo extra queda por debajo del ruido de la medición.
- **Carga masiva** (base nueva con los índices ya creados por `run_all.sql`):
  - El lote 2 pasó de **1 min 23 s a 1 min 39 s (+16 s, +20 %)**.
  - El `\copy` de transacciones pasó de 34,5 a 43,2 s y el de asientos de 29,0 a 34,5 s.
  - Construidos durante la carga, los índices ocupan 116 MB en vez de 86 MB.
  - **Recomendación** para cargas grandes futuras: crear los índices después de cargar.
- **Riesgo de sobreindexación:** `transaccion_financiera` queda con 6 índices: PK, `idempotency_key`, `transaccion_reversada_id`, IX-1, IX-2 e IX-6. Este último solo se escribe cuando la transacción está pendiente. Es el máximo razonable para la tabla que más se escribe; **no se agregan más sin una consulta que lo exija**. La sección 5 muestra que el riesgo es real.

## 5. W10: un índice que empeora otra consulta (y la decisión)

- **Qué pasó:** W10 (A06 de G5) recorre **todos** los asientos de clientes (1.279.544) para calcular promedio y desviación por cuenta con funciones de ventana.
  - **Antes:** `Seq Scan` + ordenar por cuenta (41 MB en disco) en 1,35 s.
  - **Después de crear IX-3,** el planificador cambió de plan: usa el índice para leer los asientos **ya ordenados por cuenta** y se ahorra el ordenamiento. Su costo estimado bajó (264.571 → 179.986), pero el tiempo real **subió a 2,76 s**. Leyó 1.277.467 buffers, porque visitó la tabla en orden aleatorio, fila por fila.
  - **El costo estimado no es el tiempo real:** el planificador subestimó el acceso aleatorio.
- **Alternativas medidas:**

| Alternativa | Resultado | Decisión |
|---|---|---|
| Índice cubriente `INCLUDE (naturaleza, valor)` | 60 MB en vez de 39 MB y W10 siguió en 2,8 s (también necesita `transaccion_id`) | Rechazada |
| `work_mem = 64MB` para ordenar en memoria | 1,55 s: el cuello no es el ordenamiento sino el cálculo numérico de la ventana | Rechazada |
| Reescribir con `GROUP BY` + join | 1,9 s: el agregado se repite en cada worker paralelo y se derrama a disco | Rechazada |
| Quitar IX-3 | W10 vuelve a 1,35 s, pero W02, W03 y W09R vuelven a 80–150 ms y OP3 empeora | Rechazada |
| `SET LOCAL enable_indexscan = off` **solo en la transacción del reporte** (W10S) | 1,43 s, igual que antes; no afecta a ninguna otra consulta | **Aceptada** |

- **Decisión:**
  - **Para W10, NO crear índice:** ningún índice le sirve, porque lee el 100 % de las filas de clientes.
  - Se mantiene IX-3, porque sirve a consultas de operación diaria.
  - El reporte, que corre una vez al día o al mes, desactiva el index scan solo en su propia transacción.
  - En producción, lo ideal es correr los reportes en una réplica de lectura.

## 6. Efecto en las 30 consultas de G5

Se corrieron las 30 consultas de `19_demo_queries.sql` en dos bases nuevas e idénticas, una sin índices de G7 y otra con ellos:

- Todas siguen funcionando, con los mismos resultados.
- 28 quedan dentro del ruido de la medición (±10 %; A01, A07, I07 e I09 se repitieron 5 veces para confirmarlo).
- A03 (últimos movimientos de una cuenta) mejora de 363 a 240 ms porque usa IX-3.
- **A06 empeora de 1,08 a 2,63 s:** es W10 (sección 5).
- El quality gate de G6 sobre la base reconstruida con índices sigue en **99,6, QUALITY_GATE = PASS**. DS05 (FK sin índice) baja de 34 a 29.

## 7. Decisiones de NO crear índice

| Candidato | Por qué no |
|---|---|
| Documento del cliente (W08) | Ya existe `uq_cliente_documento`. |
| Cualquier índice para W10 o para los reportes lentos de G5 (A02, A09, A10, I07) | Leen todas o casi todas las filas (agregados de todo el periodo); un índice no reduce el trabajo y puede empeorar el plan (sección 5). |
| `fecha_contable` sola | Baja selectividad: un mes es cerca del 6 % del millón y 2026 es el 43 %; los reportes por periodo terminan leyendo casi toda la tabla. |
| `tipo_codigo` o `estado_codigo` solos | 7 y 3 valores distintos; solo vale la pena el estado minoritario (IX-6, parcial). |
| `creado_por` (usuario que registró) | La única consulta (I08 de G5) agrega todo 2026. |
| Las 29 FK restantes sin índice (DS05 de G6) | 26 apuntan a catálogos (`ref.*`, producto, rol, permiso) o a `seg.usuario`, que nunca se borran (los usuarios se desactivan). Las otras 3 ya las cubre la PK de su tabla (`persona_natural`, `persona_juridica`, `cambio_limite`). Ninguna consulta del workload las necesita. |

## 8. Verificación del gate G7 (rendimiento)

| Criterio de la guía | Resultado | Evidencia |
|---|---|---|
| Seleccionar 10 consultas representativas | **Cumple** | W01–W10 (OLTP, lote y reporte) |
| `EXPLAIN (ANALYZE, BUFFERS)` antes de optimizar | **Cumple** | `g7_planes_antes.txt`, `g7_explain_antes.csv` |
| Identificar scans, joins, sorts y lecturas costosas | **Cumple** | Sección 3 (Seq Scan del millón, sort externo de 41 MB, anti join con hash) |
| Índices solo con una consulta que los justifique | **Cumple** | 6 índices, cada uno con su consulta (comentario en la base y en `12_indexes.sql`) |
| Repetir EXPLAIN y comparar costo, tiempo y lecturas | **Cumple** | Sección 2, `g7_explain_despues.csv`, `g7_planes_despues.txt` |
| Clasificar la mejora y señalar cuándo NO crear índice | **Cumple** | Columna "Clasificación"; secciones 5 y 7 |
| ≥ 5 consultas críticas analizadas antes y después | **Cumple** | 10 consultas + 3 operaciones reales |

La parte de seguridad (RBAC) se verifica en [`g7_security.md`](g7_security.md).

## 9. Matriz IA: nuevas entradas de G7 (rendimiento)

| ID | Prompt | Recomendación o resultado de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-37 | P-09 (4) / P-11 (6) | En G5 la IA marcó como candidatas a índice las 5 consultas más lentas (A06, A02, A10, A09, I07). | **Rechazar** | Secciones 5 y 7 | Son reportes que leen casi todo; los cuellos de botella reales estaban en las operaciones (W01, W06). |
| IA-38 | P-11 (6) | Índice `asiento_contable (cuenta_id, registrado_en)`. | **Modificar** | IX-3: 39 MB | Se hizo parcial (`cuenta_id IS NOT NULL`): excluye el 36 % de las líneas que ninguna consulta por cuenta usa. |
| IA-39 | P-11 (6) | Índice cubriente `INCLUDE (naturaleza, valor)` para corregir la regresión de W10. | **Rechazar** | 60 MB; W10 en 2,8 s | No resolvió la regresión y aumentó el tamaño un 54 %. |
| IA-40 | P-11 (6) | Subir `work_mem` o reescribir W10 con `GROUP BY`. | **Rechazar** | 1,55 s y 1,9 s | Ninguna mejora; el cuello es el cálculo numérico. |
| IA-41 | P-11 (6) | Desactivar el index scan solo en la transacción del reporte W10. | **Aceptar** | W10S: 1,43 s | Mitigación con alcance limitado; IX-3 se mantiene para la operación diaria. |
| IA-42 | P-11 (6) | Reescribir W09 y el procedimiento de inactivación con `registrado_en`. | **Aceptar** | 428,7 → 74,3 ms; OP3 22,7 → 1,1 s; mismas 12.365 cuentas | Equivalencia verificada en los 2.000.000 de asientos. |

## 10. Repetición en PostgreSQL 18.6 (PC del equipo)

Se ejecutó el mismo procedimiento en el computador del equipo (Windows, PostgreSQL 18.6, SQL Shell): `g7_workload.sql` → `g7_aplicar.sql` → `g7_workload.sql`. Los archivos `g7_explain_antes.csv` y `g7_explain_despues.csv` del repositorio son los de esa ejecución.

| ID | Antes (ms) | Después (ms) | Mejora | Buffers antes → después | Igual que en PG16 |
|---|---|---|---|---|---|
| OP1 Retiro en caja | 198,9 | **2,42** | **× 82** | — | Sí (× 81) |
| OP2 Consignación en caja | 1,82 | 2,54 | +0,7 ms | — | Ver nota 1 |
| OP3 Inactivación (4.018 cuentas) | 51.922 | **5.363** | **× 9,7** | — | Sí (× 20,7) |
| W01 Límite diario | 68,9 | 0,010 | × 6.888 | 16.889 → 4 | Sí |
| W02 Extracto mensual | 106,9 | 0,021 | × 5.090 | 20.822 → 28 | Sí |
| W03 Saldo según ledger | 88,4 | 0,051 | × 1.734 | 20.801 → 106 | Sí |
| W04 Historial de la cuenta | 68,2 | 0,076 | × 897 | 16.965 → 112 | Sí |
| W05 Cuentas de un cliente | 5,7 | 0,020 | × 287 | 476 → 38 | Sí |
| W06 Último evento | 3,7 | 0,007 | × 530 | 1.217 → 4 | Sí |
| W07 Ajustes pendientes | 57,9 | 0,021 | × 2.758 | 16.889 → 47 | Sí |
| W08 Cliente por documento | 0,014 | 0,015 | igual | 6 → 6 | Sí (NO crear índice) |
| W09 Cuentas sin movimiento | 241,6 | 223,6 | × 1,1 | 39.089 → 39.089 | Sí (índice solo: no concluyente) |
| W09R W09 reescrita | 123,3 | 61,0 | × 4,0 frente a W09 antes | 22.200 → 132.169 | Sí |
| W10 Movimientos atípicos | 2.967 | 3.548 | × 0,8 (regresión) | 20.801 → 1.277.467 | Sí, pero menor (+20 % en vez de +105 %) |
| W10S W10 sin index scan | 2.996 | 3.838 | — | 20.801 → 20.801 | Ver nota 2 |

Lo que se confirma en PostgreSQL 18:

- **Los planes son los mismos:** los mismos índices se usan en las mismas consultas, con los mismos buffers.
- **Las mejoras críticas también:** el retiro es 82 veces más rápido y W01–W07 bajan a centésimas de milisegundo.
- **La regresión de W10 también aparece:** el planificador cambia al `Index Scan` de IX-3 y lee 1.277.467 buffers.

Notas:

1. **OP2:** en este PC la consignación subió 0,7 ms (de 1,8 a 2,5 ms). Puede ser el costo de actualizar los índices nuevos en cada escritura, o variación entre ejecuciones (en PG16 no se notó). Aun así, una consignación sigue tardando 2,5 ms.
2. **W10S:** usa exactamente el mismo plan que W10 antes (Seq Scan, 20.801 buffers, costo ≈ 262.000), pero en esta ejecución tardó 3,8 s frente a 3,0 s. Como el plan y las lecturas son idénticos, la diferencia es variación del equipo (otros programas abiertos, temperatura). Aquí W10 y W10S quedan entre 3,0 y 3,8 s, así que la mitigación resulta **no concluyente** en este PC: la regresión es pequeña (+20 %). La decisión de la sección 5 no cambia: no hay índice que sirva a W10, y si el reporte llega a molestar, se corre con `enable_indexscan = off` o en una réplica.
