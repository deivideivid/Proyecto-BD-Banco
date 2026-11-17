@echo off
REM Banco Andino - B7 despliegue, paso 1: monta la base completa en Neon (G0-G8 + B2, B4, B5, B6). Tarda 20-40 min.
REM Doble clic. Lo que pide (cadenas y contrasenas) no se muestra ni se guarda.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0b7_nube.ps1" -Paso 1
echo.
pause
