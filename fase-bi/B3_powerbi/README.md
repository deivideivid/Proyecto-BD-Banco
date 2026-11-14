# B3 · Tableros en Power BI

En este gate conectamos Power BI al modelo estrella (`bi`), creamos las medidas del catálogo y
armamos las 4 páginas, con su versión para celular.

- `BancoAndino.pbix` - el archivo de Power BI con el modelo, las medidas y las 4 páginas.
- `modelo_powerbi.md` - cómo lo conectamos, las relaciones, las medidas y las páginas.
- `equivalencia_b3.md` - la comparación de los 13 indicadores entre SQL y Power BI.
- `powerbi/medidas.tmdl` - las 13 medidas (más 2 de apoyo) que pegamos en la vista TMDL.
- `powerbi/equivalencia_b3.dax` - la consulta DAX con la que comparamos contra SQL.
- `powerbi/generar_paginas.py` - el script que arma las páginas en formato PBIR.

## Cuándo damos B3 por cerrado

- Mínimo 7 indicadores dan igual en SQL y en Power BI, con los mismos filtros.
- Queda el archivo `.pbix` con las 4 páginas y su diseño para celular.

## Resultado

Lo hicimos el 12 de noviembre de 2026 en el computador de Juan Diego. Los **13 indicadores dan
exactamente lo mismo que SQL** en los dos escenarios (ver `equivalencia_b3.md`), y quedaron las
4 páginas con diseño para computador y para celular.
