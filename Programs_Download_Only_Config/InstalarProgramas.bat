@echo off
:: ---------------------------------------------
:: Elevación de privilegios si no es administrador
:: ---------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
:: ---------------------------------------------
:: Ejecutar script PowerShell principal
:: ---------------------------------------------
echo.
echo InstalarProgramas.ps1...
start powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0InstalarProgramas.ps1"
exit /b