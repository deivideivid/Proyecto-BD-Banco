# B6 · Paleta de colores

Antes de B6 comparamos tres opciones aplicadas a la misma pantalla (`paleta/opciones_paleta.png`):
A · Azul Andino, B · Verde Cordillera y C · Grafito y Vino. **En grupo escogimos la A.**

| Rol | Color | Dónde lo usamos |
|---|---|---|
| Primario | `#0B2545` | Barra superior, botón principal, cifras, opción activa del menú |
| Secundario | `#1D4E89` | Íconos, enlaces, foco de los campos, primera serie de gráficas |
| Acento | `#C9A227` | Logo, línea bajo las cifras, avatar, botón destacado (con texto azul) |
| Fondo | `#F3F6FA` | Fondo de la página, con degradados suaves detrás del vidrio |
| Texto / texto suave | `#0F1B2D` / `#55657A` | Textos y etiquetas |
| Éxito / alerta / peligro | `#1B7A4B` / `#8F5F00` / `#B42318` | Avisos, estados y botones de acciones delicadas |
| Gráficas | `#0B2545`, `#1D4E89`, `#4F86C6`, `#C9A227`, `#2A7F8E`, `#8DA9C4` | Series de Chart.js y de Power BI |

**Contraste (WCAG AA, mínimo 4,5:1).** Al revisarlo con la fórmula de la norma, el color de alerta
de la propuesta (`#9A6700`) daba 4,49:1 sobre el fondo, un pelo por debajo. Lo oscurecimos un poco
a `#8F5F00` (5,09:1 sobre el fondo y 5,52:1 sobre blanco). Con ese cambio todos los textos pasan
sobre blanco y sobre el fondo. El dorado da 2,4:1 sobre blanco,
así que **nunca lo usamos para texto**; en el botón destacado va con texto azul encima (6,4:1).

**Dónde vive.** En el aplicativo, todo el color sale de las variables al inicio de
`aplicativo/web/css/banco.css`. En Power BI, del tema `B3_powerbi/powerbi/tema_banco_andino.json`.
