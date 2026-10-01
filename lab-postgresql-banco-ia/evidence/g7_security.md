# G7 — Seguridad: roles y mínimo privilegio

| Campo | Valor |
|---|---|
| Proyecto | Laboratorio de Ingeniería de Bases de Datos Relacionales Aumentada con IA — Banco Andino Colombia |
| Gate | **G7 — Performance, índices y seguridad** (parte 2: seguridad; el rendimiento está en [`g7_explain.md`](g7_explain.md)) |
| Fecha | 2026-10-01 |
| Roles y permisos | [`sql/17_roles_permissions.sql`](../sql/17_roles_permissions.sql) (G3) |
| Demostración | [`sql/tests/g7_rbac_demo.sql`](../sql/tests/g7_rbac_demo.sql) → [`g7_rbac_resultados.txt`](g7_rbac_resultados.txt) |
| Resultado | **G7 RBAC = PASS**: 23 pruebas con 6 usuarios (8 accesos permitidos, 15 denegados, 0 fallas), en PostgreSQL 16 y en el PostgreSQL 18.6 del equipo |

## 1. Modelo de seguridad en dos niveles

| Nivel | Qué controla | Dónde |
|---|---|---|
| **1. Base de datos** | Qué puede leer o ejecutar una conexión (`GRANT` / `REVOKE`) | 5 roles de grupo `banco_*` (`17_roles_permissions.sql`) |
| **2. Aplicación** | Qué puede hacer cada empleado del banco (cajero, supervisor…) | `seg.usuario_rol` + `seg.fn_exigir_permiso`, que valida dentro de cada función y falla con `BA001` |

Principios aplicados:

- **Nadie de la aplicación escribe directo en las tablas de dinero.** Ningún rol tiene `INSERT`, `UPDATE` ni `DELETE` sobre `cuenta`, `transaccion_financiera` ni `asiento_contable`. El dinero solo se mueve con funciones `SECURITY DEFINER`, que validan las reglas, bloquean filas y registran la doble partida.
- **Funciones blindadas:** todas tienen `search_path = pg_catalog, pg_temp` fijo. Esto evita que alguien suplante tablas u operadores (prueba DS06 de G6 = 0).
- **Nada para PUBLIC:** se quitan explícitamente los permisos por defecto sobre esquemas, tablas, secuencias y funciones (prueba DS07 de G6 = 0).
- **Separación de funciones:**
  - El cajero no reversa: solo el supervisor (RN-51).
  - El auditor solo lee.
  - El administrador de seguridad gestiona usuarios, pero no ve ni mueve dinero.
- **Inmutabilidad:** aunque alguien tuviera permiso, los triggers impiden modificar o borrar transacciones, asientos y la auditoría, incluso al dueño de la base (RN-40, RN-53).
- **Trazabilidad:** cada operación deja en `aud.log_auditoria` quién la hizo: el usuario interno (`banco.usuario_id`) y el usuario de base de datos.

## 2. Roles de base de datos

| Rol | Para quién | Puede | No puede |
|---|---|---|---|
| `banco_consulta` | Reportes, consulta | Leer catálogos, clientes, cuentas y transacciones | Ver seguridad ni auditoría; escribir; ejecutar operaciones |
| `banco_cajero` | Operativo de caja | Lo de consulta + ejecutar operaciones de caja (clientes, apertura, consignar, retirar, transferir, crear ajustes) | Reversar, aprobar, cerrar cuentas, cambiar límites; escribir directo |
| `banco_supervisor` | Supervisor de oficina | Lo del cajero + reversar, aprobar o rechazar ajustes, desbloquear, cerrar, cambiar límites, inactivar | Escribir directo; administrar usuarios |
| `banco_auditor` | Auditoría interna | Leer **todo**, incluida la auditoría y la seguridad | Escribir o ejecutar operaciones |
| `banco_admin_seg` | Administrador de seguridad | Crear y modificar usuarios internos y sus roles (sin `DELETE`: se revocan con fecha) | Ver o mover dinero |

Matriz verificada en la base con `has_table_privilege` y `has_function_privilege`:

| Rol | Leer cuentas | Modificar cuentas | Insertar transacciones | Borrar asientos | Leer auditoría | Modificar usuarios | Retirar | Reversar |
|---|---|---|---|---|---|---|---|---|
| banco_consulta | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ | ✘ |
| banco_cajero | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ | ✔ | ✘ |
| banco_supervisor | ✔ | ✘ | ✘ | ✘ | ✘ | ✘ | ✔ | ✔ |
| banco_auditor | ✔ | ✘ | ✘ | ✘ | ✔ | ✘ | ✘ | ✘ |
| banco_admin_seg | ✘ | ✘ | ✘ | ✘ | ✘ | ✔ | ✘ | ✘ |

## 3. Demostración con usuarios de cada rol

El script crea 6 usuarios de prueba: uno por rol y uno sin rol. Se crean **sin contraseña** (`NOLOGIN`), así que no hay credenciales en el repositorio, y se usan con `SET ROLE`, que equivale a conectarse con ese usuario. Cada acción se ejecuta de verdad:

- Si PostgreSQL la permite, se deshace al final, así que la base no cambia.
- Si la niega, se guarda el mensaje de error.
- Al terminar, los usuarios se borran.

Los mensajes de abajo son los de una instalación en inglés; en un PostgreSQL en español salen traducidos (por ejemplo, "permiso denegado al esquema aud").

| Prueba | Usuario | Acción | Esperado | Obtenido | Mensaje de PostgreSQL |
|---|---|---|---|---|---|
| S01 | consulta | Leer saldos de cuentas | PERMITIDO | PERMITIDO | |
| S02 | consulta | Leer la auditoría | DENEGADO | DENEGADO | permission denied for schema aud |
| S03 | consulta | Leer usuarios internos | DENEGADO | DENEGADO | permission denied for schema seg |
| S04 | consulta | Cambiar un saldo directamente | DENEGADO | DENEGADO | permission denied for table cuenta |
| S05 | consulta | Hacer un retiro | DENEGADO | DENEGADO | permission denied for function fn_retirar |
| S06 | cajero | Consignar con la función segura | PERMITIDO | PERMITIDO | |
| S07 | cajero | Retirar con la función segura | PERMITIDO | PERMITIDO | |
| S08 | cajero | Insertar una transacción a mano | DENEGADO | DENEGADO | permission denied for table transaccion_financiera |
| S09 | cajero | Cambiar un saldo directamente | DENEGADO | DENEGADO | permission denied for table cuenta |
| S10 | cajero | Reversar una transacción | DENEGADO | DENEGADO | permission denied for function fn_reversar |
| S11 | cajero | Leer la auditoría | DENEGADO | DENEGADO | permission denied for schema aud |
| S12 | supervisor | Reversar (empleado SUPERVISOR) | PERMITIDO | PERMITIDO | |
| S13 | supervisor | Reversar (empleado CAJERO) | DENEGADO (app) | DENEGADO (app) | El usuario 10 no tiene el permiso TX_REVERSAR (BA001) |
| S14 | auditor | Leer la auditoría | PERMITIDO | PERMITIDO | |
| S15 | auditor | Leer usuarios y roles internos | PERMITIDO | PERMITIDO | |
| S16 | auditor | Leer el ledger | PERMITIDO | PERMITIDO | |
| S17 | auditor | Modificar la auditoría | DENEGADO | DENEGADO | permission denied for table log_auditoria |
| S18 | auditor | Borrar asientos contables | DENEGADO | DENEGADO | permission denied for table asiento_contable |
| S19 | auditor | Consignar | DENEGADO | DENEGADO | permission denied for function fn_consignar |
| S20 | admin_seg | Administrar usuarios internos | PERMITIDO | PERMITIDO | |
| S21 | admin_seg | Ver saldos de cuentas | DENEGADO | DENEGADO | permission denied for schema core |
| S22 | sin rol | Leer cuentas | DENEGADO | DENEGADO | permission denied for schema core |
| S23 | sin rol | Ejecutar una función del banco | DENEGADO | DENEGADO | permission denied for schema ref |

**Lo que demuestra:**

- **El usuario de consulta** lee la información de negocio, pero no la de seguridad ni la de auditoría, y no puede tocar el dinero (S01–S05).
- **El usuario operativo** (cajero) mueve dinero **solo** con las funciones, que validan las reglas. No puede hacerlo por fuera (S08–S09) ni hacer lo que le corresponde al supervisor (S10).
- **Los dos niveles se complementan** (S12–S13). La conexión de un supervisor puede ejecutar `fn_reversar`, pero si el empleado indicado es un cajero, la función lo rechaza con `BA001`. Una conexión con permisos amplios no basta: también cuenta el rol del empleado.
- **El auditor** lo lee todo, pero no puede modificar ni borrar nada, ni operar (S14–S19).
- **El administrador de seguridad** está separado del dinero (S20–S21).
- **Un usuario sin rol** no ve nada (S22–S23).

## 4. Recomendaciones para producción

| Tema | Recomendación |
|---|---|
| Conexiones | Usuarios con `LOGIN` y contraseña `SCRAM-SHA-256`, guardada en un gestor de secretos, nunca en el repositorio. Cada usuario hereda un solo rol `banco_*`. |
| Red | `pg_hba.conf` solo con las IP de los servidores de la aplicación; SSL obligatorio. |
| Reportes | El rol de consulta corre los reportes pesados (como W10) en una réplica de lectura, con `statement_timeout` para que no afecten la operación. |
| Superusuario | `postgres` solo para mantenimiento; la aplicación nunca se conecta como dueña de la base. |
| Revisión | Ejecutar `sql/tests/g7_rbac_demo.sql` y `sql/quality_gate.sql` (pruebas DS06, DS07, DS08 y A01–A06) después de cada cambio de permisos. |

## 5. Verificación del gate G7 (seguridad)

| Criterio de la guía | Resultado | Evidencia |
|---|---|---|
| Revisar permisos con un usuario de consulta, uno operativo y un auditor | **Cumple** | `demo_consulta`, `demo_cajero`, `demo_auditor` (+ supervisor, admin_seg y uno sin rol) |
| Al menos un acceso permitido y uno denegado por rol | **Cumple** | Sección 3: cada usuario tiene los dos casos |
| RBAC demuestra mínimo privilegio | **Cumple** | 23/23 pruebas como se esperaba; matriz de la sección 2 |
| Evidencia mínima: `evidence/g7_explain.md` + `evidence/g7_security.md` | **Cumple** | Ambos documentos |

**Repetición en el PC del equipo (PostgreSQL 18.6, Windows):** el mismo script dio **23 pruebas, 8 permitidos, 15 denegados, 0 fallas → G7 RBAC = PASS**, con la misma matriz de privilegios. Los mensajes salen en español (por ejemplo, "permiso denegado al esquema aud", "permiso denegado a la función fn_retirar"; S13: "El usuario 10 no tiene el permiso TX_REVERSAR").

**QUALITY GATE G7 = PASS** (rendimiento en `g7_explain.md` + seguridad en este documento).

## 6. Matriz IA: nuevas entradas de G7 (seguridad)

| ID | Prompt | Recomendación o resultado de la IA | Decisión | Evidencia | Justificación |
|---|---|---|---|---|---|
| IA-43 | P-11 | Demostrar el RBAC con usuarios `NOLOGIN` y `SET ROLE`, deshaciendo cada acción permitida. | **Aceptar** | 23/23 PASS; la base no cambia | Prueba real de permisos sin contraseñas en el repositorio ni datos modificados. |
| IA-44 | P-11 | Incluir una prueba de que el rol de base de datos no basta (S13). | **Aceptar** | S13 = DENEGADO (app, BA001) | Demuestra el segundo nivel (permisos del empleado), que es el que exige RN-51. |
