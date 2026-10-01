# G6 — Data Quality e integridad: antes y después

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G6 — Data Quality e integridad** |
| Fecha | 2026-09-30 |
| Script del gate | [`sql/quality_gate.sql`](../sql/quality_gate.sql) (76 pruebas, ≈ 35 s con el millón de transacciones) |
| Corrección | [`sql/load/registrar_cargas_en_auditoria.sql`](../sql/load/registrar_cargas_en_auditoria.sql) + ajuste de `carga_lote1.sql` y `carga_lote2_transacciones.sql` |
| Prueba de las pruebas | [`sql/tests/quality_gate_defectos.sql`](../sql/tests/quality_gate_defectos.sql) (7 defectos en una copia de la base) |
| Detalle | [`g6_quality_results_antes.csv`](g6_quality_results_antes.csv) · [`g6_quality_results.csv`](g6_quality_results.csv) (después) · [`g6_defectos_results.csv`](g6_defectos_results.csv) |
| Resultado | **QUALITY_GATE = PASS** · 0 FAIL críticos · puntaje general **98,3 → 99,6** |

## 1. Resumen

1. **Antes:** se auditó la base cargada (10K clientes, 50K cuentas, 1M transacciones) **sin corregir nada**. Resultado: 0 FAIL críticos, pero **1 FAIL de severidad ALTA (A04)**: las cargas masivas no dejaron rastro en la auditoría. También hay 2 WARNING de severidad BAJA.
2. **Corrección:** se registraron las cargas en `aud.log_auditoria` (quién, cuándo, qué archivo, cuántas filas) y se ajustaron los scripts de carga para que lo hagan solos en el futuro.
3. **Después:** se repitió el gate. A04 pasó a PASS; Auditability subió de 85,0 a 100; general de 98,3 a 99,6.
4. **Prueba de las pruebas:** en una copia de la base se metieron 7 defectos a propósito. El gate detectó **los 7** y dio **QUALITY_GATE = FAIL**. Así se demuestra que el PASS de la base real no es porque las pruebas sean débiles.

## 2. Cómo se ejecuta

Desde la carpeta `lab-postgresql-banco-ia`, con la base ya cargada:

```
psql -U postgres -d banco_andino_lab -f sql/quality_gate.sql                  -- el gate (guarda evidence/g6_quality_results.csv)
psql -U postgres -d banco_andino_lab -f sql/load/registrar_cargas_en_auditoria.sql   -- solo en bases cargadas antes de G6
psql -U postgres -d postgres         -f sql/tests/quality_gate_defectos.sql   -- prueba de las pruebas (sobre una copia)
```

Cada prueba devuelve `test_id | categoría | dimensión | regla | tabla | esperado | obtenido | severidad | resultado | detalle`, como pide el Prompt 5.

**Puntajes** (solo con pruebas ejecutadas):

- Peso por severidad: CRITICA 4 · ALTA 3 · MEDIA 2 · BAJA 1.
- Valor por resultado: PASS 1 · WARNING 0,5 · FAIL 0.
- Puntaje = 100 × Σ(peso × valor) / Σ(peso), por dimensión y general.
- **QUALITY_GATE = FAIL** si falla cualquier prueba CRITICA (todas las financieras, referenciales, de unicidad crítica y temporales imposibles son CRITICA).

## 3. Qué evalúa el gate (76 pruebas)

| Categoría (Prompt 5) | Dimensión | Pruebas | CRITICA | ALTA | MEDIA | BAJA | Ejemplos |
|---|---|---|---|---|---|---|---|
| Completitud | Data Quality | 6 | 2 | 3 | – | 1 | campos críticos del cliente, POSTED sin fecha, REJECTED sin motivo |
| Unicidad | Data Quality | 7 | 5 | 1 | – | 1 | documento, NIT, número de cuenta, idempotencia, doble reverso |
| Integridad referencial | Integrity | 7 | 6 | 1 | – | – | titularidades, asientos, transacciones y eventos huérfanos; subtipo RN-02 |
| Validez | Data Quality | 6 | 1 | 3 | 1 | 1 | montos, dígito de verificación del NIT, mayoría de edad, celulares |
| Consistencia geográfica | Data Quality | 3 | – | 2 | – | 1 | código de municipio vs. departamento (DIVIPOLA) |
| Consistencia temporal | Data Quality | 8 | 4 | 2 | 2 | – | movimientos fuera de apertura/cierre, débitos en cuentas no activas |
| Consistencia financiera | Integrity | 7 | 7 | – | – | – | Σ débitos = Σ créditos, sobregiro, límite diario vigente, reversos |
| Reconciliación de saldos | Integrity | 5 | 2 | 2 | 1 | – | saldo guardado = ledger por cuenta y por cuenta contable |
| Reglas de negocio | Integrity | 8 | 1 | 6 | 1 | – | ajustes con aprobación, reversos de supervisor, conflicto de interés |
| Distribuciones | Data Quality | 5 | – | – | 5 | – | geografía, cuentas por cliente, hora, montos, estados |
| Diseño | Database Design | 8 | 1 | 4 | 1 | 2 | dinero en NUMERIC, PK, SECURITY DEFINER, permisos de escritura |
| Auditoría | Auditability | 6 | 2 | 4 | – | – | triggers activos, inmutabilidad, cargas con rastro |
| **Total** | | **76** | **31** | **28** | **11** | **6** | |

## 4. Antes: hallazgos (sin corregir)

| Test | Severidad | Regla | Obtenido | Resultado |
|---|---|---|---|---|
| **A04** | ALTA | Cargas masivas sin rastro en la auditoría | 7 tablas sin registro (usuario, cliente, cuenta, titularidad_cuenta, evento_cuenta, transaccion_financiera, asiento_contable) | **FAIL** |
| C04 | BAJA | Clientes sin correo electrónico (campo opcional) | 7,1 % (714 de 10.000); umbral 5 % | WARNING |
| DS05 | BAJA | Claves foráneas sin índice que las soporte | 34 | WARNING |

Las otras 73 pruebas dieron PASS, incluidas las 31 críticas: 0 duplicados, 0 huérfanos, 100 % del ledger balanceado (1.000.000 de POSTED), 0 diferencias de saldo en 50.000 cuentas.

**Por qué falló A04.** En G3 se decidió (DC-07) cargar los lotes con los triggers desactivados, para no escribir 3 millones de filas de auditoría ni pagar las validaciones fila a fila. La consecuencia, que la IA no advirtió en su momento, es que las 3,2 millones de filas cargadas **no tenían ningún rastro**: la auditoría no podía responder quién cargó los datos, cuándo ni cuántas filas. Eso incumple "operaciones críticas reconstruibles".

## 5. Corrección

| Hallazgo | Acción | Archivo |
|---|---|---|
| A04 | Se deja **una fila de auditoría por tabla cargada** con el usuario de base de datos, la hora, el lote, el archivo CSV y el número de filas; y una fila `UPDATE` para el recálculo masivo de saldos del lote 2. Es idempotente: si ya existe, no la repite. | `sql/load/registrar_cargas_en_auditoria.sql` |
| A04 (a futuro) | Los dos scripts de carga llaman al script anterior al terminar, así cualquier reconstrucción queda auditada sola. En la base existente los registros quedan marcados `registro_retroactivo = true`; en una carga nueva, `false`. | `sql/load/carga_lote1.sql`, `sql/load/carga_lote2_transacciones.sql` |

Resultado del registro (15 filas en `aud.log_auditoria`):

| Lote | Tabla | Operación | Filas |
|---|---|---|---|
| lote1 | ref.departamento · ref.municipio · ref.oficina | INSERT | 33 · 51 · 87 |
| lote1 | seg.usuario · seg.usuario_rol | INSERT | 269 · 269 |
| lote1 | core.cliente · persona_natural · persona_juridica | INSERT | 10.000 · 8.500 · 1.500 |
| lote1 | core.cuenta · titularidad_cuenta · evento_cuenta · cambio_limite | INSERT | 50.000 · 51.551 · 112.145 · 3.018 |
| lote2 | fin.transaccion_financiera · fin.asiento_contable | INSERT | 1.024.178 · 2.000.000 |
| lote2 | core.cuenta (recálculo de saldos) | UPDATE | 37.884 cuentas con saldo |

Se verificó también desde cero: base nueva → `run_all.sql` (49/49 PASS) → lote 1 → lote 2. Los scripts de carga dejaron los 15 registros solos (con `registro_retroactivo = false`) y los controles de carga siguieron en PASS.

### Hallazgos que se aceptan sin corregir (documentados)

| Test | Decisión | Justificación |
|---|---|---|
| C04 | **Aceptar como WARNING** | El correo es opcional en el modelo (G1). Inventar correos para pasar la prueba sería crear datos falsos. Recomendación: campaña de actualización de datos para los 714 clientes. |
| DS05 | **Aplazar a G7** | No es un error de integridad: las 34 FK sin índice solo afectan la velocidad de joins y borrados. La guía pide crear índices **solo si una consulta los justifica** con `EXPLAIN (ANALYZE, BUFFERS)`; se evalúan en G7 con las consultas lentas de G5 para no sobreindexar. |

## 6. Después: puntajes

| Dimensión | Pruebas | Antes (PASS / WARN / FAIL) | Puntaje antes | Después (PASS / WARN / FAIL) | Puntaje después |
|---|---|---|---|---|---|
| Data Quality | 35 | 34 / 1 / 0 | 99,5 | 34 / 1 / 0 | 99,5 |
| Database Design | 8 | 7 / 1 / 0 | 97,5 | 7 / 1 / 0 | 97,5 |
| Integrity | 27 | 27 / 0 / 0 | 100,0 | 27 / 0 / 0 | 100,0 |
| Auditability | 6 | 5 / 0 / 1 | 85,0 | **6 / 0 / 0** | **100,0** |
| **OVERALL** | **76** | 73 / 2 / 1 | **98,3** | **74 / 2 / 0** | **99,6** |
| **Veredicto** | | 0 FAIL críticos | QUALITY_GATE = PASS | 0 FAIL críticos | **QUALITY_GATE = PASS** |

## 7. Prueba de las pruebas: 7 defectos inyectados

Un gate que siempre da PASS no demuestra nada. Por eso `sql/tests/quality_gate_defectos.sql` copia la base (`CREATE DATABASE banco_andino_qg TEMPLATE banco_andino_lab`), mete 7 defectos saltándose constraints y triggers (como lo haría una carga mal hecha o un cambio manual del DBA), corre el mismo gate y borra la copia. La base real no se toca.

| Defecto | Cómo se metió | Detectado por | Estado |
|---|---|---|---|
| D1 Ledger descuadrado | +1.000 en una línea de asiento | F01, S01, S02 (FAIL) | DETECTADO |
| D2 Saldo alterado a mano | +50.000 en el saldo de una cuenta, sin transacción | S01, S02 (FAIL) | DETECTADO |
| D3 Movimiento después del cierre | última transacción de una cuenta cerrada movida 10 días después del cierre | T01, T02 (FAIL) | DETECTADO |
| D4 Documento duplicado | se quitó `uq_cliente_documento` y un cliente copió el documento de otro | U01 (FAIL) | DETECTADO |
| D5 Titularidad huérfana | se quitó la FK y se agregó un titular inexistente (cliente 999999) | R01, N02 (FAIL) | DETECTADO |
| D6 Persona sin nombre | `nombres = ''` en una persona natural | C02 (FAIL) | DETECTADO |
| D7 Auditoría apagada | se desactivó `trg_auditar_cliente` | A01 (FAIL) | DETECTADO |

Resultado en la copia: **10 FAIL (8 críticos) → QUALITY_GATE = FAIL**; puntaje general 83,5 (Integrity 80,0 · Auditability 80,0 · Data Quality 84,7). Detalle en `g6_defectos_results.csv`.

## 8. Verificación del gate G6

| Gate mínimo de la guía | Resultado | Pruebas |
|---|---|---|
| Completitud: 100 % en campos críticos | **Cumple** | C01, C02, C03, C05, C06 = 0 |
| Unicidad: 0 duplicados críticos (documento, NIT, cuenta, idempotencia) | **Cumple** | U01–U04, U07 = 0 |
| Integridad referencial: 0 huérfanos | **Cumple** | R01–R07 = 0 |
| Validez: 0 valores imposibles críticos | **Cumple** | V01–V06 = 0 |
| Temporal: 0 transacciones fuera del ciclo de vida | **Cumple** | T01–T08 = 0 |
| Financiera: 100 % del ledger balanceado | **Cumple** | F01 = 100,0000 % de 1.000.000 POSTED |
| Saldos: reconciliación sin diferencia no explicada | **Cumple** | S01 = 0 cuentas · diferencia 0,00; S02 = 0 |
| Distribución: sin uniformidad artificial | **Cumple** | D01–D05 PASS |
| Auditoría: operaciones críticas reconstruibles | **Cumple después de corregir** | A04 FAIL → PASS |
| Scores solo desde pruebas ejecutadas; FAIL si falla una crítica | **Cumple** | Sección 2 y prueba de defectos (sección 7) |
| No corregir en silencio: evidenciar, luego recomendar | **Cumple** | Antes (sección 4) → corrección (sección 5) → después (sección 6) |
| Evidencia mínima: `sql/quality_gate.sql` + `evidence/g6_quality_before_after.md` | **Cumple** | Este documento |

**QUALITY GATE G6 = PASS**

## 9. Matriz IA: nuevas entradas de G6

| ID | Prompt | Recomendación o resultado de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-32 | P-07 (2B) / P-10 (5) | En G3 la IA propuso cargar con los triggers desactivados (DC-07) sin advertir que así las cargas no quedaban auditadas. | **Modificar** | A04 = FAIL (7 tablas sin rastro) | Se mantiene la carga rápida, pero ahora cada carga deja su registro en `aud.log_auditoria`: A04 = PASS. |
| IA-33 | P-10 (5) | Umbral de 5 % para clientes sin correo. | **Aceptar como WARNING** | C04 = 7,1 % | Campo opcional; no se inventan correos. Se recomienda actualización de datos. |
| IA-34 | P-10 (5) | Prueba de FK sin índice (34 casos). | **Aplazar a G7** | DS05 = WARNING | Solo se crean índices con una consulta que los justifique en `EXPLAIN`; evita sobreindexar. |
| IA-35 | P-10 (5) | Validar el gate metiendo defectos en una copia de la base. | **Aceptar** | 7/7 defectos detectados; QUALITY_GATE = FAIL en la copia | Demuestra que las pruebas sí detectan errores. |
| IA-36 | P-10 (5) | Primera versión de la prueba de defectos: corría el gate tal cual y sobrescribía `evidence/g6_quality_results.csv` con los resultados de la copia dañada. | **Corregir** | Revisión del equipo antes de ejecutar | Se agregó la variable `qg_sin_csv`; la prueba de defectos guarda su propio archivo (`g6_defectos_results.csv`). |

## Anexo · Las 76 pruebas (obtenido antes → después)

| Test | Categoría | Regla | Severidad | Esperado | Obtenido | Resultado final |
|---|---|---|---|---|---|---|
| C01 | Completitud | Campos críticos vacíos en cliente (documento, municipio, vinculación) | CRITICA | 0 | 0 → 0 | PASS |
| C02 | Completitud | Nombres o apellidos vacíos en personas naturales | ALTA | 0 | 0 → 0 | PASS |
| C03 | Completitud | Razón social o actividad económica vacías en personas jurídicas | ALTA | 0 | 0 → 0 | PASS |
| C04 | Completitud | Clientes sin correo electrónico (campo opcional) | BAJA | ≤ 5 % | 7.1 % → 7.1 % | **WARNING** |
| C05 | Completitud | Transacciones POSTED sin fecha contable o de contabilización | CRITICA | 0 | 0 → 0 | PASS |
| C06 | Completitud | Transacciones REJECTED sin motivo (RN-45) | ALTA | 0 | 0 → 0 | PASS |
| U01 | Unicidad | Documentos de cliente duplicados (RN-01) | CRITICA | 0 | 0 → 0 | PASS |
| U02 | Unicidad | NIT duplicados | CRITICA | 0 | 0 → 0 | PASS |
| U03 | Unicidad | Números de cuenta duplicados (RN-11) | CRITICA | 0 | 0 → 0 | PASS |
| U04 | Unicidad | Claves de idempotencia duplicadas (RN-38) | CRITICA | 0 | 0 → 0 | PASS |
| U05 | Unicidad | Usuarios internos con login o documento duplicado | ALTA | 0 | 0 → 0 | PASS |
| U06 | Unicidad | Posibles personas repetidas (mismo nombre, apellidos y fecha de nacimiento) | BAJA | 0 | 0 → 0 | PASS |
| U07 | Unicidad | Transacciones reversadas más de una vez (RN-42) | CRITICA | 0 | 0 → 0 | PASS |
| R01 | Integridad referencial | Titularidades con cliente o cuenta inexistente | CRITICA | 0 | 0 → 0 | PASS |
| R02 | Integridad referencial | Asientos sin transacción o con cuenta inexistente | CRITICA | 0 | 0 → 0 | PASS |
| R03 | Integridad referencial | Transacciones con cuenta origen/destino o usuario inexistente | CRITICA | 0 | 0 → 0 | PASS |
| R04 | Integridad referencial | Eventos de cuenta huérfanos | CRITICA | 0 | 0 → 0 | PASS |
| R05 | Integridad referencial | Clientes sin subtipo o con los dos (RN-02) | CRITICA | 0 | 0 → 0 | PASS |
| R06 | Integridad referencial | Cuentas no cerradas sin titular principal vigente (RN-13) | CRITICA | 0 | 0 → 0 | PASS |
| R07 | Integridad referencial | Claves foráneas o CHECK sin validar (NOT VALID) | ALTA | 0 | 0 → 0 | PASS |
| V01 | Validez | Montos ≤ 0 o con más de 2 decimales (RN-30) | CRITICA | 0 | 0 → 0 | PASS |
| V02 | Validez | NIT con dígito de verificación incorrecto (RN-04) | ALTA | 0 | 0 → 0 | PASS |
| V03 | Validez | Titulares naturales menores de 18 años al abrir (RN-08) | ALTA | 0 | 0 → 0 | PASS |
| V04 | Validez | Fechas de nacimiento imposibles (futuras o edad > 110 años) | MEDIA | 0 | 0 → 0 | PASS |
| V05 | Validez | Teléfonos que no son celulares colombianos de 10 dígitos | BAJA | 0 | 0 → 0 | PASS |
| V06 | Validez | Saldo retenido negativo o mayor que el saldo contable positivo | ALTA | 0 | 0 → 0 | PASS |
| G01 | Geográfica | Municipios cuyo código no empieza por el del departamento (RN-07) | ALTA | 0 | 0 → 0 | PASS |
| G02 | Geográfica | Clientes u oficinas en municipios fuera del catálogo DIVIPOLA | ALTA | 0 | 0 → 0 | PASS |
| G03 | Geográfica | Departamentos del catálogo sin ningún municipio | BAJA | 0 | 0 → 0 | PASS |
| T01 | Temporal | Movimientos antes de la apertura o después del cierre (RN-36) | CRITICA | 0 | 0 → 0 | PASS |
| T02 | Temporal | Débitos de cuentas que no estaban ACTIVAS (RN-34) | CRITICA | 0 | 0 → 0 | PASS |
| T03 | Temporal | Créditos a cuentas que no estaban ACTIVAS ni BLOQUEADAS (RN-35) | CRITICA | 0 | 0 → 0 | PASS |
| T04 | Temporal | Primer evento distinto de CREACION (RN-23) | ALTA | 0 | 0 → 0 | PASS |
| T05 | Temporal | Eventos cuyo estado anterior no es el estado previo real de la cuenta | ALTA | 0 | 0 → 0 | PASS |
| T06 | Temporal | Fecha contable distinta del día de contabilización (hora Colombia) | MEDIA | 0 | 0 → 0 | PASS |
| T07 | Temporal | Reversos registrados antes de la transacción original | CRITICA | 0 | 0 → 0 | PASS |
| T08 | Temporal | Cuentas abiertas antes de la vinculación del titular | MEDIA | 0 | 0 → 0 | PASS |
| F01 | Financiera | Transacciones POSTED cuadradas: Σ débitos = Σ créditos (RN-47) | CRITICA | 100 % | 100.0000 % → 100.0000 % | PASS |
| F02 | Financiera | Transacciones REJECTED o PENDING con asientos (RN-45) | CRITICA | 0 | 0 → 0 | PASS |
| F03 | Financiera | Momentos con saldo por debajo del cupo de sobregiro (RN-31) | CRITICA | 0 | 0 → 0 | PASS |
| F04 | Financiera | Cuentas CERRADAS con saldo (RN-20) | CRITICA | 0 | 0 → 0 | PASS |
| F05 | Financiera | Cuenta-día con retiros por encima del límite vigente (RN-37) | CRITICA | 0 | 0 → 0 | PASS |
| F06 | Financiera | Transferencias a la misma cuenta o entre monedas distintas (RN-32, RN-33) | CRITICA | 0 | 0 → 0 | PASS |
| F07 | Financiera | Reversos con monto o cuentas distintos de la original (RN-41) | CRITICA | 0 | 0 → 0 | PASS |
| S01 | Reconciliación | Saldo almacenado = saldo según el ledger en cada cuenta (RN-48) | CRITICA | 0 diferencias | 0 cuentas · diferencia total 0.00 → 0 cuentas · diferencia total 0.00 | PASS |
| S02 | Reconciliación | Σ saldos por cuenta contable y moneda = Σ del ledger | CRITICA | 0 diferencias | 0 → 0 | PASS |
| S03 | Reconciliación | Estado de la cuenta distinto de su último evento (RN-25) | ALTA | 0 | 0 → 0 | PASS |
| S04 | Reconciliación | Límite diario distinto del último cambio registrado (RN-27) | ALTA | 0 | 0 → 0 | PASS |
| S05 | Reconciliación | Fecha de cierre distinta del evento CIERRE | MEDIA | 0 | 0 → 0 | PASS |
| N01 | Reglas de negocio | Producto no permitido para el tipo de titular (RN-14, RN-15) | ALTA | 0 | 0 → 0 | PASS |
| N02 | Reglas de negocio | Cuentas con más titulares vigentes que el máximo del producto (RN-16) | ALTA | 0 | 0 → 0 | PASS |
| N03 | Reglas de negocio | Cupo de sobregiro fuera de cuentas CORRIENTE (RN-17) | ALTA | 0 | 0 → 0 | PASS |
| N04 | Reglas de negocio | Ajustes POSTED sin aprobación de otro SUPERVISOR (RN-44) | CRITICA | 0 | 0 → 0 | PASS |
| N05 | Reglas de negocio | Reversos registrados por usuarios sin rol SUPERVISOR (RN-51) | ALTA | 0 | 0 → 0 | PASS |
| N06 | Reglas de negocio | Usuarios que operaron cuentas de las que son titulares (RN-54) | ALTA | 0 | 0 → 0 | PASS |
| N07 | Reglas de negocio | Desbloqueos, cierres o cambios de límite sin SUPERVISOR (RN-28) | ALTA | 0 | 0 → 0 | PASS |
| N08 | Reglas de negocio | Bloqueos sin motivo (RN-29) | MEDIA | 0 | 0 → 0 | PASS |
| D01 | Distribución | Clientes por departamento no uniformes | MEDIA | mayor / promedio > 3 | 9.6 → 9.6 | PASS |
| D02 | Distribución | Cuentas por cliente con cola larga | MEDIA | máximo / mediana ≥ 10 | 100.0 → 100.0 | PASS |
| D03 | Distribución | Patrón horario de transacciones | MEDIA | pico / valle ≥ 5 | 22.7 → 22.7 | PASS |
| D04 | Distribución | Montos sesgados: mediana < promedio | MEDIA | mediana < promedio | 837000 < 1767799 → 837000 < 1767799 | PASS |
| D05 | Distribución | Mayoría de cuentas ACTIVAS y minorías en otros estados | MEDIA | ACTIVA > 50 % y 4 estados | 87.1 % activas · 4 estados → 87.1 % activas · 4 estados | PASS |
| DS01 | Diseño | Columnas float, real o money (dinero debe ser NUMERIC) | ALTA | 0 | 0 → 0 | PASS |
| DS02 | Diseño | Tablas sin clave primaria | ALTA | 0 | 0 → 0 | PASS |
| DS03 | Diseño | Tablas sin comentario (documentación en la base) | BAJA | 0 | 0 → 0 | PASS |
| DS04 | Diseño | Momentos (eventos) guardados sin zona horaria | MEDIA | 0 | 0 → 0 | PASS |
| DS05 | Diseño | Claves foráneas sin índice que las soporte | BAJA | 0 | 34 → 34 | **WARNING** |
| DS06 | Diseño | Funciones SECURITY DEFINER sin search_path fijo | ALTA | 0 | 0 → 0 | PASS |
| DS07 | Diseño | Funciones del banco ejecutables por PUBLIC | ALTA | 0 | 0 → 0 | PASS |
| DS08 | Diseño | Roles de la aplicación con escritura directa en tablas de dinero | CRITICA | 0 | 0 → 0 | PASS |
| A01 | Auditoría | Triggers de auditoría activos en las tablas críticas (RN-52) | CRITICA | 8 de 8 | 8 de 8 → 8 de 8 | PASS |
| A02 | Auditoría | Triggers de inmutabilidad activos (RN-40, RN-53) | CRITICA | 6 de 6 | 6 de 6 → 6 de 6 | PASS |
| A03 | Auditoría | Registros de auditoría incompletos (quién, qué, cuándo, registro, valores) | ALTA | 0 | 0 → 0 | PASS |
| A04 | Auditoría | Cargas masivas sin rastro en la auditoría (quién cargó, cuándo, cuántas filas) | ALTA | 0 | 7 → 0 | PASS |
| A05 | Auditoría | Transacciones sin usuario interno que las registró o con usuario sin rol | ALTA | 0 | 0 → 0 | PASS |
| A06 | Auditoría | Asignaciones de rol hechas por el mismo usuario (RN-50) | ALTA | 0 | 0 → 0 | PASS |
