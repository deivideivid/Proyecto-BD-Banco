# B1 · Pantallas y navegación

Este es el mapa de pantallas que vamos a construir en B6. Los bocetos de cada una están en la
carpeta `bocetos/`, en versión de computador y de celular.

## Partes públicas (sin iniciar sesión)

| Pantalla | Qué tiene |
|---|---|
| Inicio | Presentación del Banco Andino (banco ficticio, datos sintéticos) y botón para entrar |
| Iniciar sesión | Usuario y contraseña. Según el perfil, lleva a su menú |
| Equipo | Una tarjeta por integrante: foto o iniciales, rol en el proyecto y botón para ver su hoja de vida en PDF |
| Tecnologías | Cada herramienta que usamos y para qué |

## Pantallas por perfil

| Perfil | Pantallas |
|---|---|
| Cliente | Mis cuentas · Movimientos y extracto · Transferir · Mis estadísticas |
| Cajero | Buscar cliente o cuenta · Ficha del cliente · Nuevo cliente · Abrir cuenta · Operación de caja (consignar, retirar, transferir) · Bloquear cuenta · Crear ajuste |
| Supervisor | Lo del cajero · Pendientes de aprobar (ajustes) · Reversar transacción · Cuenta: desbloquear, cambiar límite, cerrar · Inactivar cuentas · Estadísticas de su oficina |
| Auditor de datos | Calidad de datos (resultado del quality gate) · Cuadres y reconciliación · Bitácora de auditoría · Estadísticas: Control y calidad |
| Administrador | Usuarios · Asignar o revocar rol · Estadísticas completas |

## Estadísticas (las mismas 4 páginas de Power BI)

| Página | Indicadores que pensamos mostrar |
|---|---|
| Resumen | Transacciones contabilizadas, monto movido, clientes, cuentas activas, saldo total por moneda |
| Transacciones | Monto y número por tipo y por mes, hora pico, rechazos por motivo, reversos |
| Clientes y cuentas | Cuentas por producto y estado, clientes por departamento, saldo por producto |
| Control y calidad | Transacciones cuadradas, diferencias saldo contra ledger, puntaje del quality gate, registros de auditoría |

La lista final de indicadores con su fórmula la cerramos en B2, cuando armemos el modelo
estrella, para que cada uno se pueda calcular igual en SQL, en Power BI y en el aplicativo.

## Cómo se ve en celular

- El menú lateral se abre con el botón ☰ encima del contenido, y abajo queda una barra con
  los accesos más usados.
- Las tablas largas se vuelven tarjetas, una por fila.
- Los formularios van en una sola columna con botones grandes.
- Las gráficas se apilan una debajo de la otra.

## Reglas de diseño que nos pusimos

- El menú lateral se pliega con el botón ☰ y el contenido se agranda (ver `lineamientos_interfaz.md`).
- Mismo color principal y el mismo logo del Banco Andino en todas las pantallas.
- Cada operación pide confirmar antes de enviarse y muestra el número de transacción al terminar.
- Cuando la base rechaza algo, mostramos el motivo en lenguaje sencillo según el código de error
  (por ejemplo, BA003 → "Fondos insuficientes").
- El dinero siempre con separador de miles y la moneda (COP o USD).

> En los bocetos, los nombres de personas, usuarios y la mayoría de cifras son de ejemplo. Los
> números reales salen de la base cuando construyamos las pantallas.
