@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0quality.mjs" (echo En Descargas, haz clic derecho en el ZIP y elige Extraer todo. Abre este archivo desde la carpeta extraida. & pause & exit /b 1)
where node >nul 2>&1 || (echo Instala Node.js 22 o posterior desde nodejs.org. & pause & exit /b 1)
where ollama >nul 2>&1 || (echo Instala Ollama desde ollama.com/download/windows. & pause & exit /b 1)
set OLLAMA_HOST=127.0.0.1:11434
set OLLAMA_NO_CLOUD=1
ollama pull qwen3:4b-instruct-2507-q4_K_M || (echo No se pudo cargar el modelo local. & pause & exit /b 1)
echo La prueba usa conversaciones ficticias. Puede tardar varios minutos: deja abierta esta ventana.
node quality.mjs
if errorlevel 1 goto review
echo Pruebas sinteticas superadas. Manychat no ha sido conectado ni modificado.
pause
exit /b 0
:review
echo Pendiente de revision; no activar en contactos reales.
pause
exit /b 1
