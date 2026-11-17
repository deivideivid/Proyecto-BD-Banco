@echo off
REM Banco Andino - Gate B5: prueba los 5 perfiles contra el servidor (lo permitido y lo que debe fallar).
REM Antes: dejar el aplicativo prendido con fase-bi\aplicativo\iniciar_local.bat (en otra ventana).
REM Hace operaciones reales pequenas (descripcion "Prueba B5") y deja la salida en salidas\.
chcp 65001 >nul
cd /d "%~dp0..\.."
set PYTHONIOENCODING=utf-8
"fase-bi\aplicativo\.venv\Scripts\python.exe" "fase-bi\B5_servidor\pruebas\probar_perfiles.py"
echo.
pause
