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
        Write-Warning "Fabricante no reconocido. Se usará SDI Lite como solución de respaldo." "WARNING"
        UsarSDILite
        return
    }

    if ($fab -match "innotek|vmware|virtualbox|qemu") {
        Write-Warning "Entorno virtual detectado. Omitiendo soporte de fabricante."
        return
    }

    Write-Log "Fabricante soportado. Se recomienda usar la página oficial para drivers:" "INFO"
    Write-Log " - ${fab}: $($urls[$fab])" "INFO"

}
# =================== Funciones de Instalacion y Actualizacion de Programas =====================
# Esta funcion instala Winget si no esta disponible.
#
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
        @{ nombre = "VLC Media Player"; id = "VideoLAN.VLC"; fallbackUrl = "https://get.videolan.org/vlc/3.0.21/win32/vlc-3.0.21-win32.exe"; archivo = "vlc-3.0.21-win32.exe"; fallbackPage = "https://www.videolan.org/vlc/download-windows.html" }
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
            }
            elseif ($programa.fallbackUrl) {
                Write-Warning "Winget fallo. Usando metodo alternativo..."
                InstalarDesdeWeb -nombre $programa.nombre -url $programa.fallbackUrl -archivo $programa.archivo -fallbackPage $programa.fallbackPage
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
        }
    }
}

# =================== Funciones de Configuracion de Fondo y Protector de Pantalla =====================
# Esta funcion descarga fondos de pantalla y un protector de pantalla, y los configura.
function DescargarFondosYProtectorDePantalla {
    Write-Log "Iniciando descarga de fondos y protector..." "INFO"

    # Forzar TLS 1.2 (evita fallos con GitHub/Google)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    try {
        # ================= PASO 1: Rutas y colecciones =================
        $pictures = [Environment]::GetFolderPath("MyPictures")
        $fondosPath = Join-Path $pictures "Fondos"

        $fondos = @(
            @{ url = "https://drive.usercontent.google.com/download?id=1O2drBdLD7aPkpIdIGPB4hhUC6OH1LIh5&export=download"; nombre = "Fondo de Escritorio.png" },
            @{ url = "https://drive.usercontent.google.com/download?id=1tOv6xbWirAet1gdMtESQYjaqTBK9RqI8&export=download"; nombre = "Fondo de Zoom.png" }
        )

        $videos = [Environment]::GetFolderPath("MyVideos")
        $videoDestino = Join-Path $videos "PROTECTOR-1.mp4"
        $videoUrl = "https://drive.usercontent.google.com/download?id=1bZyh8AuVB9I_ezN1bEHdtypxR5uXCCoB&export=download"

        $downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
        $zipUrl = "https://github.com/rocksdanister/lively/releases/download/v2.1.0.6/lively_screen_saver.zip"
        $zipPath = Join-Path $downloads "lively_screen_saver.zip"
        $extractFolder = Join-Path $downloads "lively_screen_saver"
        $scrName = "Lively.scr"
        $destinoScr = Join-Path $env:SystemRoot $scrName

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

                # Validación (mínimo 20 KB)
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
                Write-Log "PASO 4.1: Descargando video con BITS..." "INFO"
                Start-BitsTransfer -Source $videoUrl -Destination $videoDestino -ErrorAction Stop
            }
            catch {
                Write-Warning "PASO 4.1: BITS falló, probando con Invoke-WebRequest. $_"
                try {
                    Invoke-WebRequest -Uri $videoUrl -OutFile $videoDestino -UseBasicParsing -ErrorAction Stop
                }
                catch {
                    Write-Warning "FALLO PASO 4.2 (descargar video con IWR): $_"
                }
            }

            # Validación (mínimo 1 MB)
            if (-not (Test-Path $videoDestino) -or (Get-Item $videoDestino).Length -lt 1048576) {
                Write-Warning "FALLO PASO 4.3: Video ausente o demasiado pequeño: $videoDestino"
            }
            else {
                Write-Log "PASO 4: OK video → $videoDestino" "INFO"
            }
        }

        # ================= PASO 5: Descargar e instalar Lively.scr =================
        $zipOk = $false
        if (Test-Path $destinoScr) {
            Write-Log "PASO 5: $scrName ya existe en $destinoScr. Omitiendo instalación." "INFO"
        }
        else {
            # URLs
            $zipUrl = "https://github.com/rocksdanister/lively/releases/download/v2.1.0.6/lively_screen_saver.zip"
            $zipUrlMirror = "https://sourceforge.net/projects/lively-wallpaper.mirror/files/v2.1.0.6/lively_screen_saver.zip/download"  # espejo oficial
            $minZipBytes = 4096   # ~4 KB (el plugin es < 8 KB)
            $minScrBytes = 4096   # ~4 KB (el .scr es pequeño por diseño)

            # 5.1 Descargar ZIP (con limpieza, reintentos y validación)
            try {
                $maxTries = 3
                $minZipBytes = 4096   # ~4 KB: el ZIP puede ser muy pequeño en esta release

                for ($i = 1; $i -le $maxTries -and -not $zipOk; $i++) {
                    if (Test-Path $zipPath) {
                        try { Remove-Item -Path $zipPath -Force -ErrorAction Stop } catch {}
                    }

                    Write-Log ("PASO 5.1.{0}: Descargando ZIP a {1}..." -f $i, $zipPath) "INFO"
                    try {
                        Start-BitsTransfer -Source $zipUrl -Destination $zipPath -ErrorAction Stop
                    }
                    catch {
                        Write-Warning ("PASO 5.1.{0}: BITS falló, usando Invoke-WebRequest. {1}" -f $i, $_)
                        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
                    }

                    # Validación de tamaño (sin operador ternario; compatible con PS 5.1)
                    $size = 0
                    if (Test-Path $zipPath) {
                        try { $size = (Get-Item $zipPath).Length } catch { $size = 0 }
                    }

                    if ($size -ge $minZipBytes) {
                        $zipOk = $true
                        Write-Log ("PASO 5.1.{0}: OK ZIP -> {1} ({2} bytes)" -f $i, $zipPath, $size) "INFO"
                    }
                    else {
                        Write-Warning ("PASO 5.1.{0}: ZIP ausente o muy pequeño ({2} bytes): {1}" -f $i, $zipPath, $size)
                        Start-Sleep -Seconds 2
                    }
                }

                if (-not $zipOk) { throw ("ZIP no descargado correctamente tras {0} intento(s)." -f $maxTries) }
            }
            catch {
                Write-Warning "FALLO PASO 5.1 (descargar ZIP Lively): $_"
            }

            if ($zipOk) {
                # 5.2 Limpiar y extraer
                try {
                    if (Test-Path $extractFolder) {
                        Write-Log "PASO 5.2: Limpiando extracción previa: $extractFolder" "DEBUG"
                        Remove-Item -Path $extractFolder -Recurse -Force
                    }
                    Write-Log "PASO 5.2: Extrayendo ZIP..." "INFO"
                    Expand-Archive -Path $zipPath -DestinationPath $extractFolder -Force -ErrorAction Stop
                    Write-Log ("PASO 5.2: OK extracción -> {0}" -f $extractFolder) "INFO"
                }
                catch {
                    Write-Warning "FALLO PASO 5.2 (Expand-Archive): $_"
                }

                # 5.3 Eliminar Instructions.txt
                try {
                    $instructions = Join-Path $extractFolder "Instructions.txt"
                    if (Test-Path $instructions) {
                        Remove-Item -Path $instructions -Force -ErrorAction SilentlyContinue
                        Write-Log "PASO 5.3: Eliminado Instructions.txt" "INFO"
                    }
                    else {
                        Write-Log "PASO 5.3: Instructions.txt no encontrado (ok)" "DEBUG"
                    }
                }
                catch {
                    Write-Warning "FALLO PASO 5.3 (eliminar Instructions.txt): $_"
                }

                # 5.4 Copiar/registrar Lively.scr (buscar cualquier .scr)
                try {
                    $scrPath = Get-ChildItem -Path $extractFolder -Recurse -Include *.scr -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if (-not $scrPath) { throw "No se encontró ningún .scr dentro del ZIP en $extractFolder." }

                    $scrLen = (Get-Item $scrPath.FullName).Length
                    if ($scrLen -lt $minScrBytes) {
                        Write-Warning ("PASO 5.4: {0} es pequeño ({1} bytes), continuo." -f $scrPath.Name, $scrLen)
                    }

                    $copied = $false
                    try {
                        Copy-Item -Path $scrPath.FullName -Destination $destinoScr -Force -ErrorAction Stop
                        $copied = $true
                        Write-Log ("PASO 5.4: OK {0} copiado a {1}" -f $scrPath.Name, $destinoScr) "INFO"
                    }
                    catch {
                        Write-Warning ("PASO 5.4: No se pudo copiar a C:\Windows (¿sin admin?). Intentando copia por usuario. {0}" -f $_)
                    }

                    if (-not $copied) {
                        $userScrDir = Join-Path $env:LOCALAPPDATA "LivelyScr"
                        $userScr = Join-Path $userScrDir $scrPath.Name
                        if (-not (Test-Path $userScrDir)) { New-Item -ItemType Directory -Path $userScrDir | Out-Null }
                        Copy-Item -Path $scrPath.FullName -Destination $userScr -Force
                        Write-Log ("PASO 5.4: Copia de usuario -> {0}" -f $userScr) "INFO"

                        # Registrar screensaver para el usuario actual
                        $regPath = 'HKCU:\Control Panel\Desktop'
                        Set-ItemProperty -Path $regPath -Name 'SCRNSAVE.EXE' -Value $userScr
                        Set-ItemProperty -Path $regPath -Name 'ScreenSaveActive' -Value '1'
                        Set-ItemProperty -Path $regPath -Name 'ScreenSaveTimeOut' -Value '600'
                        Start-Process -FilePath "rundll32.exe" -ArgumentList "user32.dll,UpdatePerUserSystemParameters" -WindowStyle Hidden
                        Write-Log "PASO 5.4: Registrado protector de pantalla para el usuario actual." "INFO"
                    }
                }
                catch {
                    Write-Warning "FALLO PASO 5.4 (copiar/registrar .scr): $_"
                }
            }
            else {
                Write-Warning "OMITIDOS PASOS 5.2-5.4 por fallo en la descarga (5.1)."
            }
        }
        Write-Log "Proceso finalizado." "INFO"
    }
    catch {
        Write-Warning "ERROR GENERAL: $_"
    }
}

# Esta funcion configura Lively Wallpaper como protector de pantalla y establece un fondo de escritorio.
function ConfigurarLivelyProtectorYFondo {
    Write-Log "Iniciando configuracion SOLO del protector de pantalla Lively..." "INFO"
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
            Write-Warning "No se encontro Lively.exe en una ruta conocida. Por favor, instala Lively Wallpaper primero."
            return
        }

        $videoPath = Join-Path ([Environment]::GetFolderPath("MyVideos")) "PROTECTOR-1.mp4"
        $fondoPath = Join-Path ([Environment]::GetFolderPath("MyPictures")) "Fondos\Fondo de Escritorio.png"
        $destScr = "C:\Windows\Lively.scr"

        # 0. Establecer fondo clasico de Windows primero (respaldo visual inmediato)
        if (Test-Path $fondoPath) {
            Write-Log "Estableciendo fondo clasico de Windows como respaldo..." "INFO"
            Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name wallpaper -Value $fondoPath
            RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters
            Write-Log "Fondo clasico aplicado exitosamente como base." "INFO"
        }
        else {
            Write-Warning "No se encontro la imagen de fondo clasico en: $fondoPath"
        }

        # 1. Importar el video a la biblioteca de Lively
        if (Test-Path $videoPath) {
            Write-Log "Importando video a la biblioteca de Lively..." "INFO"
            Start-Process -FilePath $livelyExe -ArgumentList "addwallpaper", ""$videoPath""
        }
        else {
            Write-Warning "No se encontro el archivo de video en: $videoPath"
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
            Start-Process -FilePath $livelyExe -ArgumentList "setwp", "--file", ""$videoPath""
            Start-Sleep -Seconds 5

            # 4. Cerrar el fondo activo (el protector ya tomo el video)
            Write-Log "Cerrando fondo activo de Lively..." "INFO"
            Start-Process -FilePath $livelyExe -ArgumentList "closewp", "-1"
            Start-Sleep -Seconds 2

            Write-Log "Proceso de configuracion del protector completado exitosamente." "INFO"
        }
        else {
            Write-Warning "No se encontro Lively.scr en $destScr"
        }
    }
    catch {
        Write-Warning "Error en configuracion de Lively protector: $_"
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
}
catch {
    Write-Log "Error critico: $_" "ERROR"
}
finally {
    Read-Host "`nMantenimiento completado o detenido. Presione ENTER para salir"
}