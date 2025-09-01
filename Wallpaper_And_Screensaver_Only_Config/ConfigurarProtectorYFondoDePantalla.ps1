# Instalador y Actualizador de Software para Primeras Computadoras VIDANOVA
# Ejecutar como Administrador
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File '$PSCommandPath'" -Verb RunAs
    exit
}

# Definir ruta log
$scriptPath = Split-Path -Parent $PSCommandPath
$global:LogFile = "$scriptPath\actualizacion_instalacion_log.txt"

$ErrorActionPreference = "Stop"

# =================== TODAS LAS FUNCIONES AQUi =====================

function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"

    switch ($Level) {
        "ERROR"   { Write-Host $line -ForegroundColor Red } 
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        default   { Write-Host $line }
    }

    if ($global:LogFile) {
        Add-Content -Path $global:LogFile -Value $line
    }
}

function VerificarConectividad {
    Write-Log "Verificando conectividad a Internet..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Log "Conectividad verificada." "INFO"
        } else {
            Write-Warning "Conectividad fallida. Codigo de estado: $($response.StatusCode)"
        }
    }
    catch {
        Write-Warning "Error al verificar conectividad: $_"
    }
}

function DescargarFondosYProtectorDePantalla {
    Write-Log "Iniciando descarga de fondos y protector..." "INFO"
    try {
        # Carpeta de Fondos
        $pictures = [Environment]::GetFolderPath("MyPictures")
        $fondosPath = Join-Path $pictures "Fondos"

        $fondos = @(
            @{ url = "https://drive.usercontent.google.com/download?id=1O2drBdLD7aPkpIdIGPB4hhUC6OH1LIh5&export=download"; nombre = "Fondo de Escritorio.png" },
            @{ url = "https://drive.usercontent.google.com/download?id=1tOv6xbWirAet1gdMtESQYjaqTBK9RqI8&export=download"; nombre = "Fondo de Zoom.png" }
        )

        $videos = [Environment]::GetFolderPath("MyVideos")
        $videoDestino = Join-Path $videos "PROTECTOR-1.mp4"

        # Verificar si ya existen todos los archivos
        $fondosInstalados = $true
        foreach ($fondo in $fondos) {
            $destino = Join-Path $fondosPath $fondo.nombre
            if (!(Test-Path $destino)) { $fondosInstalados = $false }
        }
        $videoInstalado = Test-Path $videoDestino

        if ($fondosInstalados -and $videoInstalado) {
            Write-Log "Fondos y protector ya instalados. Omitiendo descarga." "INFO"
            return
        }

        if (!(Test-Path $pictures)) {
            New-Item -ItemType Directory -Path $pictures | Out-Null
            Write-Log "Carpeta de Imágenes creada: $pictures" "INFO"
        }

        if (!(Test-Path $fondosPath)) {
            New-Item -ItemType Directory -Path $fondosPath | Out-Null
            Write-Log "Carpeta de Fondos creada: $fondosPath" "INFO"
        }

        foreach ($fondo in $fondos) {
            $destino = Join-Path $fondosPath $fondo.nombre
            Write-Log "Descargando $($fondo.nombre)..." "INFO"
            Invoke-WebRequest -Uri $fondo.url -OutFile $destino -UseBasicParsing
        }

        Write-Log "Fondos descargados correctamente en $fondosPath" "INFO"

        # Descargar Lively.scr y moverlo a Windows
        $livelyScrUrl = "https://drive.usercontent.google.com/download?id=1TkWfPTYsExpMqNspYee1zEXAP4vVXqtt&export=download"
        $livelyScrTemp = Join-Path $env:TEMP "Lively.scr"
        $livelyScrDestino = Join-Path $env:SystemRoot "Lively.scr"

        if (!(Test-Path $livelyScrDestino)) {
            Write-Log "Descargando Lively.scr..." "INFO"
            Invoke-WebRequest -Uri $livelyScrUrl -OutFile $livelyScrTemp -UseBasicParsing

            if (Test-Path $livelyScrTemp) {
                try {
                    Copy-Item -Path $livelyScrTemp -Destination $livelyScrDestino -Force
                    Write-Log "Lively.scr copiado correctamente a $livelyScrDestino" "INFO"
                }
                catch {
                    Write-Warning "Error copiando Lively.scr a C:\Windows. Ejecuta como Administrador. $_"
                }
            } else {
                Write-Warning "No se pudo descargar Lively.scr."
            }
        } else {
            Write-Log "Lively.scr ya existe en $livelyScrDestino. Omitiendo descarga." "INFO"
        }

        # Descargar video del protector de pantalla
        if (!(Test-Path $videos)) {
            New-Item -ItemType Directory -Path $videos | Out-Null
            Write-Log "Carpeta de Videos creada: $videos" "INFO"
        }

        $videoUrl = "https://drive.usercontent.google.com/download?id=1bZyh8AuVB9I_ezN1bEHdtypxR5uXCCoB&export=download"

        Write-Log "Descargando PROTECTOR-1.mp4..." "INFO"
        Start-BitsTransfer -Source $videoUrl -Destination $videoDestino

        Write-Log "Protector descargado correctamente en $videos" "INFO"
    }
    catch {
        Write-Warning "Error al descargar fondos o protector: $_"
    }
}

function ConfigurarLivelyProtectorYFondo {
    Write-Log "Iniciando configuración SOLO del protector de pantalla Lively..." "INFO"
    try {
        $livelyPaths = @(
            "C:\Program Files\Lively Wallpaper\Lively.exe",
            "C:\Program Files\Lively\Lively.exe",
            "C:\Program Files (x86)\Lively Wallpaper\Lively.exe",
            "C:\Program Files (x86)\Lively\Lively.exe"
        )
        $livelyExe = $null
        foreach ($path in $livelyPaths) {
            if (Test-Path $path) {
                $livelyExe = $path
                break
            }
        }
        if (-not $livelyExe) {
            $found = Get-ChildItem -Path "C:\Program Files", "C:\Program Files (x86)" -Recurse -ErrorAction SilentlyContinue -Filter "Lively.exe" | Select-Object -First 1
            if ($found) { $livelyExe = $found.FullName }
        }
        if (-not $livelyExe) {
            Write-Warning "No se encontró Lively.exe en una ruta conocida. Por favor, instala Lively Wallpaper primero."
            return
        }

        $videoPath = Join-Path ([Environment]::GetFolderPath("MyVideos")) "PROTECTOR-1.mp4"
        $fondoPath = Join-Path ([Environment]::GetFolderPath("MyPictures")) "Fondos\Fondo de Escritorio.png"
        $destScr = "C:\Windows\Lively.scr"

        # 0. Establecer fondo clásico de Windows primero (respaldo visual inmediato)
        if (Test-Path $fondoPath) {
            Write-Log "Estableciendo fondo clásico de Windows como respaldo..." "INFO"
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name wallpaper -Value $fondoPath
            RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters
            Write-Log "Fondo clásico aplicado exitosamente como base." "INFO"
        } else {
            Write-Warning "No se encontró la imagen de fondo clásico en: $fondoPath"
        }

        # 1. Importar el video a la biblioteca de Lively
        if (Test-Path $videoPath) {
            Write-Log "Importando video a la biblioteca de Lively..." "INFO"
            Start-Process -FilePath $livelyExe -ArgumentList "addwallpaper", "`"$videoPath`""
        } else {
            Write-Warning "No se encontró el archivo de video en: $videoPath"
            return
        }

        # 2. Registrar Lively.scr como protector de pantalla
        if (Test-Path $destScr) {
            Write-Log "Configurando Lively como protector de pantalla en Windows..." "INFO"
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "SCRNSAVE.EXE" -Value $destScr
            Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value 300
            Write-Log "Protector de pantalla configurado correctamente (5 minutos)." "INFO"

            # 3. Aplicar el video como fondo temporalmente para activar el protector
            Write-Log "Aplicando video como fondo temporalmente para el protector..." "INFO"
            Start-Process -FilePath $livelyExe -ArgumentList "setwp", "--file", "`"$videoPath`""
            Start-Sleep -Seconds 5

            # 4. Cerrar el fondo activo (el protector ya tomó el video)
            Write-Log "Cerrando fondo activo de Lively..." "INFO"
            Start-Process -FilePath $livelyExe -ArgumentList "closewp", "-1"
            Start-Sleep -Seconds 2

            Write-Log "Proceso de configuración del protector completado exitosamente." "INFO"
        } else {
            Write-Warning "No se encontró Lively.scr en $destScr"
        }
    }
    catch {
        Write-Warning "Error en configuración de Lively protector: $_"
    }
}

# =================== BLOQUE PRINCIPAL AQUi =====================
try {
    Write-Log "`nIniciando mantenimiento del sistema..." "INFO"
    VerificarConectividad
    
    # Descargar fondos y video de protector de pantalla
    DescargarFondosYProtectorDePantalla

    # Configurar Lively, fondo y protector de pantalla
    ConfigurarLivelyProtectorYFondo
}
catch {
    Write-Log "Error critico: $_" "ERROR"
}
finally {
    Read-Host "`nMantenimiento completado o detenido. Presione ENTER para salir"
}