# B6 · Interfaces

En este gate hicimos las pantallas de los 5 perfiles, las secciones públicas (Inicio, Equipo y
Tecnologías) y le pusimos al aplicativo la paleta que escogimos en grupo. Todo funciona en
celular, tablet y computador.

- `paleta.md` y `paleta/opciones_paleta.png` - las tres opciones que comparamos y la que quedó.
- `sql/b6_01_accesos_admin.sql` y `ejecutar_b6.bat` - funciones para que el administrador le dé
  acceso al aplicativo a un empleado (con sus pruebas).
- `pruebas/capturas_b6.py` - recorre las pantallas en los tres tamaños, toma las capturas y
  revisa que no haya errores ni desplazamiento lateral. También prueba el menú y una
  transferencia de punta a punta.
- `capturas/` - las 51 capturas (`celular_*`, `tablet_*`, `computador_*`).
- `salidas/revision_pantallas.txt` - el resultado de esa revisión.
- El código está en `fase-bi/aplicativo/web/`.

## Pantallas

| Perfil | Pantallas |
|---|---|
| Sin iniciar sesión | Inicio · Ingresar · Equipo (con las hojas de vida) · Tecnologías |
| Cliente | Mis cuentas · Movimientos (por cuenta y fechas) · Transferir · Mis estadísticas |
| Cajero | Buscar cliente · Ficha del cliente con sus cuentas · Operación de caja por número de cuenta · Nuevo cliente (persona natural o empresa) · Abrir y activar cuenta · Bloquear · Crear ajuste |
| Supervisor | Todo lo del cajero, más desbloquear, cambiar límite y cerrar desde la ficha · Pendientes de aprobar · Reversar · Inactivar cuentas (con vista previa) · Estadísticas de su oficina |
| Auditor de datos | Calidad de datos · Cuadres · Bitácora de auditoría con filtros · Ingresos al aplicativo · Tablero de Control y calidad |
| Administrador | Usuarios y roles · Nuevo usuario · Accesos al aplicativo (contraseña temporal que se muestra una sola vez) · Estadísticas de todo el banco |

## Cómo seguimos los lineamientos de B1

- **Menú lateral plegable como el de Opera.** El botón ☰ lo pliega a una franja de íconos y el
  contenido se agranda; al pasar el mouse por un ícono sale su nombre. El aplicativo recuerda si
  cada persona lo dejó plegado. En celular el menú sale encima del contenido, se cierra tocando
  afuera o deslizando a la izquierda, y abajo queda una barra con los 4 accesos más usados.
- **Vidrio y minimalismo.** Tarjetas, menú y ventanas semitransparentes con desenfoque, una sola
  acción principal por pantalla y un solo estilo de íconos de línea (dibujados por nosotros).
- **Animaciones cortas.** Los botones se elevan y se hunden; al ingresar, la tarjeta se desvanece;
  en cada operación el botón muestra "Procesando…" y al terminar sale una marca de éxito animada
  con el número de la transacción; si algo falla, la tarjeta se sacude y muestra el motivo en
  lenguaje sencillo; las cifras cuentan hasta su valor. Si el equipo tiene "reducir movimiento",
  se quitan.
- **Cada operación pide confirmar** con un resumen antes de enviarse.
- **El dinero** siempre con separador de miles, dos decimales y la moneda. Los montos se pueden
  escribir como en Colombia (`1.250.000,50`).
- **Tablas que en celular se vuelven tarjetas**, una por fila.

## Equipo y hojas de vida

La sección Equipo lee `fase-bi/equipo/equipo.json` y muestra el PDF de cada uno. Antes de
publicarlas revisamos las cuatro hojas de vida que teníamos y encontramos datos que no deben
quedar a la vista: números de documento, direcciones, fecha de nacimiento, teléfonos y los
nombres y teléfonos de las referencias (que son de otras personas). Hicimos copias con esos
datos borrados del PDF (no solo tapados: el texto ya no está) con los nombres `hv_*.pdf`, y el
aplicativo solo entrega esas copias. La de David aparece como pendiente hasta que la suba.

## Cómo correrlo

1. Doble clic en `ejecutar_b6.bat` (pide la contraseña de `postgres`). Debe terminar en
   **B6 ACCESOS = PASS**.
2. Cerrar la ventana vieja del aplicativo y abrirlo otra vez con `fase-bi/aplicativo/iniciar_local.bat`.
3. Opcional: con el aplicativo prendido, `python fase-bi/B6_interfaces/pruebas/capturas_b6.py`
   vuelve a tomar las capturas.

## Cuándo damos B6 por cerrado

Se ve bien en celular, tablet y computador (con capturas).

## Resultado

Lo probamos en la copia de la base de B5:

- **50 revisiones en PASS:** 46 pantallas (18 en computador y celular, 10 de ellas también en
  tablet) cargaron sin errores del navegador y sin desplazamiento lateral, más 4 pruebas de
  interacción (menú plegable que se recuerda, menú del celular, una transferencia completa con
  su número y un rechazo por fondos con el mensaje en lenguaje sencillo).
- **B6 ACCESOS = PASS** (4 de 4): el cajero no da accesos, un administrador no se da acceso a sí
  mismo y no se da un perfil sin el rol vigente.
- Volvimos a correr las pruebas anteriores con las pantallas nuevas: **110 de 110** en
  `probar_perfiles.py` (ahora incluye dar y quitar acceso a un empleado nuevo) y las 37 cifras de
  Estadísticas siguen dando igual a SQL.

## Lo que nos pasó

- La ventana de confirmar mostraba `[object HTMLElement]` en vez de los datos: la función que
  arma los elementos solo aplanaba un nivel de listas. La corregimos y la prueba de la
  transferencia ahora revisa esa ventana.
- La página de Estadísticas buscaba el contenedor viejo (`.contenido`) después de pasarla al marco
  común y no cargaba; lo encontró la revisión de pantallas.
- Las páginas públicas preguntaban por la sesión y el navegador anotaba un error 401. Agregamos
  `/api/sesion/estado`, que responde sin error cuando no hay sesión.
- El color de alerta de la paleta daba 4,49:1 de contraste sobre el fondo; lo oscurecimos a
  `#8F5F00` (ver `paleta.md`).

## Lo que falta

- La hoja de vida de David (`fase-bi/equipo/hojas_de_vida/hv_david_gonzalez.pdf`).
- El rol de cada uno en el proyecto, en `fase-bi/equipo/equipo.json` (por ahora solo está el de
  Jerónimo).
- Aplicar el tema de colores en Power BI y ordenar los días de la semana (ver `B3_powerbi/README.md`).
