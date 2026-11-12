# B2 · Modelo estrella

En este gate armamos el modelo estrella del banco en el esquema `bi` de la misma base, lo
validamos contra las tablas del banco y fijamos los indicadores que vamos a mostrar.

- `modelo_estrella.md` - qué tablas tiene, el grano de cada una y las decisiones que tomamos.
- `diagrama_estrella.png` y `diagrama_estrella.mmd` - el diagrama del modelo.
- `catalogo_indicadores.md` - los 13 indicadores con su fórmula y sus valores oficiales.
- `sql/` - los 5 scripts (crear, cargar, rol de Power BI, validar e indicadores).
- `ejecutar_b2.bat` - corre todo con la contraseña de PostgreSQL.
- `salidas/salida_b2.txt` - lo que salió al correrlo.

## Cuándo damos B2 por cerrado

- La validación termina en **B2 MODELO ESTRELLA = PASS**: los totales del modelo cuadran al
  peso con los del banco y repetir la carga da lo mismo.
- El rol de Power BI puede leer `bi` y no puede leer ni escribir nada más.

## Resultado

Primero lo construimos y probamos en una copia de la base reconstruida con
`g8_reconstruir_todo.sql` (PostgreSQL 16): los 14 controles dieron PASS y la carga tardó unos
30 segundos. Después lo corrimos en la base de Juan Diego (PostgreSQL 18.6) con `ejecutar_b2.bat`.
