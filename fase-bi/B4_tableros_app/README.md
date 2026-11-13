# B4 · Tableros dentro del aplicativo

Power BI no se puede meter directo en una página sin publicarlo en su servicio en la nube, así
que hicimos los mismos tableros dentro del aplicativo, con gráficas propias (plan B, decisión 3).
Es la sección **Estadísticas**: las mismas 4 páginas de Power BI, con los mismos filtros.

- `sql/b4_01_funciones_estadisticas.sql` - las funciones del esquema `bi` que calculan los
  indicadores, las series de las gráficas, los clientes con más saldo y las opciones de los filtros.
- `sql/b4_02_validar_estadisticas.sql` - compara lo que entregan esas funciones con el cálculo
  directo en SQL, revisa que cada gráfica sume lo mismo que su indicador y prueba los permisos.
- `ejecutar_b4.bat` - corre los dos scripts y guarda la salida en `salidas/salida_b4.txt`.
- `pruebas/validar_pagina.py` - abre la página en un navegador, lee las cifras que se ven y las
  compara con los valores oficiales. También toma las capturas.
- `equivalencia_b4.md` - la comparación SQL, Power BI y página.
- `capturas/` - las 4 páginas en computador y en celular.
- El aplicativo está en `fase-bi/aplicativo/` (servidor en Python y páginas web).

## Cómo lo armamos

1. **Los indicadores se calculan en la base, no en la página.** Creamos funciones en `bi`
   (`fn_indicadores`, `fn_serie`, `fn_top_clientes`, `fn_opciones_filtro`) con las mismas reglas
   de `b2_05_kpi_referencia.sql` y de las medidas de Power BI. El servidor solo les pide los datos
   y la página solo los dibuja. Así hay un solo lugar donde vive cada fórmula.
2. **Los filtros se comportan igual que en Power BI.** El mes filtra las transacciones; los
   saldos (K08 a K11) son una foto al corte y no cambian con el mes; el quality gate y los
   controles (K12 y K13) son de toda la base. La página Control y calidad no tiene filtros.
3. **Solo lectura.** Las funciones solo las puede ejecutar el rol `banco_bi` (el mismo de Power
   BI). En local el aplicativo entra con `powerbi_lector`.
4. **El servidor** es FastAPI (`fase-bi/aplicativo/servidor/`). Entrega cada página como JSON en
   `/api/estadisticas/{resumen|transacciones|clientes|control}` y guarda lo calculado en memoria:
   sin filtros, la base se demora unos 3 segundos en recorrer el millón de transacciones, y de
   ahí en adelante sale al instante. Si alguien recarga el modelo estrella, el caché se renueva solo.
5. **La página** (`fase-bi/aplicativo/web/estadisticas.html`) usa Chart.js copiado dentro del
   proyecto. Muestra los montos exactos al centavo, con separador de miles y la moneda, y sigue
   los lineamientos de B1: tarjetas tipo vidrio, cifras que cuentan hasta su valor, gráficas que
   crecen al cargar y nada de animaciones si el equipo tiene activado "reducir movimiento".
6. **En celular** las tarjetas van de dos en dos (las cifras largas ocupan toda la fila), los
   filtros en una columna, las gráficas una debajo de otra y las tablas se vuelven tarjetas.

Los colores son provisionales (azul oscuro y gris). La paleta final la escogemos antes de B6 y
se cambia en un solo lugar (las variables al inicio de `estadisticas.css`).

## Cómo correrlo

1. Doble clic en `ejecutar_b4.bat` (pide la contraseña de `postgres`). Tiene que terminar en
   **B4 ESTADÍSTICAS = PASS**.
2. Doble clic en `fase-bi/aplicativo/iniciar_local.bat` (pide la contraseña de `powerbi_lector`).
   La primera vez instala las librerías de Python. Se abre `http://localhost:8000`.
3. Opcional: con el aplicativo prendido, `python fase-bi/B4_tableros_app/pruebas/validar_pagina.py`
   (necesita `pip install playwright` y `python -m playwright install chromium`).

## Cuándo damos B4 por cerrado

Los indicadores de la página dan igual que en Power BI y en SQL.

## Resultado

Lo probamos primero en la copia de la base reconstruida con G8 (la misma de B2, con la misma
huella del esquema `bi`). En el computador de Juan Diego la validación de SQL queda en
`salidas/salida_b4.txt` al correr `ejecutar_b4.bat`.

- **SQL contra las funciones del aplicativo:** 69 de 69 en PASS (39 indicadores en tres
  escenarios, 27 sumas de gráficas y 3 de permisos).
- **Página contra los valores oficiales:** las 37 cifras que se ven en las tarjetas de las
  4 páginas, en los escenarios A y B, dan igual que SQL. Como en B3 SQL ya había dado igual
  que Power BI, los tres coinciden en los 13 indicadores (ver `equivalencia_b4.md`).

## Lo que nos pasó al correrlo en el computador de Juan Diego

`ejecutar_b4.bat` dio **B4 ESTADÍSTICAS = PASS (69 de 69)** a la primera. El aplicativo abrió,
pero la página se quedó en "Calculando…" sin cifras. En la ventana del servidor vimos el motivo:
PostgreSQL rechazaba la contraseña de `powerbi_lector`, y el servidor se quedaba reintentando
sin avisarle a la página. Lo arreglamos en dos partes:

- `iniciar_local.ps1` ahora prueba la contraseña antes de arrancar (`servidor/probar_conexion.py`)
  y la vuelve a pedir si no sirve, hasta 3 veces. Si la base no está prendida, lo dice.
- Si con el servidor prendido la base no responde, el servidor contesta en 15 segundos con un
  aviso claro (error 503) y la página lo muestra en vez de quedarse cargando.
- Al volver a arrancarlo, la ventana anterior del servidor seguía abierta ocupando el puerto
  8000, y el navegador le hablaba a esa copia vieja. Ahora `iniciar_local.ps1` revisa si el
  puerto está ocupado, avisa y usa el siguiente libre.
