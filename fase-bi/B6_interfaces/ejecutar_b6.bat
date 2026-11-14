@echo off
REM Banco Andino - Gate B6: agrega en la base las funciones para que el administrador de acceso
REM al aplicativo a los empleados, y las prueba. Doble clic. Pide la contrasena de postgres.
REM Se puede correr varias veces. Requiere B5.
chcp 65001 >nul
cd /d "%~dp0..\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "fase-bi\herramientas\correr_sql.ps1" -Titulo "Banco Andino - B6 accesos del administrador" -Salida "fase-bi\B6_interfaces\salidas\salida_b6.txt" -Scripts "fase-bi\B6_interfaces\sql\b6_01_accesos_admin.sql"
echo.
pause
