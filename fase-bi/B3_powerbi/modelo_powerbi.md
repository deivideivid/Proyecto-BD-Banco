# B3 · Cómo armamos Power BI

## Conexión

Power BI se conecta a PostgreSQL (`localhost`, base `banco_andino_lab`) en modo **Importar**,
con el usuario **`powerbi_lector`**, que solo puede leer el esquema `bi` (lo creamos en B2). Por
eso el navegador de Power BI solo nos mostró las tablas de `bi`, y no las del banco.

Importamos 10 tablas: las 6 dimensiones, los 3 hechos y `calidad_prueba`. No trajimos
`bi.carga` (es la bitácora de cargas) ni la vista `v_calidad_puntaje`, porque el puntaje lo
calculamos con una medida.

## Relaciones

Power BI detectó las llaves foráneas del esquema `bi`. Encima de eso hicimos dos cambios:

1. **Quitamos** las relaciones de `dim_cuenta` hacia `dim_cliente`, `dim_oficina` y
   `dim_producto`. Abrían un segundo camino desde esas dimensiones hasta las transacciones
   (dimensión → cuenta → transacción), y por eso Power BI había dejado inactiva la relación de
   las transacciones con las cuentas.
2. **Activamos** `fact_transaccion → dim_cuenta` (por `cuenta_key`).

La relación `fact_saldo_cuenta → dim_cuenta` (uno a uno) la dejamos inactiva: los saldos ya
tienen su cliente, oficina, producto y estado en la misma tabla, y si la activábamos se volvía
a formar un camino doble.

Así, un filtro de mes, producto o departamento llega a las transacciones y a los saldos al
mismo tiempo.

## Medidas

Las 13 medidas (K01 a K13) siguen al pie de la letra `B2_modelo_estrella/catalogo_indicadores.md`.
Las creamos pegando `powerbi/medidas.tmdl` en la vista TMDL y dándole Aplicar. Además dejamos
dos de apoyo: **Transacciones rechazadas** y **Cuentas al corte**.

- Las medidas de saldo (K08 a K11) usan `REMOVEFILTERS` sobre la fecha, porque son una foto al
  corte: si alguien filtra un mes, siguen mostrando el saldo del corte.
- El puntaje del quality gate (K12) usa la misma fórmula de G6: peso por severidad y PASS = 1,
  WARNING = 0,5, FAIL = 0.
- Nos pasó que la vista TMDL no acepta comentarios con `//`, así que el archivo quedó sin ellos.

## Páginas

| Página | Qué muestra |
|---|---|
| Resumen | Transacciones, monto movido, clientes con movimientos, cuentas activas, saldo COP y tasa de rechazo; monto por mes; transacciones por tipo |
| Transacciones | Transacciones, ticket promedio, monto USD, tasa de rechazo, rechazadas y reversos; por hora del día; por día de la semana; rechazos por motivo; monto por tipo |
| Clientes y cuentas | Cuentas al corte, activas, en sobregiro, saldo COP y USD; cuentas por estado y por producto; saldo por departamento de la oficina; clientes con más saldo |
| Control y calidad | Puntaje del quality gate y controles en PASS; tabla de controles de cuadre; tabla con las 76 pruebas de G6 |

Las tres primeras páginas tienen filtros de **mes**, **producto** y **departamento de la
oficina**. La de control no los tiene, porque los controles son de toda la base.

**Para celular:** cada página tiene su diseño móvil, con los filtros arriba, las tarjetas de dos
en dos y las gráficas una debajo de la otra.

**Cómo armamos las páginas:** en vez de arrastrar cada gráfica a mano, guardamos el informe como
proyecto de Power BI (`.pbip`), que guarda cada página y cada gráfica como un archivo JSON. Con
`powerbi/generar_paginas.py` creamos esos archivos (posición en computador y en celular), los
pusimos en el proyecto, volvimos a abrirlo y lo guardamos como `BancoAndino.pbix`.

## Lo que falta para la versión final

- **Colores:** las páginas tienen el tema por defecto de Power BI. Cuando definamos la paleta
  del banco (antes de B6), le aplicamos el tema.
- **Días de la semana:** la gráfica los ordena alfabéticamente. Lo corregimos ordenando la
  columna `nombre_dia` por `dia_semana`.
