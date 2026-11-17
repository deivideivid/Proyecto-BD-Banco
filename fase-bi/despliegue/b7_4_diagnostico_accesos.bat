@echo off
REM Banco Andino - B7 despliegue, paso 4 (diagnostico): revisa los accesos de demostracion en Neon.
REM Solo lee la base. No muestra contrasenas.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0b7_nube.ps1" -Paso 4
echo.
pause
