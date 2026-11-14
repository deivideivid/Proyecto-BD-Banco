@echo off
REM Banco Andino - Arranca el aplicativo en este computador y abre http://localhost:8000
REM Doble clic. Pide la contrasena de powerbi_lector (la misma de Power BI). Ctrl + C para apagarlo.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0iniciar_local.ps1"
echo.
pause
