# B5 · Matriz de permisos

Qué puede hacer cada perfil, con qué rol de la base lo hace y quién lo frena si intenta otra cosa.
"Servidor" = el servidor responde 403 antes de tocar la base. "Base" = aunque el servidor lo
dejara pasar, la base lo niega (42501 por el rol, BA001 por el permiso del banco, BA010 por la
cuenta ajena).

| Sección o acción | Cliente | Cajero | Supervisor | Auditor de datos | Administrador |
|---|---|---|---|---|---|
| Rol de la base | `banco_cliente_app` | `banco_cajero` | `banco_supervisor` | `banco_auditor` | `banco_admin_seg` |
| Sus cuentas, movimientos y transferir | Sí, solo las suyas (la base revisa la titularidad) | No | No | No | No |
| Buscar clientes y ver fichas | No | Sí, de su oficina | Sí, de su oficina | No | No |
| Registrar clientes, abrir y activar cuentas | No | Sí | Sí | No | No |
| Consignar, retirar, transferir | No | Sí, cuentas de su oficina | Sí, cuentas de su oficina | No (Base: 42501) | No (Base: 42501) |
| Bloquear cuenta, crear ajuste | No | Sí | Sí | No | No |
| Desbloquear, cambiar límite, cerrar | No | No (Base: 42501) | Sí | No | No |
| Reversar | No | No (Base: 42501) | Sí | No | No |
| Aprobar o rechazar ajustes | No | No (Base: 42501) | Sí, pero no los suyos (RN-44) | No | No |
| Inactivar cuentas sin movimiento | No | No | Sí, con vista previa y confirmación, mínimo 180 días | No | No |
| Cuadres, bitácora de auditoría e ingresos | No | No (Base: 42501) | No | Sí, solo lectura | No |
| Calidad de datos (quality gate) | No | No | No | Sí | No |
| Usuarios y roles | No | No (Base: 42501) | No | No | Sí, pero no a sí mismo (RN-50) |
| Estadísticas | No (sus estadísticas van en "Mis estadísticas") | No | Las 4 páginas, solo de su oficina | Solo Control y calidad | Las 4 páginas, todo el banco |

**Usuario técnico `canal.digital`.** Es con quien se hacen las transferencias del cliente. Su rol
del banco (`CANAL_DIGITAL`) solo tiene `TX_TRANSFERIR`: si alguien intentara consignar con él, la
base responde BA001 (lo probamos). El administrador no lo puede modificar desde el aplicativo.

**`app_servidor`.** No tiene permisos propios. Puede ponerse los 7 roles de arriba (más
`banco_bi` para las estadísticas y `banco_app_acceso` para el inicio de sesión), pero no los
hereda: sin `SET ROLE` la base le niega todo (lo probamos).
