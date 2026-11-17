@echo off
REM Banco Andino - B7 despliegue, paso 2: contrasena de app_servidor, tamano de la base, accesos de la nube y DATABASE_URL para Render.
REM Doble clic. Lo que pide (cadenas y contrasenas) no se muestra ni se guarda.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0b7_nube.ps1" -Paso 2
echo.
pause
