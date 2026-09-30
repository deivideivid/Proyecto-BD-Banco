# G3 — Construcción en PostgreSQL

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G3 — Construcción de PostgreSQL** |
| Fecha | 2026-09-30 |
| Entrada | `docs/02_modelo_logico.md` (modelo aprobado en G2) |
| Código | `sql/00_extensions.sql` … `sql/20_teardown.sql`, `sql/run_all.sql`, `sql/tests/concurrencia/` |
| Evidencia | [`evidence/g3_tests.txt`](../evidence/g3_tests.txt) |
| Resultado | **G3 = PASS** (ver [sección 9](#9-verificación-del-gate-g3)) |

## 1. Estructura de los scripts

El DDL de G2 (`tablas_banco_andino.sql`) se dividió en los archivos numerados que pide el laboratorio y se completó con funciones, triggers, roles y pruebas.

| Archivo | Contenido |
|---|---|
| `00_extensions.sql` | Verifica PostgreSQL 16+. No se necesitan extensiones (`gen_random_uuid()` y `sha256()` son nativas). |
| `01_schemas.sql` | Esquemas `ref`, `seg`, `core`, `fin`, `aud`. |
| `02_catalogs.sql` | Catálogos, plan de cuentas contable y `ref.fn_dv_nit`. |
| `03_geography.sql` | Departamentos, municipios y oficinas. |
| `04_customers.sql` | Cliente y subtipos. |
| `05_products.sql` | Productos. |
| `06_accounts.sql` | Cuentas, titularidad, eventos y cambios de límite. |
| `07_users_security.sql` | Usuarios internos, roles y permisos de la aplicación. |
| `08_transactions.sql` | Transacciones financieras. |
| `09_ledger.sql` | Asientos contables. |
| `10_audit.sql` | Registro de auditoría. |
| `11_constraints.sql` | FK que cruza el orden de archivos (evento → usuario). |
| `12_indexes.sql` | Sin índices secundarios: se justifican en G7 con `EXPLAIN` (decisión DC-06). |
| `13_views.sql` | Vistas de reconciliación: `fin.v_balance_transaccion`, `core.v_saldo_vs_ledger`, `core.v_estado_vs_eventos`. |
| `14_functions.sql` | 29 funciones: utilidades y operaciones del negocio. |
| `15_procedures.sql` | `core.pr_inactivar_cuentas_sin_movimiento`. |
| `16_triggers.sql` | 32 triggers: inmutabilidad, doble partida, reglas de cuenta y titularidad, auditoría. |
| `17_roles_permissions.sql` | Roles de base de datos y mínimo privilegio. |
| `18_tests.sql` | 49 pruebas positivas y negativas (se deshacen al final). |
| `19_demo_queries.sql` | Reservado para G5. |
| `20_teardown.sql` | Borra el modelo. |
| `run_all.sql` | Ejecuta 20 → 00…17 → 18. **Corre dos veces seguidas sin error.** |
| `tests/concurrencia/` | Pruebas CT-0 a CT-4 con dos sesiones (ver `LEEME.md`). |

## 2. Cómo se ejecuta

Desde la carpeta `lab-postgresql-banco-ia`:

```powershell
psql -U postgres -c "CREATE DATABASE banco_andino_lab"
psql -U postgres -d banco_andino_lab -f sql/run_all.sql                       # modelo + 49 pruebas
psql -U postgres -d banco_andino_lab -f sql/load/carga_lote1.sql              # 10.000 clientes · 50.000 cuentas
psql -U postgres -d banco_andino_lab -f sql/load/carga_lote2_transacciones.sql  # 1.000.000 transacciones
```

`run_all.sql` **borra** el modelo antes de crearlo: si se vuelve a correr, hay que recargar los lotes.

## 3. Operaciones del negocio

Todas son funciones `SECURITY DEFINER` con `search_path` fijo. Reciben el usuario interno que opera (`p_usuario_id`), validan su permiso, validan precondiciones, bloquean las filas que tocan y quedan auditadas. Cada una es una sola sentencia SQL: se aplica completa o no se aplica (RN-39).

| Operación | Función | Permiso (app) | Reglas |
|---|---|---|---|
| Crear cliente natural / jurídico | `core.fn_crear_cliente_natural`, `core.fn_crear_cliente_juridico` | CLI_CREAR | RN-01 a RN-04 |
| Abrir cuenta | `core.fn_abrir_cuenta` | CTA_ABRIR | RN-08, RN-11 a RN-17, RN-23 |
| Agregar cotitular | `core.fn_agregar_titular` | CTA_ABRIR | RN-08, RN-14 a RN-16 |
| Activar | `core.fn_activar_cuenta` | CTA_ACTIVAR | RN-24, RN-25 |
| Bloquear | `core.fn_bloquear_cuenta` | CTA_BLOQUEAR | RN-24, RN-29 |
| Desbloquear | `core.fn_desbloquear_cuenta` | CTA_DESBLOQUEAR (supervisor) | RN-28 |
| Cambiar límite | `core.fn_cambiar_limite` | CTA_CAMBIAR_LIMITE (supervisor) | RN-27, RN-28 |
| Cerrar cuenta | `core.fn_cerrar_cuenta` | CTA_CERRAR (supervisor) | RN-20, RN-28 |
| Consignar | `fin.fn_consignar` | TX_CONSIGNAR | RN-30, RN-35, RN-38 |
| Retirar | `fin.fn_retirar` | TX_RETIRAR | RN-30, RN-31, RN-34, RN-37, RN-38 |
| Transferir | `fin.fn_transferir` | TX_TRANSFERIR | RN-31 a RN-35, RN-38, RN-39 |
| Reversar | `fin.fn_reversar` | TX_REVERSAR (supervisor) | RN-40 a RN-43, RN-51 |
| Crear / aprobar / rechazar ajuste | `fin.fn_crear_ajuste`, `fin.fn_aprobar_ajuste`, `fin.fn_rechazar_ajuste` | TX_AJUSTE_CREAR / TX_AJUSTE_APROBAR | RN-44, RN-51 |
| Registrar solicitud rechazada | `fin.fn_registrar_rechazo` | según el tipo | RN-45 |
| Inactivar cuentas sin movimiento | `CALL core.pr_inactivar_cuentas_sin_movimiento` | CTA_INACTIVAR (supervisor) | RN-24 |

**Errores del negocio.** Cada rechazo usa un código propio (`SQLSTATE` clase `BA`), para que la aplicación y las pruebas sepan exactamente por qué falló:

| Código | Significado | Código | Significado |
|---|---|---|---|
| BA001 | Permiso denegado | BA010 | Titularidad inválida (edad, tipo de cliente, máximo) |
| BA002 | El estado de la cuenta no lo permite | BA011 | Transición no permitida o columna controlada |
| BA003 | Fondos insuficientes | BA012 | Cierre con saldo |
| BA004 | Límite diario de retiro excedido | BA013 | Aprobación de ajuste inválida |
| BA005 | Monto inválido (≤ 0 o más de 2 decimales) | BA014 | Contabilidad descuadrada o incoherente |
| BA006 | Transferencia inválida (misma cuenta u otra moneda) | BA015 | Clave de idempotencia reutilizada |
| BA007 | Registro inmutable | BA016 | Registro no encontrado |
| BA008 | Reverso inválido | BA017 | Parámetro de producto o cliente inválido |
| BA009 | El usuario es titular de la cuenta (RN-54) | | |

## 4. De dónde sale cada regla

| Reglas | Mecanismo | Prueba |
|---|---|---|
| RN-01, RN-11, RN-38, RN-42 | `UNIQUE` (documento, número de cuenta, clave de idempotencia, transacción reversada) | T01, T08, T14, T15 |
| RN-02 | Trigger diferido `trg_cliente_un_subtipo` + FK compuesta | T27 |
| RN-03, RN-04, RN-07, RN-18 a RN-21, RN-29, RN-30, RN-50 | `CHECK` y FK del DDL de G2 | T10, T11 |
| RN-08, RN-14, RN-15, RN-16 | Trigger `trg_titularidad_reglas` (bloquea la cuenta) | T28, T29, T30 |
| RN-09 | Triggers `trg_*_no_borrar` | T36 |
| RN-17, RN-22 | Trigger `trg_cuenta_reglas` | T31, T32 |
| RN-23 a RN-25, RN-27 | Triggers de `evento_cuenta` y `cambio_limite`: el estado y el límite de la cuenta **solo cambian con un evento** | T33, T34, T37 |
| RN-24 | FK a `ref.transicion_estado_cuenta` + validación en `core.fn_registrar_evento` | T34 |
| RN-28, RN-49, RN-51 | `seg.fn_exigir_permiso` dentro de cada operación | T19, T20 |
| RN-31, RN-34, RN-35, RN-43 | `fin.fn_validar_debito` / `fin.fn_validar_credito` con la cuenta bloqueada | T03, T16, T17, T18, T38 |
| RN-32, RN-33 | Validación en `fin.fn_transferir` (+ `CHECK` origen ≠ destino) | T04, T12 |
| RN-36 | El estado vigente (por eventos) impide operar fuera del periodo de la cuenta | T38 |
| RN-37 | Suma de retiros del día con la cuenta bloqueada | T13 |
| RN-39 | Una función = una sentencia SQL atómica | T06 |
| RN-40, RN-41, RN-53 | Triggers de inmutabilidad (fila y `TRUNCATE`); correcciones con `fn_reversar` | T05a–d, T07, T40, T41 |
| RN-44 | `fin.fn_aprobar_ajuste` + `CHECK` aprobador ≠ creador | T22, T23 |
| RN-45 | `CHECK` de rechazo con motivo + trigger: solo POSTED tiene asientos | T24 |
| RN-46, RN-47 | Triggers diferidos de cuadre (al confirmar) | T25 |
| RN-48 | Los saldos se aplican **desde los asientos** (`fin.fn_aplicar_saldos`) + vista de reconciliación | T46 |
| RN-52 | Trigger genérico `aud.trg_auditar` (usuario interno, usuario de BD, registro, antes/después) | T39 |
| RN-54 | `fin.fn_validar_no_titular` | T21 |
| G2 · H-03 | Trigger `trg_asiento_coherente` | T26 |
| Mínimo privilegio | `17_roles_permissions.sql` | T42 a T45 |

## 5. Concurrencia

| Riesgo | Cómo se evita | Prueba |
|---|---|---|
| Doble retiro / actualización perdida | `SELECT … FOR UPDATE` sobre la cuenta antes de validar fondos y límite | CT-1: la segunda sesión espera y falla con BA003 |
| Interbloqueo en transferencias cruzadas | Las cuentas se bloquean **siempre en orden de `cuenta_id`** (`core.fn_bloquear_cuentas`) | CT-2: ambas terminan, sin deadlock |
| Doble procesamiento (doble clic) | Clave de idempotencia `UNIQUE` + `INSERT … ON CONFLICT DO NOTHING` + huella (`hash_solicitud`) | CT-3: las dos sesiones reciben el mismo `transaccion_id` |
| Doble reverso | `FOR UPDATE` sobre la transacción original + `UNIQUE (transaccion_reversada_id)` | CT-4: la segunda falla con BA008 |

**Nivel de aislamiento:** `READ COMMITTED` (el de PostgreSQL por defecto). Con bloqueos de fila explícitos es suficiente y evita los reintentos que exigiría `SERIALIZABLE`.

## 6. Seguridad (mínimo privilegio)

| Rol de base de datos | Puede | No puede |
|---|---|---|
| `banco_consulta` | Leer `ref`, `core`, `fin` y las vistas de control | Escribir; ver `seg` y `aud` |
| `banco_cajero` | Lo de consulta + ejecutar las operaciones de caja | Reversar, aprobar ajustes, cerrar, escribir tablas directamente |
| `banco_supervisor` | Lo del cajero + desbloquear, cerrar, cambiar límite, reversar, aprobar ajustes, inactivar | Escribir tablas directamente |
| `banco_auditor` | Leer todo, incluida la auditoría | Ejecutar operaciones |
| `banco_admin_seg` | Administrar usuarios internos y roles | Ver o mover dinero; borrar asignaciones |

- Ningún rol de la aplicación tiene `INSERT`, `UPDATE` o `DELETE` sobre tablas de negocio: el dinero **solo** se mueve con las funciones.
- Se quitó el `EXECUTE` que PostgreSQL da a `PUBLIC` en todas las funciones.
- Las funciones `SECURITY DEFINER` fijan `search_path = pg_catalog, pg_temp` y usan nombres calificados, para que nadie pueda suplantar una tabla o función.

## 7. Carga masiva con triggers

Los scripts `sql/load/` desactivan los triggers de negocio y auditoría de las tablas que cargan (`ALTER TABLE … DISABLE TRIGGER USER`, que solo puede hacer el dueño de la tabla) y los reactivan antes del `COMMIT`. Las mismas reglas se verifican después en bloque (20 controles del lote 1 y 24 del lote 2). Así, cargar el millón toma lo mismo que antes (≈ 1,5 min en local) y no genera 3 millones de filas de auditoría.

## 8. Autoauditoría (formato del Prompt 2B: regla · PASS/FAIL · evidencia · corrección)

| Regla | Resultado | Evidencia | Corrección |
|---|---|---|---|
| 3FN; PK, FK, UNIQUE, NOT NULL, CHECK | PASS | G2 + DDL sin cambios de estructura | — |
| `NUMERIC` para dinero; `TIMESTAMPTZ` para eventos | PASS | 0 columnas float/real/money (G2) | — |
| Convención snake_case y comentarios en objetos críticos | PASS | `COMMENT ON` en tablas, funciones y roles | — |
| Clave de idempotencia | PASS | T14, T15, CT-3 | — |
| Transacciones ACID | PASS | T06, T25, CT-1 a CT-4 | — |
| Ledger de doble partida | PASS | T06, T07, T23, T25, T46 | — |
| Inmutabilidad de POSTED | PASS | T05a–d | La primera versión de T05d fallaba: `TRUNCATE` se rechaza si hay verificaciones diferidas pendientes. La prueba fuerza primero `SET CONSTRAINTS ALL IMMEDIATE`. |
| Auditoría | PASS | T39, T40, T41 | — |
| RBAC y mínimo privilegio | PASS | T19, T20, T42 a T45 | — |
| Índices justificados | PASS (por decisión) | `12_indexes.sql` | No se crean índices sin `EXPLAIN` que los justifique; se hace en G7. |
| Concurrencia | PASS | CT-0 a CT-4 | — |
| Operaciones: crear cliente y cuenta, activar, bloquear, desbloquear, consignar, retirar, transferir, reversar y cerrar | PASS | Fixture de `18_tests.sql`, T06, T07, T16, T19, T37 | — |
| Pruebas sobre la base con 1.000.000 de transacciones | PASS | `g3_tests.txt` §4 | La primera versión tardaba 3 min 25 s: la vista `v_estado_vs_eventos` usaba `LATERAL` por cuenta sin índice. Se reescribió con `DISTINCT ON` (conjunto) y la prueba final se limitó a los datos de prueba: **4 s**. |

**Limitaciones conocidas (se tratan en G7):**

- La función recibe el usuario interno como parámetro. La correspondencia "usuario que se conecta a la base ↔ usuario interno" la garantiza la aplicación; en G7 se documenta cómo validarla.
- Una operación rechazada se deshace completa (error). Si el canal quiere dejar rastro del rechazo (RN-45), llama a `fin.fn_registrar_rechazo` en una transacción aparte.

## 9. Verificación del gate G3

| Criterio del laboratorio | Resultado | Evidencia |
|---|---|---|
| El DDL se ejecuta desde cero sin errores | **Cumple** | `g3_tests.txt` §1 |
| `run_all.sql` corre dos veces seguidas en base limpia | **Cumple** | `g3_tests.txt` §2 |
| Las pruebas negativas fallan correctamente | **Cumple** | 39 pruebas negativas con el código de error esperado |
| Las pruebas positivas conservan la integridad | **Cumple** | 10 pruebas positivas + T46 (cuadre, saldo = ledger, estado = eventos) |
| Las 7 pruebas mínimas del laboratorio | **Cumple** | T01 a T07 |
| Concurrencia (doble retiro, actualización perdida, doble procesamiento) | **Cumple** | CT-0 a CT-4 |
| Los datos de G4 siguen cargando y validando con los triggers activos | **Cumple** | `g3_tests.txt` §3: 20/20 y 24/24 PASS |
| Funciona en el entorno del equipo (Windows, PostgreSQL 18.6) | **Cumple** | `g3_tests.txt` §6: 49/49 PASS |
| Evidencia mínima: `/sql` completo + `evidence/g3_tests.txt` | **Cumple** | Carpeta `sql/` y evidencia |

**QUALITY GATE G3 = PASS**

## 10. Decisiones de construcción

| ID | Decisión | Razón |
|---|---|---|
| DC-01 | Operaciones como funciones `SECURITY DEFINER`; sin permisos directos sobre las tablas | Única puerta de entrada al dinero; mínimo privilegio. |
| DC-02 | Errores con `SQLSTATE` propios (BA001–BA017) | Las pruebas verifican el motivo exacto, no solo que falle. |
| DC-03 | Bloqueo de filas en orden de `cuenta_id` + `READ COMMITTED` | Evita doble retiro e interbloqueos sin reintentos. |
| DC-04 | El saldo se aplica desde los asientos recién creados | El saldo nunca se calcula por un camino distinto al ledger (D-01). |
| DC-05 | Estado, fecha de cierre y límite solo cambian con un evento (`pg_trigger_depth`) | Mantiene D-03 consistente por construcción. |
| DC-06 | Sin índices secundarios hasta G7 | Cada índice debe tener una consulta y un `EXPLAIN` que lo justifiquen. |
| DC-07 | Carga masiva con triggers desactivados por el dueño + validación en bloque | Rendimiento y sin auditoría masiva artificial; solo el dueño puede desactivarlos. |
| DC-08 | Pruebas en una sola transacción con `ROLLBACK` | Se pueden correr en la base con datos sin ensuciarla. |

## 11. Matriz IA: nuevas entradas de G3

| ID | Prompt | Recomendación de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-17 | P-07 (2B) | Operaciones como funciones `SECURITY DEFINER` con `search_path` fijo y sin permisos directos a tablas. | **Aceptar** | T42 a T45 | Mínimo privilegio verificable. |
| IA-18 | P-07 (2B) | `SELECT … FOR UPDATE` en orden de `cuenta_id` y aislamiento `READ COMMITTED`. | **Aceptar** | CT-1 a CT-4 | Evita doble retiro e interbloqueos. |
| IA-19 | P-07 (2B) | Crear en G3 índices para todas las claves foráneas. | **Rechazar** (por ahora) | Criterio de G7: "un índice sin consulta que lo justifique" | Se crean en G7 con `EXPLAIN` antes y después. |
| IA-20 | P-07 (2B) | Auditar con trigger cada inserción también durante la carga masiva. | **Modificar** | Carga de 3.000.000 de filas | Los triggers se desactivan en la carga (solo el dueño puede) y se valida en bloque. |
| IA-21 | P-07 (2B) | Vista de estado por eventos con `LATERAL` por cuenta. | **Modificar** | Prueba sobre 1.000.000: 3 min 25 s → 4 s | Reescrita con `DISTINCT ON`. |
