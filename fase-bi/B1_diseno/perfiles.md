# B1 · Perfiles del aplicativo

Definimos 5 perfiles. Cuatro ya existían en la base desde G3 (tabla `seg.rol`) y uno es nuevo:
el Cliente. Para cada uno dejamos claro qué ve, qué puede hacer y con qué función de la base
lo hace, para que en B5 no tengamos que inventar nada.

## Resumen

| Perfil | Rol en la base | Qué ve | Qué puede hacer |
|---|---|---|---|
| Cliente | Nuevo (canal digital) | Solo sus cuentas y sus movimientos | Transferir entre cuentas |
| Cajero | `CAJERO` | Clientes y cuentas de su oficina | Registrar clientes, abrir cuentas, consignar, retirar, transferir, bloquear, crear ajustes |
| Supervisor | `SUPERVISOR` | Lo del cajero, más lo pendiente de aprobar | Lo del cajero, más desbloquear, cerrar, cambiar límites, reversar, aprobar ajustes, inactivar |
| Auditor de datos | `AUDITOR` | Calidad de datos, cuadres y bitácora de auditoría | Solo consultar. No mueve dinero |
| Administrador | `ADMIN_SEGURIDAD` | Usuarios, roles y estadísticas completas | Crear y desactivar usuarios, asignar y revocar roles |

## Detalle por perfil

### Cliente (banca en línea)

- **Ve:** sus cuentas con saldo disponible, sus últimos movimientos, un extracto por fechas y un
  resumen de cuánto entró y salió por mes.
- **Hace:** transferir entre cuentas de la misma moneda.
- **Cómo lo resolvemos en la base:** las funciones del banco piden siempre un empleado que
  opere (`p_usuario_id`) y la regla RN-10 dice que los clientes no son usuarios. Por eso vamos a
  crear un usuario técnico del canal digital, con un rol nuevo que solo tiene el permiso
  `TX_TRANSFERIR`. El aplicativo revisa primero que la cuenta de origen sea del cliente que
  inició sesión y después llama a `fin.fn_transferir` con ese usuario técnico. Así las reglas de
  fondos, límite diario e idempotencia siguen viviendo en la base.

### Cajero

| Acción | Función de la base | Permiso |
|---|---|---|
| Buscar cliente o cuenta | Consulta | `banco_consulta` |
| Registrar cliente natural / jurídico | `core.fn_crear_cliente_natural`, `core.fn_crear_cliente_juridico` | `CLI_CREAR` |
| Abrir y activar cuenta | `core.fn_abrir_cuenta`, `core.fn_activar_cuenta` | `CTA_ABRIR`, `CTA_ACTIVAR` |
| Consignar | `fin.fn_consignar` | `TX_CONSIGNAR` |
| Retirar | `fin.fn_retirar` | `TX_RETIRAR` |
| Transferir | `fin.fn_transferir` | `TX_TRANSFERIR` |
| Bloquear cuenta | `core.fn_bloquear_cuenta` | `CTA_BLOQUEAR` |
| Crear ajuste (queda pendiente) | `fin.fn_crear_ajuste` | `TX_AJUSTE_CREAR` |

### Supervisor

Todo lo del cajero, más:

| Acción | Función de la base | Permiso |
|---|---|---|
| Desbloquear cuenta | `core.fn_desbloquear_cuenta` | `CTA_DESBLOQUEAR` |
| Cambiar límite diario | `core.fn_cambiar_limite` | `CTA_CAMBIAR_LIMITE` |
| Cerrar cuenta | `core.fn_cerrar_cuenta` | `CTA_CERRAR` |
| Reversar transacción | `fin.fn_reversar` | `TX_REVERSAR` |
| Aprobar o rechazar ajuste | `fin.fn_aprobar_ajuste`, `fin.fn_rechazar_ajuste` | `TX_AJUSTE_APROBAR` |
| Inactivar cuentas sin movimiento | `CALL core.pr_inactivar_cuentas_sin_movimiento` | `CTA_INACTIVAR` |

### Auditor de datos

- **Ve:** el resultado del quality gate de G6, los cuadres de las vistas de reconciliación
  (`fin.v_balance_transaccion`, `core.v_saldo_vs_ledger`, `core.v_estado_vs_eventos`), la
  bitácora `aud.log_auditoria` con filtros y la página de Control y calidad de las estadísticas.
- **No hace:** ninguna operación. En la base tiene permiso de solo lectura (`banco_auditor`).

### Administrador

- **Ve:** la lista de usuarios internos con sus roles, y todas las páginas de Estadísticas.
- **Hace:** crear usuarios internos, desactivarlos y asignar o revocar roles con fecha (la base
  no deja borrar asignaciones).
- **No hace:** mover dinero. En la base, `banco_admin_seg` no tiene ese permiso, y lo dejamos así.

## Cómo se entra al aplicativo

- La base no guarda contraseñas (desde G3, `seg.usuario` no tiene esa columna). Por eso vamos a
  crear un esquema aparte, `app`, con los accesos del aplicativo: usuario, contraseña cifrada
  (hash) y a qué empleado o cliente corresponde.
- Para la sustentación dejamos un usuario de prueba por perfil. Las contraseñas no van en el
  repositorio: se generan al montar el aplicativo.
- Cada perfil, al entrar, solo ve su menú. Si alguien intenta abrir una pantalla que no le toca,
  el servidor la niega, y aunque la saltara, la base también la niega (doble control, como en G7).

## Qué ve cada perfil en el menú

| Sección | Cliente | Cajero | Supervisor | Auditor | Administrador |
|---|---|---|---|---|---|
| Mis cuentas / Transferir | Sí | | | | |
| Caja (clientes, cuentas, operaciones) | | Sí | Sí | | |
| Aprobaciones y reversos | | | Sí | | |
| Calidad de datos y auditoría | | | | Sí | |
| Usuarios y roles | | | | | Sí |
| Estadísticas | Solo las suyas | | De su oficina | Control y calidad | Todas |
| Equipo y Tecnologías | Sí | Sí | Sí | Sí | Sí (también sin iniciar sesión) |
