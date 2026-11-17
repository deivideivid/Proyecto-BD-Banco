# B1 · Lineamientos de la interfaz final

Esto lo acordamos al revisar los bocetos. Los bocetos son en blanco y negro a propósito: muestran
qué va en cada pantalla. El aspecto final lo construimos en B6 siguiendo estas reglas.

## Menú lateral plegable

- Arriba a la izquierda va un botón ☰ (menú hamburguesa).
- En computador, el menú se pliega a una franja delgada con solo íconos, como el menú lateral de
  Opera, y el contenido (tablero o página) se agranda para usar ese espacio. Al pasar el mouse por
  un ícono sale su nombre, y con el mismo botón ☰ se vuelve a abrir.
- El aplicativo recuerda si cada persona dejó el menú abierto o plegado.
- En celular, el menú sale encima del contenido desde la izquierda y se cierra tocando afuera o
  deslizando. La barra de abajo se queda con los accesos más usados de cada perfil.
- Boceto: `bocetos/8_menu_lateral.png`.

## Estilo visual

- **Minimalista:** pocos elementos por pantalla, mucho espacio en blanco y una sola acción
  principal por pantalla.
- **Glass (vidrio):** tarjetas, menú y ventanas con fondo semitransparente y desenfoque detrás,
  bordes suaves y sombras ligeras. Cuidamos que el texto siempre se lea bien sobre el vidrio.
- **Íconos simples:** un solo estilo de íconos de línea en todo el aplicativo, del mismo color
  de la paleta. Nada de íconos de colores mezclados.
- **Logo:** sencillo y del color de la paleta, para la barra superior y la pantalla de inicio.

## Animaciones

| Dónde | Qué pasa |
|---|---|
| Botones | Se elevan un poco al pasar el mouse y se hunden al presionarlos |
| Iniciar sesión | La tarjeta de entrada se desvanece y el tablero del perfil entra suavemente |
| Pagos y transferencias | Mientras la base responde, el botón muestra que está procesando; al terminar aparece una marca de éxito animada con el número de transacción |
| Errores | La tarjeta se sacude un poco y muestra el motivo en lenguaje sencillo |
| Menú lateral | Se pliega y se abre deslizándose, y el contenido se acomoda sin saltos |
| Tableros | Las cifras cuentan hasta su valor y las gráficas crecen al cargar |
| Cambio de página | Transición corta de desvanecido |

Las animaciones son cortas (menos de medio segundo) para que no estorben. Si el celular o el
computador tienen activado "reducir movimiento", las quitamos.

## Colores

La paleta la definimos más adelante, cuando estemos en el desarrollo. La idea es que se vea
como un banco: sobria y ejecutiva. Antes de B6 vamos a comparar 2 o 3 opciones en grupo.
