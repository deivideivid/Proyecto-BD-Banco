@echo off
REM Banco Andino - Gate B2: crea el modelo estrella (esquema bi), lo carga, crea el rol de
REM solo lectura para Power BI, lo valida contra el banco y calcula los indicadores oficiales.
REM Doble clic. Pide la contrasena de PostgreSQL. No toca las tablas del banco: solo el esquema bi.
REM Requiere la base banco_andino_lab cargada (G8) y el archivo evidence\g6_quality_results.csv.
chcp 65001 >nul
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "fase-bi\herramientas\correr_sql.ps1" -Titulo "Banco Andino - B2 modelo estrella" -Salida "fase-bi\B2_modelo_estrella\salidas\salida_b2.txt" -Scripts "fase-bi\B2_modelo_estrella\sql\b2_01_esquema_bi.sql,fase-bi\B2_modelo_estrella\sql\b2_02_cargar_bi.sql,fase-bi\B2_modelo_estrella\sql\b2_03_rol_powerbi.sql,fase-bi\B2_modelo_estrella\sql\b2_04_validar_bi.sql,fase-bi\B2_modelo_estrella\sql\b2_05_kpi_referencia.sql"
echo.
pause
