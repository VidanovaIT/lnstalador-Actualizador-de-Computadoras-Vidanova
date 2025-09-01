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

function EstaInstalado {
    param ([string]$id)
    $apps = winget list --id "$id" 2>$null
    return ($apps -match "$id")
}

function TieneActualizacion {
    param ([string]$id)
    $updates = winget upgrade --id "$id" 2>$null
    return ($updates -match "$id")
}

function ActualizarFuentesWinget {
    Write-Log "Actualizando fuentes de Winget..." "INFO"
    try {
        winget source update | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Fuentes de Winget actualizadas correctamente." "INFO"
        } else {
            Write-Warning "Hubo un problema al actualizar las fuentes de Winget (Código: $LASTEXITCODE)."
        }
    }
    catch {
        Write-Warning "Error al ejecutar winget source update: $_"
    }
}

function InstalarWinget {
    Write-Log "Winget no detectado. Intentando instalarlo..." "INFO"
    try {
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\winget.msixbundle" -UseBasicParsing
        Add-AppxPackage -Path "$env:TEMP\winget.msixbundle"
        Write-Log "Winget instalado correctamente." "INFO"
    }
    catch {
        Write-Warning "Error al instalar Winget: $_"
        exit 1
    }
}

function GetBrowserPath {
    $edgePaths = @(
        "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    $chromePaths = @(
        "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
    )
    $firefoxPaths = @(
        "$env:ProgramFiles (x86)\Mozilla Firefox\firefox.exe",
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
    )

    foreach ($exe in $edgePaths)   { if (Test-Path $exe) { return $exe } }
    foreach ($exe in $chromePaths) { if (Test-Path $exe) { return $exe } }
    foreach ($exe in $firefoxPaths){ if (Test-Path $exe) { return $exe } }
    return $null # Default
}

function InstalarYActualizarProgramas {
    $programas = @(
        @{ nombre = "Google Chrome"; id = "Google.Chrome"; fallbackUrl = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"; archivo = "googlechromestandaloneenterprise64.msi"; fallbackPage = "https://www.google.com/chrome/"},
        @{ nombre = "WhatsApp"; id = "WhatsApp.WhatsApp"; fallbackUrl = "https://get.microsoft.com/installer/download/9NKSQGP7F2NH?cid=website_cta_psi"; archivo = "WhatsAppInstaller.exe"; fallbackPage = "https://www.whatsapp.com/download/windows" },    
        @{ nombre = "AnyDesk"; id = "AnyDesk.AnyDesk"; fallbackUrl = "https://download.anydesk.com/AnyDesk.exe"; archivo = "AnyDesk.exe"; fallbackPage = "https://anydesk.com/es/downloads/windows" },
        @{ nombre = "Thunderbird"; id = "Mozilla.Thunderbird" },
        @{ nombre = "Google Drive"; id = "Google.GoogleDrive"; fallbackUrl = "https://dl.google.com/drive-file-stream/GoogleDriveSetup.exe"; archivo = "GoogleDriveSetup.exe"; fallbackPage = "https://www.google.com/drive/download/" },
        @{ nombre = "Lively Wallpaper"; id = "rocksdanister.LivelyWallpaper" },
        @{ nombre = "WinRAR"; id = "RARLab.WinRAR"; fallbackUrl = "https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-711es.exe"; archivo = "WinRAR-x64.exe"; fallbackPage = "https://www.win-rar.com/download.html" },
        @{ nombre = "Adobe Acrobat Reader"; id = "Adobe.Acrobat.Reader.64-bit"; fallbackPage = "https://get.adobe.com/es/reader/" },
        @{ nombre = "Microsoft Teams"; id = "Microsoft.Teams"; fallbackUrl = "https://statics.teams.cdn.office.net/evergreen-assets/DesktopClient/MSTeamsSetup.exe"; archivo = "MSTeamsSetup.exe"; fallbackPage = "https://www.microsoft.com/es-es/microsoft-teams/download-app" },
        @{ nombre = "VLC Media Player"; id = "VideoLAN.VLC"; fallbackUrl = "https://get.videolan.org/vlc/3.0.21/win32/vlc-3.0.21-win32.exe"; archivo = "vlc-3.0.21-win32.exe"; fallbackPage = "https://www.videolan.org/vlc/download-windows.html" }
    )

    $total = $programas.Count
    $index = 0

    foreach ($programa in $programas) {
        $index++
        $porcentaje = [math]::Round(($index / $total) * 100)
        Write-Log "`n[$porcentaje%] $($programa.nombre)..." "INFO"

        if (!(EstaInstalado $programa.id)) {
            Write-Log "No instalado. Usando Winget..." "INFO"
            winget install --id $($programa.id) --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Log "$($programa.nombre) instalado." "INFO"
            }
            elseif ($programa.fallbackUrl) {
                Write-Warning "Winget falló. Usando método alternativo..."
                InstalarDesdeWeb -nombre $programa.nombre -url $programa.fallbackUrl -archivo $programa.archivo -fallbackPage $programa.fallbackPage
            }
            else {
                Write-Warning "Error instalando $($programa.nombre)."
            }
        } 
        else {
            Write-Log "Ya instalado." "INFO"
            if (TieneActualizacion($programa.id)) {
                Write-Log "Actualizando..." "INFO"
                winget upgrade --id $($programa.id) --silent --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Actualizado correctamente." "INFO"
                }
                else {
                    Write-Warning "Error actualizando $($programa.nombre)."
                }
            }
            else {
                Write-Log "$($programa.nombre) está actualizado." "INFO"
            }
        }
    }
}

function AbrirEnNavegador {
    param([string]$url)
    $browser = GetBrowserPath
    if ($browser) {
        Write-Log "Abriendo en navegador: $browser" "INFO"
        Start-Process -FilePath $browser -ArgumentList $url
    } else {
        Write-Log "No se detecto navegador moderno, abriendo con el predeterminado (Edge/IE)." "WARNING"
        Start-Process $url
    }
}

function InstalarDesdeWeb {
    param (
        [string]$nombre,
        [string]$url,
        [string]$archivo,
        [string]$fallbackPage
    )
    $ruta = "$env:TEMP\$archivo"
    Write-Log "Descargando $nombre desde: $url" "INFO"
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
        }
        if ($archivo.ToLower().EndsWith(".msi")) {
            Write-Log "Usando BITS para descargar $nombre (MSI)..." "INFO"
            Start-BitsTransfer -Source $url -Destination $ruta -ErrorAction Stop
        }
        else {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $url -OutFile $ruta -Headers $headers -UseBasicParsing -ErrorAction Stop
        }


        if (Test-Path $ruta) {
            $tam = (Get-Item $ruta).Length
            $firma = ""
            $esExe = $false

            if ($tam -gt 512) {
                $stream = [System.IO.File]::OpenRead($ruta)
                $bytes = New-Object byte[] 2
                $stream.Read($bytes, 0, 2) | Out-Null
                $firma = [System.Text.Encoding]::ASCII.GetString($bytes)
                $stream.Close()
                if ($firma -eq "MZ") { $esExe = $true }
            }

            # Si es un MSI, usar msiexec
            if ($archivo.ToLower().EndsWith(".msi")) {
                Write-Log "Detectado instalador MSI. Ejecutando con msiexec..." "INFO"
                try {
                    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$ruta`" /quiet /norestart" -Wait
                    Write-Log "$nombre instalado usando MSI." "SUCCESS"
                }
                catch {
                    Write-Warning "Error ejecutando instalador MSI de $nombre."
                    if ($fallbackPage) {
                        Write-Log "Abriendo página oficial para instalación manual de $nombre..." "INFO"
                        AbrirEnNavegador $fallbackPage
                        Read-Host "Presione ENTER para continuar..."
                    }
                }
            }
            elseif ($esExe -or ($archivo.ToLower().EndsWith(".exe") -and $tam -gt 800000)) {
                Write-Log "Lanzando instalador EXE de $nombre ($archivo, tam: $([Math]::Round($tam/1MB,2)) MB)..." "INFO"
                try {
                    $proc = Start-Process -FilePath $ruta -PassThru
                    Start-Sleep -Seconds 7
                    if (!$proc.HasExited) {
                        Write-Log "$nombre sigue ejecutándose. Continuando sin esperar..." "INFO"
                    }
                }
                catch {
                    Write-Warning "No se pudo ejecutar el instalador EXE de $nombre."
                    if ($fallbackPage) {
                        Write-Log "Abriendo página oficial para instalación manual de $nombre..." "INFO"
                        AbrirEnNavegador $fallbackPage
                        Read-Host "Presione ENTER para continuar..."
                    }
                }
            }
            else {
                $content = Get-Content $ruta -TotalCount 1
                if ($content -like "<*" -or $content -like "<?*") {
                    Write-Warning "La descarga de $nombre no es ejecutable (posible HTML, tam: $([Math]::Round($tam/1KB,2)) KB)."
                } else {
                    Write-Warning "Descarga de $nombre parece incompleta o corrupta (tam: $([Math]::Round($tam/1KB,2)) KB, firma: $firma)."
                }
                Remove-Item $ruta -Force
                if ($fallbackPage) {
                    Write-Log "Abriendo página oficial para instalación manual de $nombre..." "INFO"
                    AbrirEnNavegador $fallbackPage
                    Read-Host "Presione ENTER para continuar..."
                }
            }
        }
        else {
            Write-Warning "No se descargó el instalador de $nombre." "WARNING"
            if ($fallbackPage) {
                Write-Log "Abriendo página oficial para instalación manual de $nombre..." "INFO"
                AbrirEnNavegador $fallbackPage
                Read-Host "Presione ENTER para continuar..."
            }
        }
    }
    catch {
        Write-Warning "Error descargando/ejecutando $nombre."
        if ($fallbackPage) {
            Write-Log "Abriendo página oficial para instalación manual de $nombre..." "INFO"
            AbrirEnNavegador $fallbackPage
            Read-Host "Presione ENTER para continuar..."
        }
    }
}

# =================== BLOQUE PRINCIPAL AQUi =====================
try {
    Write-Log "`nIniciando mantenimiento del sistema..." "INFO"
    VerificarConectividad

    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        InstalarWinget
        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Winget no disponible tras intento de instalacion."
        }
    }
    ActualizarFuentesWinget

    Write-Host "`nVerificacion inicial de Winget."
    Write-Host "`nMostrando lista de paquetes (winget list)."
    winget list --accept-source-agreements --upgrade-available

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Winget no pudo listar los paquetes. Verifica tu conexion a Internet o la instalacion de Winget."
        Read-Host "Presiona ENTER para continuar..."
        exit 1
    }
    ##Aqui funcion de Programas
    InstalarYActualizarProgramas
    
}
catch {
    Write-Log "Error critico: $_" "ERROR"
}
finally {
    Read-Host "`nMantenimiento completado o detenido. Presione ENTER para salir"
}