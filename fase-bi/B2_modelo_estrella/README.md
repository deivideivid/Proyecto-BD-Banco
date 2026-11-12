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
30 segundos.

Después lo corrimos en la base del computador de Juan Diego (PostgreSQL 18.6) con
`ejecutar_b2.bat`, el 12 de noviembre de 2026:

- Terminó con `RESULTADO: OK` y **B2 MODELO ESTRELLA = PASS** (14 de 14 controles).
- La carga tardó 120,7 segundos en ese computador.
- La huella de la carga repetida fue la misma que en la copia de prueba
  (`4149f55080d618b5aed9a6ea3414eef5`), así que los dos modelos son idénticos.
- Los 13 indicadores dieron exactamente los mismos valores del catálogo.
- El rol `banco_bi` leyó `bi`, y le fue negado leer `core.cuenta` y escribir en `bi`.

La salida completa está en `salidas/salida_b2.txt`.
