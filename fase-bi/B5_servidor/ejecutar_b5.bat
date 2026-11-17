@echo off
REM Banco Andino - Gate B5: crea en la base lo que necesita el aplicativo (esquema app, usuario del
REM canal digital, accesos de demostracion y el usuario app_servidor), prueba los permisos de cada
REM rol y al final pide la contrasena nueva de app_servidor (dos veces).
REM Doble clic. Primero pide la contrasena de postgres. Se puede correr varias veces.
chcp 65001 >nul
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "fase-bi\herramientas\correr_sql.ps1" -Titulo "Banco Andino - B5 base del aplicativo" -Salida "fase-bi\B5_servidor\salidas\salida_b5_base.txt" -Scripts "fase-bi\B5_servidor\sql\b5_01_esquema_app.sql,fase-bi\B5_servidor\sql\b5_02_pruebas_bd.sql" -ClaveDeRol "app_servidor"
echo.
pause
