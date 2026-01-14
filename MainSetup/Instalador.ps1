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

# ========================= TODAS LAS FUNCIONES AQUI ===========================
# =================== Funciones de registro y conectividad =====================
# Configurar el registro de eventos
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$ToEventLog = $false
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"

    switch ($Level) {
        "ERROR" { Write-Host $line -ForegroundColor Red } 
        "WARNING" { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }

    if ($global:LogFile) {
        Add-Content -Path $global:LogFile -Value $line
    }

    if ($ToEventLog) {
        $validLevels = @{ "INFO" = "Information"; "WARNING" = "Warning"; "ERROR" = "Error" }
        $entryType = $validLevels[$Level.ToUpper()] 
        if ($entryType) {
            $source = "MyPowerShellScript"
            if (-not (Get-EventLog -LogName Application -Source $source -ErrorAction SilentlyContinue)) {
                New-EventLog -LogName Application -Source $source
            }
            Write-EventLog -LogName Application -Source $source -EntryType $entryType -EventId 100 -Message $Message
        }
    }
}


# Funciones de conectividad
function VerificarConectividad {
    Write-Log "Verificando conectividad a Internet..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Log "Conectividad verificada." "INFO"
        }
        else {
            Write-Warning "Conectividad fallida. Codigo de estado: $($response.StatusCode)"
        }
    }
    catch {
        Write-Warning "Error al verificar conectividad: $_"
    }
}

# =================== Funciones Actualizador de Controladores de Computadora =====================
# Detectar fabricante de la computadora
function DetectarFabricante {
    try {
        $fab = (Get-CimInstance -Class Win32_ComputerSystem).Manufacturer
        return $fab.Trim()
    }
    catch {
        Write-Warning "No se pudo detectar el fabricante: $_"
        return "Desconocido"
    }
}

# Descarga y ejecuta SDI Lite para instalar drivers automaticamente
function UsarSDILite {
    $downloadPage = "https://sdi-tool.org/download/"
    $zipPath = "$env:TEMP\SDI_Lite.zip"
    $extractPath = "$env:TEMP\SDI_Lite"

    Write-Log "Buscando SDI Lite..." "INFO"

    try {
        $html = Invoke-WebRequest -Uri $downloadPage -UseBasicParsing
        $matches = [regex]::Matches($html.Content, 'https://sdi-tool\.org/releases/SDI_R\d+\.zip')
        if ($matches.Count -eq 0) {
            Write-Warning "No se encontro enlace de descarga."
            return
        }

        $latestUrl = $matches[0].Value
        Write-Log "Iniciando descarga desde: $latestUrl" "INFO"
        Write-Log "Descargando SDI Lite (esto puede tardar unos minutos)..." "INFO"
        Invoke-WebRequest -Uri $latestUrl -OutFile $zipPath

        if (Test-Path $zipPath) {
            Write-Log "Descarga completada. Preparando extraccion..." "INFO"

            if (Test-Path $extractPath) {
                Write-Log "Limpiando carpeta temporal existente antes de extraer..." "INFO"
                Remove-Item -Path $extractPath -Recurse -Force
            }

            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            Write-Log "Extraccion completada. Buscando ejecutable..." "INFO"

            $sdiExe = Get-ChildItem -Path $extractPath -Recurse -Filter "SDI_x64_*.exe" | Select-Object -First 1

            if (-not $sdiExe) {
                $sdiExe = Get-ChildItem -Path $extractPath -Recurse -Filter "SDI_R*.exe" | Select-Object -First 1
            }

            if ($sdiExe) {
                Write-Log "Agregando reglas de firewall para SDI Lite..." "INFO"
                New-NetFirewallRule -DisplayName "SDI Lite (Privada)" -Direction Inbound -Program $sdiExe.FullName -Action Allow -Profile Private -ErrorAction SilentlyContinue
                New-NetFirewallRule -DisplayName "SDI Lite (Publica)" -Direction Inbound -Program $sdiExe.FullName -Action Allow -Profile Public -ErrorAction SilentlyContinue

                # Paso 1: Descargar DriverPacks
                Write-Log "Paso 1: Ejecutando autoupdate para descargar solo lo necesario..." "INFO"
                Start-Process -FilePath $sdiExe.FullName `
                    -ArgumentList "-autoupdate", "-connections:200", "-autoclose" `
                    -Wait
                Write-Log "DriverPacks descargados correctamente." "INFO"

                # Paso 2: Abrir interfaz grafica para instalacion manual
                Write-Log "Paso 2: Abriendo SDI Lite en modo grafico para instalacion manual." "INFO"
                Start-Process -FilePath $sdiExe.FullName -WindowStyle Normal
                Write-Log "SDI Lite se esta ejecutando de forma independiente para instalacion manual. Puedes continuar con el resto del mantenimiento." "INFO"

            }
            else {
                Write-Warning "No se encontro el ejecutable principal en la carpeta extraida."
            }
        }
        else {
            Write-Warning "El archivo ZIP no se descargo correctamente. No se encontro: $zipPath"
        }
    }
    catch {
        Write-Warning "Error SDI Lite: $_"
    }
}

# Funcion auxiliar para pedir confirmacion (y/n) o (Y/N)
function PedirConfirmacion {
    param([string]$pregunta)
    
    do {
        $respuesta = Read-Host $pregunta
        if ($respuesta -match "^[ySN]$|^[yN]$") {
            return $respuesta.ToUpper() -eq "Y"
        }
        Write-Host "Por favor responde con 'y' o 'n' (o 'Y' o 'N')." -ForegroundColor Yellow
    } while ($true)
}

# Instalar soporte de fabricante 
function InstalarSoporteFabricante {
    param ([string]$fab)

    Write-Log "Verificando soporte del fabricante..." "INFO"
    Write-Log "Valor de fabricante detectado: '$fab'" "DEBUG"

    # Normalizacion de fabricante
    $fabOriginal = $fab
    $fab = $fab.Trim().ToLower()
    switch -Regex ($fab) {
        "hewlett-packard|hp inc|hp" { $fab = "HP"; break }
        "dell inc|dell" { $fab = "Dell"; break }
        "lenovo" { $fab = "Lenovo"; break }
        "acer" { $fab = "Acer"; break }
        "asus|asustek" { $fab = "ASUS"; break }
        "gigabyte" { $fab = "Gigabyte"; break }
        "msi" { $fab = "MSI"; break }
        "samsung" { $fab = "Samsung"; break }
        "toshiba|dynabook" { $fab = "Toshiba"; break }
        "microsoft corporation" { $fab = "Microsoft"; break }
        "google" { $fab = "Google"; break }
        "lg electronics|lg" { $fab = "LG"; break }
        default { $fab = "Desconocido" }
    }

    Write-Log "Fabricante normalizado: '$fab'" "DEBUG"

    $urls = @{
        "Dell"      = "https://www.dell.com/support/home/es-es/drivers/driversdetails?driverid=0K9T7"
        "HP"        = "https://support.hp.com/ec-es/help/hp-support-assistant"
        "Lenovo"    = "https://support.lenovo.com/ec/es/solutions/ht037099"
        "Acer"      = "https://www.acer.com/ar-es/support/drivers-and-manuals"
        "ASUS"      = "https://www.asus.com/support/Download-Center/"
        "Gigabyte"  = "https://www.gigabyte.com/Consumer/Software/GIGABYTE-Control-Center/global/"
        "MSI"       = "https://www.msi.com/Landing/MSI-Center"
        "Samsung"   = "https://www.samsung.com/latin/support/downloadcenter/"
        "Toshiba"   = "https://support.dynabook.com/"
        "Microsoft" = "https://support.microsoft.com/es-es/downloads"
        "LG"        = "https://www.lg.com/us/support/software-firmware"
        "Google"    = "https://support.google.com/chromebook/answer/177889?hl=es"
    }

    if ($fab -eq "Desconocido" -or !$urls.ContainsKey($fab)) {
        Write-Warning "Fabricante no reconocido. Se usará SDI Lite como solucion de respaldo." "WARNING"
        UsarSDILite
        return
    }

    if ($fab -match "innotek|vmware|virtualbox|qemu") {
        Write-Warning "Entorno virtual detectado. Omitiendo soporte de fabricante."
        return
    }

    Write-Log "Fabricante soportado. Se recomienda usar la página oficial para drivers:" "INFO"
    Write-Log " - ${fab}: $($urls[$fab])" "INFO"
    
    # Permitir al usuario decidir si usar SDI Lite como alternativa
    Write-Host ""
    Write-Host "________________________________________________" -ForegroundColor Cyan
    Write-Host "¿Deseas usar SDI Lite como herramienta alternativa?" -ForegroundColor Cyan
    Write-Host "SDI Lite descargara automáticamente los drivers mas recientes." -ForegroundColor Cyan
    Write-Host "________________________________________________" -ForegroundColor Cyan
    Write-Host ""
    
    $usarSDILite = PedirConfirmacion "¿Usar SDI Lite? (y/n): "
    
    if ($usarSDILite) {
        Write-Log "Usuario eligió usar SDI Lite." "INFO"
        UsarSDILite
    }
    else {
        Write-Log "Usuario decidió no usar SDI Lite en este momento." "INFO"
        Write-Host "Puedes visitar la página oficial del fabricante más adelante si lo necesitas." -ForegroundColor Green
    }

}
# =================== Funciones de Instalacion y Actualizacion de Programas =====================
# Esta funcion crea un acceso directo en el escritorio para un programa instalado
function CrearAccesoDirectoEscritorio {
    param(
        [string]$nombrePrograma,
        [string]$idPrograma
    )
    
    try {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $WshShell = New-Object -ComObject WScript.Shell
        
        # Rutas comunes donde buscar ejecutables
        $rutasComunes = @{
            "Google.Chrome" = @(
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "$env:ProgramFiles (x86)\Google\Chrome\Application\chrome.exe"
            )
            "WhatsApp.WhatsApp" = @(
                "$env:LOCALAPPDATA\WhatsApp\WhatsApp.exe",
                "$env:ProgramFiles\WindowsApps\*WhatsApp*\WhatsApp.exe"
            )
            "AnyDesk.AnyDesk" = @(
                "$env:ProgramFiles (x86)\AnyDesk\AnyDesk.exe",
                "$env:ProgramFiles\AnyDesk\AnyDesk.exe",
                "$env:LOCALAPPDATA\AnyDesk\AnyDesk.exe"
            )
            "Mozilla.Thunderbird" = @(
                "$env:ProgramFiles\Mozilla Thunderbird\thunderbird.exe",
                "$env:ProgramFiles (x86)\Mozilla Thunderbird\thunderbird.exe"
            )
            "Google.GoogleDrive" = @(
                "$env:ProgramFiles\Google\Drive File Stream\*\GoogleDriveFS.exe",
                "$env:LOCALAPPDATA\Google\Drive\GoogleDriveFS.exe"
            )
            "rocksdanister.LivelyWallpaper" = @(
                "$env:LOCALAPPDATA\Programs\Lively Wallpaper\Lively.exe",
                "$env:ProgramFiles\Lively Wallpaper\Lively.exe"
            )
            "RARLab.WinRAR" = @(
                "$env:ProgramFiles\WinRAR\WinRAR.exe",
                "$env:ProgramFiles (x86)\WinRAR\WinRAR.exe"
            )
            "Adobe.Acrobat.Reader.64-bit" = @(
                "$env:ProgramFiles\Adobe\Acrobat DC\Acrobat\Acrobat.exe",
                "$env:ProgramFiles (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe",
                "$env:ProgramFiles\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
            )
            "Microsoft.Teams" = @(
                "$env:LOCALAPPDATA\Microsoft\Teams\current\Teams.exe",
                "$env:ProgramFiles\Microsoft\Teams\current\Teams.exe"
            )
            "VideoLAN.VLC" = @(
                "$env:ProgramFiles\VideoLAN\VLC\vlc.exe",
                "$env:ProgramFiles (x86)\VideoLAN\VLC\vlc.exe"
            )
            "Zoom.Zoom" = @(
                "$env:ProgramFiles\Zoom\bin\Zoom.exe",
                "$env:ProgramFiles (x86)\Zoom\bin\Zoom.exe",
                "$env:APPDATA\Zoom\bin\Zoom.exe"
            )
            "Spotify.Spotify" = @(
                "$env:APPDATA\Spotify\Spotify.exe",
                "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe"
            )
        }
        
        # Buscar ejecutable del programa
        $ejecutable = $null
        if ($rutasComunes.ContainsKey($idPrograma)) {
            foreach ($ruta in $rutasComunes[$idPrograma]) {
                # Manejar rutas con comodines
                if ($ruta -like "*`**") {
                    $encontrados = Get-ChildItem -Path (Split-Path $ruta -Parent) -Filter (Split-Path $ruta -Leaf) -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($encontrados) {
                        $ejecutable = $encontrados.FullName
                        break
                    }
                }
                elseif (Test-Path $ruta) {
                    $ejecutable = $ruta
                    break
                }
            }
        }
        
        # Si no se encontró, buscar en el menú inicio
        if (-not $ejecutable) {
            $startMenuPaths = @(
                "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
                "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
            )
            
            foreach ($startPath in $startMenuPaths) {
                $lnkFiles = Get-ChildItem -Path $startPath -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -like "*$nombrePrograma*" } | 
                    Select-Object -First 1
                
                if ($lnkFiles) {
                    $shortcut = $WshShell.CreateShortcut($lnkFiles.FullName)
                    $ejecutable = $shortcut.TargetPath
                    if ($ejecutable -and (Test-Path $ejecutable)) {
                        break
                    }
                }
            }
        }
        
        # Crear acceso directo si se encontró el ejecutable
        if ($ejecutable -and (Test-Path $ejecutable)) {
            $shortcutPath = Join-Path $desktop "$nombrePrograma.lnk"
            
            # Si ya existe, no recrear
            if (Test-Path $shortcutPath) {
                Write-Log "   ↳ Acceso directo ya existe en escritorio" "DEBUG"
                return
            }
            
            $shortcut = $WshShell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = $ejecutable
            $shortcut.WorkingDirectory = Split-Path $ejecutable -Parent
            $shortcut.Save()
            
            Write-Log "   ↳ Acceso directo creado en escritorio: $nombrePrograma.lnk" "INFO"
        }
        else {
            Write-Log "   ↳ No se pudo encontrar ejecutable para crear acceso directo de $nombrePrograma" "DEBUG"
        }
    }
    catch {
        Write-Log "   ↳ Error creando acceso directo para $nombrePrograma : $_" "DEBUG"
    }
    finally {
        if ($WshShell) {
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WshShell) | Out-Null
        }
    }
}

# Esta funcion instala Winget si no esta disponible.
function InicializarWinget {
    Write-Host "`n--- Verificacion inicial de Winget ---`n"

    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Winget no detectado. Intentando instalarlo..." "INFO"
        try {
            Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$env:TEMP\winget.msixbundle" -UseBasicParsing
            Add-AppxPackage -Path "$env:TEMP\winget.msixbundle"
            Write-Log "Winget instalado correctamente." "INFO"
        }
        catch {
            Write-Warning "Error al instalar Winget: $_"
            throw "Winget no disponible tras intento de instalacion."
        }

        # Verifica nuevamente si esta disponible
        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Winget no disponible tras intento de instalacion."
        }
    }

    Write-Log "Actualizando fuentes de Winget..." "INFO"
    try {
        winget source update | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Fuentes de Winget actualizadas correctamente." "INFO"
        }
        else {
            Write-Warning "Hubo un problema al actualizar las fuentes de Winget (Codigo: $LASTEXITCODE)."
        }
    }
    catch {
        Write-Warning "Error al ejecutar winget source update: $_"
    }

    # Mostrar lista de paquetes actualizables
    Write-Host "`nMostrando lista de paquetes con actualizaciones disponibles (winget list)."
    Write-Host "Si es la primera vez, puede pedir aceptar terminos. Presiona Y y ENTER si corresponde.`n"

    winget list --accept-source-agreements --upgrade-available

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Winget no pudo listar los paquetes. Verifica tu conexion a Internet o la instalacion de Winget."
        Read-Host "Presiona ENTER para continuar..."
        exit 1
    }
}

# Esta funcion abre una URL en el navegador predeterminado o en uno especifico si se encuentra.
# Si no se encuentra un navegador moderno, usa el predeterminado (Edge/IE)
function AbrirEnNavegador {
    param([string]$url)

    $browser = $null

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

    foreach ($exe in $edgePaths) { if (Test-Path $exe) { $browser = $exe; break } }
    if (-not $browser) {
        foreach ($exe in $chromePaths) { if (Test-Path $exe) { $browser = $exe; break } }
    }
    if (-not $browser) {
        foreach ($exe in $firefoxPaths) { if (Test-Path $exe) { $browser = $exe; break } }
    }

    if ($browser) {
        Write-Log "Abriendo en navegador: $browser" "INFO"
        Start-Process -FilePath $browser -ArgumentList $url
    }
    else {
        Write-Log "No se detecto navegador moderno, abriendo con el predeterminado (Edge/IE)." "WARNING"
        Start-Process $url
    }
}

# Esta funcion descarga un archivo desde una URL y lo instala si es un ejecutable o MSI.
# Si la descarga falla o el archivo no es valido, abre una pagina de instalacion manual.
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
                    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i "$ruta" /quiet /norestart" -Wait
                    Write-Log "$nombre instalado usando MSI." "SUCCESS"
                }
                catch {
                    Write-Warning "Error ejecutando instalador MSI de $nombre."
                    if ($fallbackPage) {
                        Write-Log "Abriendo pagina oficial para instalacion manual de $nombre..." "INFO"
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
                        Write-Log "$nombre sigue ejecutandose. Continuando sin esperar..." "INFO"
                    }
                }
                catch {
                    Write-Warning "No se pudo ejecutar el instalador EXE de $nombre."
                    if ($fallbackPage) {
                        Write-Log "Abriendo pagina oficial para instalacion manual de $nombre..." "INFO"
                        AbrirEnNavegador $fallbackPage
                        Read-Host "Presione ENTER para continuar..."
                    }
                }
            }
            else {
                $content = Get-Content $ruta -TotalCount 1
                if ($content -like "<" -or $content -like "<?") {
                    Write-Warning "La descarga de $nombre no es ejecutable (posible HTML, tam: $([Math]::Round($tam/1KB,2)) KB)."
                }
                else {
                    Write-Warning "Descarga de $nombre parece incompleta o corrupta (tam: $([Math]::Round($tam/1KB,2)) KB, firma: $firma)."
                }
                Remove-Item $ruta -Force
                if ($fallbackPage) {
                    Write-Log "Abriendo pagina oficial para instalacion manual de $nombre..." "INFO"
                    AbrirEnNavegador $fallbackPage
                    Read-Host "Presione ENTER para continuar..."
                }
            }
        }
        else {
            Write-Warning "No se descargo el instalador de $nombre." "WARNING"
            if ($fallbackPage) {
                Write-Log "Abriendo pagina oficial para instalacion manual de $nombre..." "INFO"
                AbrirEnNavegador $fallbackPage
                Read-Host "Presione ENTER para continuar..."
            }
        }
    }
    catch {
        Write-Warning "Error descargando/ejecutando $nombre."
        if ($fallbackPage) {
            Write-Log "Abriendo pagina oficial para instalacion manual de $nombre..." "INFO"
            AbrirEnNavegador $fallbackPage
            Read-Host "Presione ENTER para continuar..."
        }
    }
}

# Esta funcion instala y actualiza una lista de programas comunes usando Winget.
# Si Winget falla, intenta descargar e instalar desde la web.
function InstalarYActualizarProgramas {
    $programas = @(
        @{ nombre = "Google Chrome"; id = "Google.Chrome"; fallbackUrl = "https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi"; archivo = "googlechromestandaloneenterprise64.msi"; fallbackPage = "https://www.google.com/chrome/" },
        @{ nombre = "WhatsApp"; id = "WhatsApp.WhatsApp"; fallbackUrl = "https://get.microsoft.com/installer/download/9NKSQGP7F2NH?cid=website_cta_psi"; archivo = "WhatsAppInstaller.exe"; fallbackPage = "https://www.whatsapp.com/download/windows" },    
        @{ nombre = "AnyDesk"; id = "AnyDesk.AnyDesk"; fallbackUrl = "https://download.anydesk.com/AnyDesk.exe"; archivo = "AnyDesk.exe"; fallbackPage = "https://anydesk.com/es/downloads/windows" },
        @{ nombre = "Thunderbird"; id = "Mozilla.Thunderbird" },
        @{ nombre = "Google Drive"; id = "Google.GoogleDrive"; fallbackUrl = "https://dl.google.com/drive-file-stream/GoogleDriveSetup.exe"; archivo = "GoogleDriveSetup.exe"; fallbackPage = "https://www.google.com/drive/download/" },
        @{ nombre = "Lively Wallpaper"; id = "rocksdanister.LivelyWallpaper" },
        @{ nombre = "WinRAR"; id = "RARLab.WinRAR"; fallbackUrl = "https://www.win-rar.com/fileadmin/winrar-versions/winrar/winrar-x64-711es.exe"; archivo = "WinRAR-x64.exe"; fallbackPage = "https://www.win-rar.com/download.html" },
        @{ nombre = "Adobe Acrobat Reader"; id = "Adobe.Acrobat.Reader.64-bit"; fallbackPage = "https://get.adobe.com/es/reader/" },
        @{ nombre = "Microsoft Teams"; id = "Microsoft.Teams"; fallbackUrl = "https://statics.teams.cdn.office.net/evergreen-assets/DesktopClient/MSTeamsSetup.exe"; archivo = "MSTeamsSetup.exe"; fallbackPage = "https://www.microsoft.com/es-es/microsoft-teams/download-app" },
        @{ nombre = "VLC Media Player"; id = "VideoLAN.VLC"; fallbackUrl = "https://get.videolan.org/vlc/3.0.21/win32/vlc-3.0.21-win32.exe"; archivo = "vlc-3.0.21-win32.exe"; fallbackPage = "https://www.videolan.org/vlc/download-windows.html" },
        @{ nombre = "Zoom Workplace"; id = "Zoom.Zoom"; fallbackUrl = "https://zoom.us/client/latest/ZoomInstallerFull.exe"; archivo = "ZoomInstallerFull.exe"; fallbackPage = "https://zoom.us/download" },
        @{ nombre = "Spotify"; id = "Spotify.Spotify"; fallbackPage = "https://www.spotify.com/download/windows/" }
    )

    $total = $programas.Count
    $index = 0

    foreach ($programa in $programas) {
        $index++
        $porcentaje = [math]::Round(($index / $total) * 100)
        Write-Log "`n[$porcentaje%] $($programa.nombre)..." "INFO"

        # Verificar instalacion
        $salidaLista = winget list --id $($programa.id) 2>$null
        $estaInstalado = $salidaLista -match $programa.id
        if (-not $estaInstalado) {
            Write-Log "No instalado. Usando Winget..." "INFO"
            winget install --id $($programa.id) --silent --accept-source-agreements --accept-package-agreements
            if ($LASTEXITCODE -eq 0) {
                Write-Log "$($programa.nombre) instalado." "INFO"
                # Crear acceso directo en escritorio
                CrearAccesoDirectoEscritorio -nombrePrograma $programa.nombre -idPrograma $programa.id
            }
            elseif ($programa.fallbackUrl) {
                Write-Warning "Winget fallo. Usando metodo alternativo..."
                InstalarDesdeWeb -nombre $programa.nombre -url $programa.fallbackUrl -archivo $programa.archivo -fallbackPage $programa.fallbackPage
                # Intentar crear acceso directo después de instalación alternativa
                Start-Sleep -Seconds 5
                CrearAccesoDirectoEscritorio -nombrePrograma $programa.nombre -idPrograma $programa.id
            }
            else {
                Write-Warning "Error instalando $($programa.nombre)."
            }
        }
        else {
            Write-Log "Ya instalado." "INFO"

            # Si esta instalado, verificar si hay actualizacion
            $salidaUpdate = winget upgrade --id $($programa.id) 2>$null
            $tieneUpdate = $salidaUpdate -match $programa.id
            if ($tieneUpdate) {
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
                Write-Log "$($programa.nombre) esta actualizado." "INFO"
            }
            
            # Crear acceso directo si no existe (incluso si ya estaba instalado)
            CrearAccesoDirectoEscritorio -nombrePrograma $programa.nombre -idPrograma $programa.id
        }
    }
}

# =================== Funciones de Configuracion de Fondo y Protector de Pantalla =====================
# Esta funcion descarga fondos de pantalla y un protector de pantalla, y los configura.
function DescargarFondosYProtectorDePantalla {
    Write-Log "Iniciando descarga de fondos y protector..." "INFO"

    # Forzar TLS 1.2 (evita fallos con GitHub/Google)
    
    try { 
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
    }
    catch { "Error forzando TLS 1.2: $_" }

    try {
        # ================= PASO 1: Rutas y colecciones =================
        $pictures = [Environment]::GetFolderPath("MyPictures")
        $fondosPath = Join-Path $pictures "Fondos"

        $fondos = @(
            @{ url = "https://drive.usercontent.google.com/download?id=1TdkSn764_O6nw92BNvkpSPrczYEBrU84&export=download"; nombre = "Fondo de Escritorio.png" },
            @{ url = "https://drive.usercontent.google.com/download?id=1XC6LxjhVAKNQDehwKVn-jPAOA4kvurvk&export=download"; nombre = "Fondo de Zoom.png" }
        )

        $videos = [Environment]::GetFolderPath("MyVideos")
        $videoDestino = Join-Path $videos "PROTECTOR-1.mp4"
        $videoUrl = "https://drive.usercontent.google.com/download?id=1bZyh8AuVB9I_ezN1bEHdtypxR5uXCCoB&export=download"

        # Sitio Oficial de Lively: https://rocksdanister.github.io/lively/
        # URL: https://github.com/rocksdanister/lively/releases/download/v2.2.1.0/lively_setup_x86_full_v2210.exe
        $downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
        $installerOk = $false
        $extractFolder = Join-Path $downloads "lively_screensaver"

        $installerPath = Join-Path $downloads "lively_setup_x86_full_v2210.exe"
        $zipPath = Join-Path $downloads "lively_utility_screensaver.zip"
        $destinoScr = "C:\Windows\Lively.scr"
        $userScrDir = Join-Path $env:LOCALAPPDATA "LivelyScr"
        $userScr = Join-Path $userScrDir "Lively.scr"

        $minInstallerBytes = 10MB
        $minZipBytes = 4096
        $minScrBytes = 4096

        # ================= PASO 2: Crear carpetas si faltan =================
        try {
            if (-not (Test-Path $pictures)) { New-Item -ItemType Directory -Path $pictures   | Out-Null; Write-Log "PASO 2: Creada carpeta Imágenes: $pictures" "INFO" }
            if (-not (Test-Path $fondosPath)) { New-Item -ItemType Directory -Path $fondosPath | Out-Null; Write-Log "PASO 2: Creada carpeta Fondos:   $fondosPath" "INFO" }
            if (-not (Test-Path $videos)) { New-Item -ItemType Directory -Path $videos     | Out-Null; Write-Log "PASO 2: Creada carpeta Vídeos:   $videos" "INFO" }
            if (-not (Test-Path $downloads)) { New-Item -ItemType Directory -Path $downloads  | Out-Null; Write-Log "PASO 2: Creada carpeta Descargas: $downloads" "INFO" }
        }
        catch {
            Write-Warning "FALLO PASO 2 (crear carpetas): $_"
        }

        # ================= PASO 3: Descargar fondos =================
        foreach ($fondo in $fondos) {
            $destino = Join-Path $fondosPath $fondo.nombre
            if (Test-Path $destino) {
                Write-Log "PASO 3: Fondo ya existe, omitiendo: $($fondo.nombre)" "DEBUG"
                continue
            }
            try {
                Write-Log "PASO 3: Descargando $($fondo.nombre)..." "INFO"
                Invoke-WebRequest -Uri $fondo.url -OutFile $destino -UseBasicParsing -ErrorAction Stop

                # Validacion (mínimo 20 KB)
                if (-not (Test-Path $destino) -or (Get-Item $destino).Length -lt 20480) {
                    throw "Archivo incompleto o demasiado pequeño: $destino"
                }
                Write-Log "PASO 3: OK $($fondo.nombre) → $destino" "INFO"
            }
            catch {
                Write-Warning "FALLO PASO 3 (fondo $($fondo.nombre)): $_"
            }
        }

        # ================= PASO 4: Descargar video del protector =================
        if (Test-Path $videoDestino) {
            Write-Log "PASO 4: Video ya existe, omitiendo: $videoDestino" "DEBUG"
        }
        else {
            try {
                Write-Log "PASO 4: Descargando video del protector..." "INFO"
                try {
                    Start-BitsTransfer -Source $videoUrl -Destination $videoDestino -ErrorAction Stop
                }
                catch {
                    Write-Warning "BITS falló, usando Invoke-WebRequest. $_"
                    Invoke-WebRequest -Uri $videoUrl -OutFile $videoDestino -UseBasicParsing -ErrorAction Stop
                }
            }
            catch {
                Write-Warning "FALLO PASO 4 (descargar video): $_"
            }

            # Validación (mínimo 1 MB)
            if (-not (Test-Path $videoDestino) -or (Get-Item $videoDestino).Length -lt 1048576) {
                Write-Warning "FALLO PASO 4.3: Video ausente o demasiado pequeño: $videoDestino"
            }
            else {
                Write-Log "PASO 4: OK video → $videoDestino" "INFO"
            }
        }
        # ================= PASO 5: Descargar e instalar Lively (v2.2.1.0) =================
        try {
            $exeUrl = "https://github.com/rocksdanister/lively/releases/download/v2.2.1.0/lively_setup_x86_full_v2210.exe"
            $downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
            $exePath = Join-Path $downloads "lively_setup_x86_full_v2210.exe"
            
            # Verificar si Lively ya está instalado
            $livelyInstalled = $false
            $livelyPaths = @(
                "$env:LOCALAPPDATA\Programs\Lively Wallpaper\Lively.exe",
                "C:\Program Files\Lively Wallpaper\Lively.exe",
                "C:\Program Files (x86)\Lively Wallpaper\Lively.exe"
            )
            
            foreach ($path in $livelyPaths) {
                if (Test-Path $path) {
                    $livelyInstalled = $true
                    Write-Log "PASO 5: Lively ya está instalado en: $path" "INFO"
                    break
                }
            }
            
            if ($livelyInstalled) {
                Write-Log "PASO 5: Cerrando Lively si está en ejecución..." "INFO"
                Get-Process -Name "Lively" -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 3
                Write-Log "PASO 5: Omitiendo reinstalación de Lively (ya instalado)." "INFO"
            }
            else {
                # Si ya existe el instalador, omitir descarga
                if (Test-Path $exePath) {
                    Write-Log "PASO 5: Instalador Lively ya descargado en $exePath, omitiendo descarga." "INFO"
                }
                else {
                    Write-Log "PASO 5.1: Descargando instalador Lively v2.2.1.0..." "INFO"
                    try {
                        Start-BitsTransfer -Source $exeUrl -Destination $exePath -ErrorAction Stop
                    }
                    catch {
                        Write-Warning "BITS falló, usando Invoke-WebRequest: $_"
                        Invoke-WebRequest -Uri $exeUrl -OutFile $exePath -UseBasicParsing -ErrorAction Stop
                    }

                    # Validar tamaño mínimo (~50 MB)
                    if (-not (Test-Path $exePath) -or (Get-Item $exePath).Length -lt 50000000) {
                        throw "El instalador parece incompleto: $exePath"
                    }
                    Write-Log "PASO 5.1: Instalador descargado correctamente → $exePath" "INFO"
                }

                # PASO 5.2: Ejecutar instalador en modo silencioso
                Write-Log "PASO 5.2: Ejecutando instalador de Lively (modo silencioso)..." "INFO"

                # Parametros de InnoSetup para instalacion silenciosa:
                # /VERYSILENT = No muestra dialogo de instalacion
                # /NOAUTOLAUNCH = No abre Lively despues de instalar
                # /NODEPENDENCIES = No instala vcredist/dotnet (opcionalmente)
                Start-Process -FilePath $exePath -ArgumentList "/VERYSILENT /NOAUTOLAUNCH" -Wait -ErrorAction Stop

                Write-Log "PASO 5.3: Instalación de Lively completada correctamente." "INFO"
            }

            # PASO 5.4: Descargar e instalar Lively Screensaver (Lively.scr)
            try {
                $scrZipUrl = "https://github.com/rocksdanister/lively/releases/download/v2.2.0.0/lively_utility_screensaver.zip"
                $scrZipPath = Join-Path $downloads "lively_utility_screensaver.zip"
                $scrExtractPath = Join-Path $downloads "lively_screensaver_temp"
                $scrDestPath = "C:\Windows\Lively.scr"  # Ubicación correcta según documentación

                Write-Log "PASO 5.4: Descargando Lively Screensaver..." "INFO"
                try {
                    Start-BitsTransfer -Source $scrZipUrl -Destination $scrZipPath -ErrorAction Stop
                }
                catch {
                    Write-Warning "BITS falló, usando Invoke-WebRequest: $_"
                    Invoke-WebRequest -Uri $scrZipUrl -OutFile $scrZipPath -UseBasicParsing -ErrorAction Stop
                }

                # Validar descarga
                if (-not (Test-Path $scrZipPath) -or (Get-Item $scrZipPath).Length -lt 4096) {
                    throw "El archivo ZIP del screensaver parece incompleto: $scrZipPath"
                }

                Write-Log "PASO 5.4: Extrayendo Lively.scr..." "INFO"
                # Crear carpeta temporal si no existe
                if (Test-Path $scrExtractPath) {
                    Remove-Item -Path $scrExtractPath -Recurse -Force
                }
                New-Item -ItemType Directory -Path $scrExtractPath -Force | Out-Null

                # Extraer ZIP
                Expand-Archive -Path $scrZipPath -DestinationPath $scrExtractPath -Force

                # Buscar Lively.scr en la carpeta extraída
                $scrFile = Get-ChildItem -Path $scrExtractPath -Filter "Lively.scr" -Recurse | Select-Object -First 1

                if ($scrFile) {
                    Write-Log "PASO 5.4: Copiando Lively.scr a: $scrDestPath" "INFO"
                    
                    # Copiar Lively.scr a C:\Windows
                    Copy-Item -Path $scrFile.FullName -Destination $scrDestPath -Force

                    # Verificar copia exitosa
                    if (Test-Path $scrDestPath) {
                        Write-Log "PASO 5.4: Lively.scr copiado exitosamente a C:\Windows" "INFO"
                        
                        # Registrar en el registro de Windows de forma directa (backend)
                        Write-Log "PASO 5.4: Registrando screensaver en Windows (backend)..." "INFO"
                        $regPath = 'HKCU:\Control Panel\Desktop'
                        
                        # Establecer el screensaver
                        Set-ItemProperty -Path $regPath -Name 'SCRNSAVE.EXE' -Value $scrDestPath -Force
                        Set-ItemProperty -Path $regPath -Name 'ScreenSaveActive' -Value '1' -Force
                        Set-ItemProperty -Path $regPath -Name 'ScreenSaveTimeOut' -Value '300' -Force
                        Set-ItemProperty -Path $regPath -Name 'ScreenSaveUsePassword' -Value '0' -Force
                        
                        # Aplicar cambios de inmediato
                        Start-Process -FilePath "rundll32.exe" -ArgumentList "user32.dll,UpdatePerUserSystemParameters" -WindowStyle Hidden -Wait
                        Start-Sleep -Seconds 1
                        
                        Write-Log "PASO 5.4: Screensaver registrado en backend correctamente." "INFO"
                    }
                    else {
                        Write-Warning "PASO 5.4: No se pudo copiar Lively.scr a: $scrDestPath"
                    }
                }
                else {
                    Write-Warning "PASO 5.4: No se encontró Lively.scr en el archivo extraído."
                }

                # Limpiar archivos temporales
                Write-Log "PASO 5.4: Limpiando archivos temporales..." "INFO"
                if (Test-Path $scrExtractPath) {
                    Remove-Item -Path $scrExtractPath -Recurse -Force
                }
                if (Test-Path $scrZipPath) {
                    Remove-Item -Path $scrZipPath -Force
                }
                Write-Log "PASO 5.4: Archivos temporales eliminados." "INFO"

            }
            catch {
                Write-Warning "FALLO PASO 5.4 (instalar screensaver): $_"
            }

            # PASO 5.5: Registrar Lively como protector de pantalla
            try {
                $scrPath = "C:\Windows\Lively.scr"  # Ubicación correcta
                if (Test-Path $scrPath) {
                    Write-Log "PASO 5.5: Configurando Lively como protector de pantalla en backend..." "INFO"
                    $regPath = 'HKCU:\Control Panel\Desktop'
                    
                    Set-ItemProperty -Path $regPath -Name 'SCRNSAVE.EXE' -Value $scrPath -Force
                    Set-ItemProperty -Path $regPath -Name 'ScreenSaveActive' -Value '1' -Force
                    Set-ItemProperty -Path $regPath -Name 'ScreenSaveTimeOut' -Value '300' -Force
                    Set-ItemProperty -Path $regPath -Name 'ScreenSaveUsePassword' -Value '0' -Force
                    
                    # Forzar actualización del sistema
                    rundll32.exe user32.dll,UpdatePerUserSystemParameters
                    Start-Sleep -Seconds 2
                    
                    Write-Log "PASO 5.5: Protector configurado en backend (5 minutos)." "INFO"
                }
                else {
                    Write-Warning "PASO 5.5: No se encontró Lively.scr en la ruta esperada: $scrPath"
                }
            }
            catch {
                Write-Warning "FALLO PASO 5.5 (registro de protector): $_"
            }

        }
        catch {
            Write-Warning "FALLO PASO 5 (instalar Lively): $_"
        }

        Write-Log "Proceso finalizado." "INFO"
    }
    catch {
        Write-Warning "ERROR GENERAL: $_"
    }
}

# =================== Configura SOLO el protector de pantalla Lively ===================
function ConfigurarLivelyProtectorYFondo {
    Write-Log "Iniciando configuración SOLO del protector de pantalla Lively..." "INFO"
    try {
        # Buscar Lively ejecutable (v2.2.1.0)
        $livelyPaths = @(
            "$env:LOCALAPPDATA\Programs\Lively Wallpaper\Lively.exe",
            "C:\Program Files\Lively Wallpaper\Lively.exe",
            "C:\Program Files\Lively Wallpaper\Lively.App.exe",
            "C:\Program Files (x86)\Lively Wallpaper\Lively.App.exe",
            "C:\Program Files (x86)\Lively Wallpaper\Lively.exe"
        )
        $livelyExe = $livelyPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $livelyExe) {
            Write-Warning "No se encontró Lively instalado. Instálalo antes de continuar."
            return
        }
        
        Write-Log "Lively encontrado en: $livelyExe" "INFO"

        # Rutas de archivos multimedia
        $videoPath = Join-Path ([Environment]::GetFolderPath("MyVideos")) "PROTECTOR-1.mp4"
        $fondoPath = Join-Path ([Environment]::GetFolderPath("MyPictures")) "Fondos\Fondo de Escritorio.png"
        $destScr   = "C:\Windows\Lively.scr"  # Ubicación correcta del screensaver

        # Paso 0: Establecer fondo de escritorio estático
        if (Test-Path $fondoPath) {
            Write-Log "Aplicando fondo de escritorio fijo desde Windows..." "INFO"
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name wallpaper -Value $fondoPath
            RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters
            Write-Log "Fondo aplicado correctamente." "INFO"
        }
        else {
            Write-Warning "No se encontró la imagen de fondo: $fondoPath"
        }

        # Paso 1: Validar video
        if (-not (Test-Path $videoPath)) {
            Write-Warning "No se encontró el video del protector en: $videoPath"
            return
        }

        # Paso 2: Registrar Lively como protector de pantalla (backend)
        if (Test-Path $destScr) {
            Write-Log "Paso 2: Configurando Lively como protector de pantalla (backend)..." "INFO"
            $regPath = "HKCU:\Control Panel\Desktop"
            
            Set-ItemProperty -Path $regPath -Name "SCRNSAVE.EXE" -Value $destScr -Force
            Set-ItemProperty -Path $regPath -Name "ScreenSaveActive" -Value "1" -Force
            Set-ItemProperty -Path $regPath -Name "ScreenSaveTimeOut" -Value "300" -Force
            Set-ItemProperty -Path $regPath -Name "ScreenSaveUsePassword" -Value "0" -Force
            
            # Aplicar cambios inmediatamente
            rundll32.exe user32.dll,UpdatePerUserSystemParameters
            Start-Sleep -Seconds 2
            
            Write-Log "Paso 2: Protector de pantalla configurado (5 minutos)." "INFO"
        }
        else {
            Write-Warning "No se encontró Lively.scr en $destScr"
            return
        }

        # Paso 3: Configurar el video en Lively directamente en archivos de configuración
        Write-Log "Paso 3: Configurando video como screensaver en Lively..." "INFO"
        
        if (Test-Path $videoPath) {
            try {
                # Rutas de configuración de Lively
                $livelyDataPath = "$env:LOCALAPPDATA\Lively Wallpaper"
                $settingsPath = Join-Path $livelyDataPath "Settings.json"
                $libraryPath = Join-Path $livelyDataPath "Library\wallpapers"
                
                # Abrir Lively para crear estructura de carpetas
                Write-Log "Paso 3.1: Iniciando Lively para crear estructura..." "INFO"
                & $livelyExe app --showApp true
                Start-Sleep -Seconds 8
                
                # Cerrar Lively antes de modificar archivos
                Write-Log "Paso 3.2: Cerrando Lively temporalmente..." "INFO"
                & $livelyExe app --shutdown true
                Start-Sleep -Seconds 5
                
                # Crear carpeta para el video en la biblioteca
                Write-Log "Paso 3.3: Creando entrada en biblioteca para el video..." "INFO"
                
                if (-not (Test-Path $libraryPath)) {
                    New-Item -ItemType Directory -Path $libraryPath -Force | Out-Null
                }
                
                # Generar nombre único para la carpeta del wallpaper
                $uniqueId = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object {[char]$_})
                $videoWallpaperFolder = Join-Path $libraryPath "${uniqueId}.mp4"
                New-Item -ItemType Directory -Path $videoWallpaperFolder -Force | Out-Null
                
                # Copiar el video a la biblioteca
                $videoDestInLibrary = Join-Path $videoWallpaperFolder "PROTECTOR-1.mp4"
                Copy-Item -Path $videoPath -Destination $videoDestInLibrary -Force
                Write-Log "Paso 3.3: Video copiado a biblioteca: $videoWallpaperFolder" "INFO"
                
                # Crear LivelyInfo.json para el video
                $livelyInfo = @{
                    AppVersion = "2.2.1.0"
                    Title = "Protector Vidanova"
                    Thumbnail = "PROTECTOR-1.mp4"
                    Preview = "PROTECTOR-1.mp4"
                    Desc = "Video protector de pantalla Vidanova"
                    Author = "Vidanova"
                    License = ""
                    Contact = ""
                    Type = 1  # Video type
                    FileName = "PROTECTOR-1.mp4"
                    Arguments = $null
                    IsAbsolutePath = $false
                }
                
                $livelyInfoPath = Join-Path $videoWallpaperFolder "LivelyInfo.json"
                $livelyInfo | ConvertTo-Json -Depth 5 | Set-Content -Path $livelyInfoPath -Encoding UTF8 -Force
                Write-Log "Paso 3.3: LivelyInfo.json creado correctamente" "INFO"
                
                # Iniciar Lively para que indexe el nuevo wallpaper
                Write-Log "Paso 3.3: Iniciando Lively para indexar el wallpaper..." "INFO"
                & $livelyExe app --showApp false
                Start-Sleep -Seconds 5
                
                # Configurar como screensaver en Settings.json
                Write-Log "Paso 3.4: Configurando screensaver en Settings.json..." "INFO"
                
                # Asegurarse de que Lively esté completamente cerrado antes de modificar el JSON
                Get-Process -Name "Lively" -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 3
                
                # Crear Settings.json si no existe
                if (-not (Test-Path $settingsPath)) {
                    $defaultSettings = @{
                        ScreensaverData = @{
                            Wallpapers = @()
                        }
                    }
                    $defaultSettings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8 -Force
                }
                
                $settings = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
                
                # Configurar screensaver con la ruta correcta del video
                $screensaverConfig = @{
                    Wallpapers = @(
                        @{
                            LivelyInfoFolderPath = $videoWallpaperFolder
                        }
                    )
                }
                
                # Reemplazar o agregar la configuración de screensaver
                if ($settings.PSObject.Properties.Name -contains "ScreensaverData") {
                    $settings.ScreensaverData = $screensaverConfig
                }
                else {
                    $settings | Add-Member -MemberType NoteProperty -Name "ScreensaverData" -Value $screensaverConfig -Force
                }
                
                # Guardar configuración
                $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding UTF8 -Force
                Write-Log "Paso 3.4: Screensaver configurado en Settings.json: $videoWallpaperFolder" "INFO"
                
                # Abrir Lively para que cargue la nueva configuración
                Write-Log "Paso 3.5: Abriendo Lively para aplicar configuración..." "INFO"
                & $livelyExe app --showApp true
                Start-Sleep -Seconds 5
                
                # Cerrar Lively
                Write-Log "Paso 3.5: Cerrando Lively..." "INFO"
                & $livelyExe app --shutdown true
                Start-Sleep -Seconds 3
                
                Write-Log "Paso 3: Configuración completada exitosamente." "INFO"
            }
            catch {
                Write-Warning "Paso 3: Error configurando video: $_"
            }
        }
        else {
            Write-Warning "Paso 3: Video no encontrado en $videoPath"
        }
        
        # Paso 4: Verificar configuración (opcional - cerrar Lively si está abierto)
        Write-Log "Paso 4: Finalizando configuración..." "INFO"
        try {
            Get-Process -Name "Lively" -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Log "Paso 4: Lively no estaba ejecutándose." "DEBUG"
        }

        Write-Log "✅ Configuración de Lively completada: solo protector activo, fondo estático." "INFO"
    }
    catch {
        Write-Warning "⚠️ Error en la configuración de Lively: $_"
    }
}

# =================== Función de Configuración de Barra de Tareas Windows 11 =====================
function ConfigurarBarraTareasWindows11 {
    Write-Log "Verificando versión de Windows..." "INFO"
    
    try {
        # Detectar si es Windows 11
        $osVersion = [System.Environment]::OSVersion.Version
        $buildNumber = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuild).CurrentBuild
        
        if ([int]$buildNumber -lt 22000) {
            Write-Log "Este sistema es Windows 10 (Build: $buildNumber). Configuración solo para Windows 11." "INFO"
            return
        }
        
        Write-Log "Windows 11 detectado (Build: $buildNumber). Aplicando configuraciones de barra de tareas..." "INFO"
        
        $regPathExplorer = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $regPathSearch = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        
        # Asegurar que las rutas del registro existan
        if (-not (Test-Path $regPathExplorer)) {
            New-Item -Path $regPathExplorer -Force | Out-Null
        }
        if (-not (Test-Path $regPathSearch)) {
            New-Item -Path $regPathSearch -Force | Out-Null
        }
        
        $cambiosAplicados = $false
        
        # 1. Alinear iconos de la barra de tareas a la izquierda
        try {
            $valorActual = Get-ItemProperty -Path $regPathExplorer -Name "TaskbarAl" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TaskbarAl
            if ($valorActual -ne 0) {
                Write-Log "→ Alineando iconos a la izquierda..." "INFO"
                Set-ItemProperty -Path $regPathExplorer -Name "TaskbarAl" -Value 0 -Type DWord -Force -ErrorAction Stop
                $cambiosAplicados = $true
            }
            else {
                Write-Log "→ Iconos ya están alineados a la izquierda (valor actual: $valorActual)" "INFO"
            }
        }
        catch {
            Write-Warning "Error al configurar alineación de iconos: $_"
        }
        
        # 2. Ocultar vista de tareas (Task View)
        try {
            $valorActual = Get-ItemProperty -Path $regPathExplorer -Name "ShowTaskViewButton" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ShowTaskViewButton
            if ($valorActual -ne 0) {
                Write-Log "→ Ocultando Vista de Tareas..." "INFO"
                Set-ItemProperty -Path $regPathExplorer -Name "ShowTaskViewButton" -Value 0 -Type DWord -Force -ErrorAction Stop
                $cambiosAplicados = $true
            }
            else {
                Write-Log "→ Vista de Tareas ya está oculta (valor actual: $valorActual)" "INFO"
            }
        }
        catch {
            Write-Warning "Error al configurar Vista de Tareas: $_"
        }
        
        # 3. Ocultar Widgets (Noticias e intereses)
        try {
            $valorActual = Get-ItemProperty -Path $regPathExplorer -Name "TaskbarDa" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty TaskbarDa
            if ($valorActual -ne 0) {
                Write-Log "→ Ocultando Widgets y Noticias..." "INFO"
                Set-ItemProperty -Path $regPathExplorer -Name "TaskbarDa" -Value 0 -Type DWord -Force -ErrorAction Stop
                $cambiosAplicados = $true
            }
            else {
                Write-Log "→ Widgets/Noticias ya están ocultos (valor actual: $valorActual)" "INFO"
            }
        }
        catch {
            Write-Warning "Error al configurar Widgets: $_"
        }
        
        # 4. Configurar búsqueda solo como icono
        try {
            $valorActual = Get-ItemProperty -Path $regPathSearch -Name "SearchboxTaskbarMode" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SearchboxTaskbarMode
            if ($valorActual -ne 1) {
                Write-Log "→ Configurando búsqueda solo como icono..." "INFO"
                Set-ItemProperty -Path $regPathSearch -Name "SearchboxTaskbarMode" -Value 1 -Type DWord -Force -ErrorAction Stop
                $cambiosAplicados = $true
            }
            else {
                Write-Log "→ Búsqueda ya está configurada como icono (valor actual: $valorActual)" "INFO"
            }
        }
        catch {
            Write-Warning "Error al configurar búsqueda: $_"
        }
        
        # 5. Reiniciar el Explorador de Windows solo si hubo cambios
        if ($cambiosAplicados) {
            Write-Log "→ Reiniciando Explorador de Windows para aplicar cambios..." "INFO"
            try {
                Stop-Process -Name explorer -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                Start-Process explorer.exe
                Start-Sleep -Seconds 3
                Write-Log "✅ Configuración de barra de tareas completada exitosamente." "INFO"
            }
            catch {
                Write-Warning "No se pudo reiniciar el Explorador automáticamente. Reinicia manualmente o cierra sesión para ver los cambios."
            }
        }
        else {
            Write-Log "✅ Todas las configuraciones de barra de tareas ya estaban aplicadas. No se requieren cambios." "INFO"
        }
    }
    catch {
        Write-Warning "Error configurando barra de tareas de Windows 11: $_"
    }
}

# =================== BLOQUE PRINCIPAL AQUi =====================
try {
    Write-Log "`nIniciando mantenimiento del sistema..." "INFO"
    VerificarConectividad

    # Inicializar Winget
    InicializarWinget

    $fabricante = DetectarFabricante
    Write-Log "`nFabricante: $fabricante" "INFO"
    InstalarSoporteFabricante -fab $fabricante

    #Aqui funcion de Programas
    InstalarYActualizarProgramas
    
    # Descargar fondos y video de protector de pantalla
    DescargarFondosYProtectorDePantalla

    # Configurar Lively, fondo y protector de pantalla
    ConfigurarLivelyProtectorYFondo

    # Configurar barra de tareas de Windows 11
    ConfigurarBarraTareasWindows11
}
catch {
    Write-Log "Error critico: $_" "ERROR"
}
finally {
    Read-Host "`nMantenimiento completado o detenido. Presione ENTER para salir"
}