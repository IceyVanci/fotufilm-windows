@echo off
rem Double-click build: engine, editor, then one Fotufilm exe in dist\.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
if errorlevel 1 (
  echo.
  echo Build failed - see the message above.
  pause
  exit /b 1
)
echo.
pause