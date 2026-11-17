@echo off
REM Banco Andino - B7 despliegue, paso 3: pruebas de los 5 perfiles contra el enlace de Render.
REM Doble clic. Lo que pide (cadenas y contrasenas) no se muestra ni se guarda.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0b7_nube.ps1" -Paso 3
echo.
pause
