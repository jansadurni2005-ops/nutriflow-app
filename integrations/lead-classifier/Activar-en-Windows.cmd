@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0agente-crm.mjs" (echo Extrae todo el ZIP antes de activar. & pause & exit /b 1)
where node >nul 2>&1 || (echo No se ha encontrado Node.js. & pause & exit /b 1)
node "%~dp0activar-agente.mjs"
if errorlevel 1 pause
