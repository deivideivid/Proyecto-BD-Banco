@echo off
REM Banco Andino - Gate B4: crea las funciones de la seccion Estadisticas en el esquema bi y las
REM valida contra el calculo directo en SQL (escenarios A, B y C), las graficas y los permisos.
REM Doble clic. Pide la contrasena de PostgreSQL (usuario postgres). Solo toca el esquema bi.
REM Requiere B2 (esquema bi cargado).
chcp 65001 >nul
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "fase-bi\herramientas\correr_sql.ps1" -Titulo "Banco Andino - B4 estadisticas del aplicativo" -Salida "fase-bi\B4_tableros_app\salidas\salida_b4.txt" -Scripts "fase-bi\B4_tableros_app\sql\b4_01_funciones_estadisticas.sql,fase-bi\B4_tableros_app\sql\b4_02_validar_estadisticas.sql"
echo.
pause
