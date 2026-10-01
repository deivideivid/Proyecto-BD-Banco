# Guía de defensa técnica

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G8 — Cierre, evidencia y defensa** |
| Criterio de la guía | "El estudiante puede justificar el modelo, demostrar gates y explicar dónde la IA se equivocó o fue mejorada." Defensa oral: **3 decisiones de diseño y 2 errores descubiertos**. |
| Demostración en vivo | [`sql/tests/g8_demo_defensa.sql`](../sql/tests/g8_demo_defensa.sql): 8 demostraciones en unos 5 minutos, sin dejar cambios en la base |
| Documentos de apoyo | [`informe_final.pdf`](informe_final.pdf) · [`matriz_ia.md`](matriz_ia.md) · [`erd_final.png`](erd_final.png) |

## 1. Guion sugerido (12–15 minutos)

| Minuto | Qué se presenta | Apoyo |
|---|---|---|
| 0–2 | El problema y cómo se trabajó: gates G0–G8, "IA propone → PostgreSQL ejecuta → las pruebas deciden" | Informe, sección 1 |
| 2–4 | El modelo: 5 esquemas, 28 tablas, 42 FK; el ERD sale del catálogo, así que coincide con el DDL | `erd_final.png` |
| 4–8 | **3 decisiones de diseño** (sección 2) | Demos 1 a 5 |
| 8–11 | **2 errores descubiertos** (sección 3) | G6 antes/después y G7 EXPLAIN (demo 7) |
| 11–13 | Uso de la IA: 46 decisiones; 27 no se aceptaron tal cual | `matriz_ia.md` |
| 13–15 | Preguntas | Sección 4 |

Antes de la defensa:

1. Reconstruir la base con `\i sql/g8_reconstruir_todo.sql`. Debe terminar en **G8 RECONSTRUCCIÓN = PASS**.
2. Ensayar `\i sql/tests/g8_demo_defensa.sql`. Los `ERROR` de las demos 1, 5, 6 y 8 son **esperados**: son la base de datos protegiéndose.

## 2. Tres decisiones de diseño

### Decisión 1 · El ledger de doble partida es la fuente de verdad; el saldo es una caché que se reconcilia

- **Qué se hizo:**
  - Cada transacción POSTED genera exactamente 2 asientos (débito y crédito del mismo valor).
  - El saldo de la cuenta se actualiza **desde los asientos recién creados** (`fin.fn_aplicar_saldos`), nunca por otro camino (DM-05, DC-04).
  - Unos triggers diferidos verifican el cuadre al confirmar (RN-46, RN-47).
- **Alternativa descartada:** guardar solo el saldo en la cuenta. Es más simple, pero no permite reconciliar ni auditar de dónde sale cada peso.
- **Por qué:** en un banco, el saldo tiene que poder reconstruirse a partir de los movimientos. Guardar el saldo también en la cuenta es una redundancia **controlada** (desnormalización D-01): hace rápidas las operaciones y se verifica contra el ledger.
- **Evidencia:**
  - **Demo 2:** 1.000.000 de POSTED y 0 descuadradas.
  - **Demo 3:** 50.000 cuentas con diferencia 0,00.
  - **G6:** pruebas F01, S01 y S02.
  - **Prueba de las pruebas de G6:** al alterar un saldo a mano, S01 lo detecta.

### Decisión 2 · El dinero solo se mueve con funciones seguras: bloqueo ordenado e idempotencia

- **Qué se hizo:** las 17 operaciones son funciones `SECURITY DEFINER` con `search_path` fijo. Ningún rol de la aplicación puede hacer INSERT, UPDATE ni DELETE sobre las tablas de dinero (DC-01). Cada función:
  - valida el permiso del empleado;
  - bloquea las cuentas con `FOR UPDATE` **en orden de `cuenta_id`** (DC-03);
  - valida estado, fondos y límite;
  - registra la doble partida en **una sola sentencia** (atómica).

  La clave de idempotencia `UNIQUE` + `ON CONFLICT` evita duplicados (DM-08).
- **Alternativas descartadas:**
  - Dar permisos de escritura a la aplicación y validar en el código.
  - Usar `SERIALIZABLE`, que obliga a reintentar.
  - Detectar duplicados por monto y fecha.
- **Por qué:** la regla vive donde no se puede saltar. El bloqueo ordenado evita el doble retiro y los interbloqueos sin reintentos.
- **Evidencia:**
  - **Pruebas de concurrencia CT-1 a CT-4 (G3):** doble retiro, transferencias cruzadas, doble clic y doble reverso.
  - **Demo 4:** dos envíos dan 1 transacción.
  - **Demo 5:** una transferencia fallida deja 0 transacciones nuevas y el saldo sin cambios.
  - **Demo 8 y RBAC de G7:** 23/23 pruebas.

### Decisión 3 · El estado de la cuenta cambia solo con eventos y las transiciones válidas son datos

- **Qué se hizo:**
  - `evento_cuenta` registra creación, activación, bloqueo, cierre e inactivación, separado de las transacciones de dinero (DM-03).
  - Las transiciones permitidas están en la tabla `ref.transicion_estado_cuenta`, con una FK compuesta (DM-04).
  - Un trigger impide cambiar el estado, el límite o la fecha de cierre de la cuenta si no es a través de un evento (DC-05, `pg_trigger_depth`).
- **Alternativa descartada:** cambiar `estado_cuenta` directamente con UPDATE y validar las transiciones con código.
- **Por qué:**
  - Queda la historia completa de cada cuenta: quién la bloqueó, cuándo y por qué.
  - La base rechaza sola una transición inválida.
  - Agregar una transición nueva es un INSERT, no un cambio de código.
- **Evidencia:**
  - **G3:** pruebas T33, T34 y T37.
  - **G6:** S03 (estado = último evento) y T05 (estado anterior coherente) en las 50.000 cuentas.
  - **G7:** el índice IX-5 se justificó precisamente por el trigger de eventos.

**Decisiones de reserva**, por si preguntan por otras:

- Supertipo `cliente` con subtipos (DM-01): `INHERITS` no propaga UNIQUE ni FK.
- 6 índices, cada uno con su EXPLAIN (G7).
- `NUMERIC` para el dinero, nunca `FLOAT` ni `money` (IA-10).

## 3. Dos errores descubiertos

### Error 1 · La carga masiva dejó 3,2 millones de filas sin rastro en la auditoría (G6)

- **Qué pasó:** en G3 la IA propuso, y el equipo aceptó, cargar los lotes con los triggers desactivados, para no escribir millones de filas de auditoría (DC-07). Nadie notó la consecuencia: la auditoría no podía decir quién cargó los datos, cuándo ni cuántas filas.
- **Cómo se descubrió:** el quality gate de G6 se ejecutó **sin corregir nada primero**. La prueba A04 dio FAIL (severidad ALTA): 7 tablas sin registro de carga.
- **Corrección:** `registrar_cargas_en_auditoria.sql` deja una fila por tabla con usuario, hora, archivo y número de filas. Los scripts de carga ahora lo hacen solos. Se repitió el gate: A04 = PASS; Auditability pasó de 85 a 100 y el puntaje general de 98,3 a 99,6.
- **Lección:** una decisión de rendimiento puede romper un requisito de auditoría. El gate lo encontró porque mide resultados, no intenciones. Matriz: IA-32.

### Error 2 · Cada retiro recorría el millón de transacciones con la cuenta bloqueada, y la IA apuntaba a otro lado (G7)

- **Qué pasó:** en G5 la IA señaló como candidatas a índice las 5 consultas más lentas: reportes de 0,5 a 1 s.
- **Cómo se descubrió:** el `EXPLAIN (ANALYZE, BUFFERS)` de G7 mostró otra cosa. El cuello de botella real estaba **dentro de `fn_retirar`**: la suma de retiros del día (RN-37) hacía un `Seq Scan` de 1.024.178 filas, unos 132 MB, para encontrar 1, y **con la cuenta bloqueada**. En el PC del equipo, un retiro tardaba 198,9 ms.
- **Corrección:** un índice `(cuenta_origen_id, fecha_contable)`. El retiro bajó a **2,4 ms (× 82)**. Para los reportes, en cambio, la decisión fue **no crear índice**: leen casi toda la tabla.
- **Además, un índice tiene efectos secundarios:** el índice del extracto hizo que el reporte A06 pasara de 3,0 a 3,5 s en PG18 (y de 1,3 a 2,8 s en PG16), porque el planificador lo eligió por un costo estimado menor. Se documentó y se mitigó solo en ese reporte.
- **Lección:** hay que medir dónde está el problema real antes de optimizar. Matriz: IA-37 a IA-41.

**Errores de reserva:**

- **IA-24:** el generador dejó 482 movimientos en cuentas que se iban a inactivar; lo detectó la validación del lote 2.
- **IA-29:** comparaba con el límite actual y no con el vigente ese día; el resultado mostraba días "al 180 %".
- **IA-45:** tildes dañadas por la codificación de SQL Shell en Windows.

## 4. Las 8 preguntas de defensa de la guía

**1. ¿Qué regla crítica decidió implementar en PostgreSQL y no solo en la aplicación? ¿Por qué?**
La doble partida y la inmutabilidad de lo contabilizado (RN-40, RN-46, RN-47): triggers diferidos de cuadre y triggers que impiden UPDATE, DELETE y TRUNCATE incluso al dueño de la base. También el límite diario y los fondos, validados dentro de la función con la cuenta bloqueada. Si estas reglas vivieran solo en la aplicación, cualquier conexión directa, un script de carga o un error de programación podría dejar el ledger descuadrado. *Demo 1 y demo 2.*

**2. ¿Cómo garantiza que una transferencia no quede ejecutada parcialmente?**
`fin.fn_transferir` es **una sola sentencia SQL**: bloquea las dos cuentas en orden, valida, inserta la transacción y los 2 asientos y aplica los saldos. Si cualquier paso falla, PostgreSQL deshace todo (atomicidad, RN-39). Además, los triggers diferidos revisan el cuadre al confirmar. *Demo 5: la transferencia fallida deja 0 transacciones nuevas y el saldo igual. Prueba T06 de G3.*

**3. ¿Qué problema resuelve la idempotencia en un sistema financiero?**
El doble procesamiento: el cliente da doble clic, la red reintenta o se cae la conexión justo después de enviar. Cada solicitud trae una `idempotency_key` única. Si llega repetida, se devuelve la misma transacción en vez de crear otra; si llega la misma clave con otros datos (otro `hash_solicitud`), se rechaza con BA015. *Demo 4. Prueba concurrente CT-3: dos sesiones simultáneas reciben el mismo `transaccion_id`.*

**4. ¿Por qué una transacción contabilizada debería ser inmutable?**
Es un registro contable y legal. Si se pudiera editar, se perdería la trazabilidad y el ledger dejaría de cuadrar con los saldos. Los errores se corrigen con un **reverso**: una nueva transacción que referencia a la original y deja las dos a la vista (RN-41). Solo se permite un reverso por transacción (`UNIQUE`, RN-42). *Demo 1. Pruebas T05a–d y T07 de G3.*

**5. ¿Qué evidencia demuestra que sus índices son útiles?**
`EXPLAIN (ANALYZE, BUFFERS)` antes y después de 10 consultas y 3 operaciones reales, en PostgreSQL 16 y 18. Ejemplo: el límite diario pasó de `Seq Scan` con 16.889 buffers a `Index Scan` con 4, y el retiro completo de 198,9 a 2,4 ms. También se midió el costo:

- **Almacenamiento:** 86 MB.
- **Carga masiva:** +16 s.
- **Lo que empeoró:** el reporte A06.

En 3 casos la decisión fue **no** crear índice. *Demo 7. `evidence/g7_explain.md`.*

**6. ¿Cómo detectó que sus datos sintéticos eran demasiado uniformes o poco realistas?**
Con el perfil de 48 métricas de G4 y las pruebas de distribución D01–D05 de G6. Algunos resultados:

| Métrica | Resultado |
|---|---|
| Departamento más grande frente al promedio | 9,6 veces |
| Cuentas por cliente | mediana 3, máximo 300 |
| Hora pico frente a hora valle | 22,7 veces |
| Montos | mediana < promedio (sesgados) |
| Cuentas activas | 87 % |

La validación también detectó errores del generador (IA-24): 482 movimientos en el periodo previo a una inactivación y **0 rechazos por límite diario**, algo poco realista. Se corrigió y se agregaron intentos que exceden el límite.

**7. ¿Qué recomendación de la IA rechazó y qué evidencia sustentó su decisión?**
Indexar los reportes lentos (IA-37). El EXPLAIN mostró que leen casi toda la tabla y que un índice incluso puede empeorarlos: A06 pasó de 3,0 a 3,5 s en PG18. Otras:

- Montar la base en Supabase gratis (IA-26): 475 MB contra un límite de 500 MB, sin espacio para los índices.
- El índice cubriente para corregir la regresión (IA-39): +54 % de tamaño y ninguna mejora.

En total, 27 de 46 recomendaciones no se aceptaron tal cual (`docs/matriz_ia.md`).

**8. ¿Qué cambiaría si el sistema pasara de 1 millón a 100 millones de movimientos?**

- **Particionar** `transaccion_financiera` y `asiento_contable` por mes de `fecha_contable` (particionado declarativo). Las consultas por periodo leerían solo sus particiones y las antiguas se podrían archivar.
- **Índices BRIN** por fecha para los reportes. Son diminutos porque los datos se insertan en orden de tiempo.
- **Réplica de lectura** para los reportes y la analítica (como W10), y **vistas materializadas** para los agregados mensuales.
- **Cargas masivas** creando los índices después de cargar.
- **Configuración:** ajustar `shared_buffers`, `work_mem` y `autovacuum` para tablas que solo reciben INSERT.
- **Conexiones:** un pool como PgBouncer.

Lo que **no cambiaría**: las reglas (doble partida, inmutabilidad, idempotencia, bloqueo ordenado). Están diseñadas por fila y por cuenta, y su costo no crece con el tamaño de la tabla gracias a los índices de G7.

## 5. Checklist final del estudiante (sección 16 de la guía)

| Punto | Cumple | Evidencia |
|---|---|---|
| Puedo reconstruir la BD desde cero con los scripts del repositorio | ✔ | `sql/g8_reconstruir_todo.sql` → G8 RECONSTRUCCIÓN = PASS (`evidence/g8_reconstruccion.txt`) |
| El ERD coincide con el DDL ejecutado | ✔ | `docs/erd_final.mmd` se genera desde el catálogo (`sql/tests/g8_erd_desde_catalogo.sql`): 28 tablas, 42 FK |
| Todas las tablas críticas tienen PK y las relaciones tienen FK | ✔ | G6: DS02 = 0; 42 FK |
| No uso FLOAT/REAL para dinero | ✔ | G6: DS01 = 0 |
| Documento, NIT, número de cuenta e idempotencia sin duplicados | ✔ | G6: U01–U04 = 0 |
| Una transferencia es atómica | ✔ | G3 T06; demo 5 |
| Una transacción POSTED no se altera directamente | ✔ | G3 T05a–d; demo 1 |
| El ledger cumple débito = crédito | ✔ | G6 F01 = 100 %; demo 2 |
| No hay movimientos fuera del ciclo de vida válido de la cuenta | ✔ | G6 T01–T03 = 0 |
| Los saldos se pueden reconciliar | ✔ | G6 S01–S02 = 0; demo 3 |
| 10K clientes, 50K cuentas y 1M transacciones | ✔ | Resumen de `g8_reconstruir_todo.sql` |
| Datos sintéticos y semilla documentada | ✔ | Semilla 20260909; `docs/04_datos_sinteticos.md` |
| Las distribuciones no son artificialmente uniformes | ✔ | G4 701–710; G6 D01–D05 |
| 30 consultas verificadas | ✔ | `evidence/g5_results.md` (+ 7 validaciones cruzadas) |
| Analicé ≥ 5 planes EXPLAIN críticos | ✔ | 10 consultas + 3 operaciones (`evidence/g7_explain.md`) |
| Probé permisos permitidos y denegados | ✔ | 23 pruebas: 8 permitidos y 15 denegados (`evidence/g7_security.md`) |
| Conservé evidencias de cada quality gate | ✔ | Carpeta `evidence/` (G0–G8) |
| Registré al menos tres decisiones de aceptar, modificar o rechazar a la IA | ✔ | 46 decisiones (`docs/matriz_ia.md`) |
| Puedo explicar qué aprendí técnicamente sin depender del LLM | — | Se demuestra en la defensa: secciones 2 a 4 de esta guía |
