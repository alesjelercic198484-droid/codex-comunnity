@echo off
rem  CodeX Community - hitri zagon za testiranje na Windows (dvoklik)
rem  Za produkcijo uporabi: powershell -File scripts\install-windows.ps1
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo  Node.js ni name scenario. Prenesi ga: https://nodejs.org/  (LTS, x64)
  echo  Med namestitvijo pusti kljukico "Add to PATH".
  echo.
  pause
  exit /b 1
)
if not exist config.json (
  echo  config.json manjka - ustvarjam iz config.example.json
  copy /y config.example.json config.json >nul
)
echo  Zaganjam ... stran bo na http://localhost:3000  (admin: /admin)
node server.js
pause
