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
echo Ejecutando ConfigurarProtectorYFondoDePantalla.ps1...
start powershell -NoExit -ExecutionPolicy Bypass -File "%~dp0ConfigurarProtectorYFondoDePantalla.ps1"
exit /b
