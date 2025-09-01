# 📄 Instalador-Actualizador Primeras Computadoras — Vidanova

Este proyecto fue desarrollado para **automatizar el proceso de preparación inicial y mantenimiento de software** en equipos nuevos o recién formateados, estandarizando el entorno Windows para colaboradores de **Vidanova**.

---

## 🧰 Funcionalidad General

El sistema consta de dos archivos principales:

- **`Instalador.bat`**: lanzador inicial. Verifica permisos de administrador y abre PowerShell con la política adecuada.

- **`Instalador.ps1`**: script principal que contiene toda la lógica de instalación, actualización y soporte de drivers.

---

## 🔒 Características Destacadas
✅ Elevación automática de privilegios: el script se relanza automáticamente como administrador si no tiene permisos al iniciar.

✅ Verificación de conectividad a Internet: se prueba acceso a Google antes de continuar, deteniendo el proceso si no hay conexión.

✅ Instalación automática de Winget: si no está disponible, se descarga desde el sitio oficial de Microsoft y se instala silenciosamente.

✅ Actualización de fuentes de Winget: se actualizan automáticamente las fuentes de paquetes antes de cualquier operación.

✅ Registro detallado (log): todo el proceso se documenta en un archivo actualizacion_instalacion_log.txt, guardado junto al script.

✅ Detección del fabricante del equipo: se analiza la marca (HP, Dell, Lenovo, etc.) y se proporciona el enlace oficial para controladores.

✅ Soporte alternativo con SDI Lite: si el equipo es virtual o el fabricante no es reconocido, se descarga e inicia SDI Lite para instalación manual de drivers.

✅ Instalación y actualización inteligente de software: cada programa se valida con winget para instalar o actualizar; si falla, se usa descarga directa.

✅ Método de respaldo automático: si Winget falla o no puede instalar un programa, el script descarga el instalador desde la web y lo ejecuta con validación.

✅ Descarga de fondos corporativos y protector de pantalla: se descargan imágenes y un video desde Google Drive y se configuran automáticamente.

✅ Configuración automática de Lively Wallpaper: si está instalado, el script configura el video como fondo y como protector de pantalla con reglas de tiempo.

---

## 💻 Aplicaciones Instaladas / Actualizadas

Las aplicaciones incluidas actualmente en la configuración de Vidanova son:

- ✅ Google Chrome
- ✅ WhatsApp Desktop
- ✅ AnyDesk
- ✅ Mozilla Thunderbird
- ✅ Google Drive
- ✅ Lively Wallpaper
- ✅ WinRAR
- ✅ Adobe Acrobat Reader
- ✅ Microsoft Teams
- ✅ VLC Media Player

> **Nota**: Si alguna aplicación no puede instalarse con Winget, el script utiliza descarga directa desde el sitio oficial para asegurar su disponibilidad.

---

## 📸 Capturas de Pantalla

### 🟢 Verificación inicial de Winget

![Screenshot verificación Winget](./screenshots/verificacion-winget.png)

---

### 🟢 Detección de fabricante y drivers

![Screenshot detección fabricante](./screenshots/deteccion-fabricante.png)

---

### 🟢 Instalación manual de drivers con SDI Lite

![Screenshot SDI Lite](./screenshots/sdi-lite.png)


---

## 🗂 Logs y Trazabilidad


El script genera un archivo de log detallado:

```
[Carpeta del script]\actualizacion_instalacion_log.txt
```

Este registro contiene información completa sobre cada paso realizado, incluyendo:

- 🔌 Verificación de conectividad a Internet

- 🔄 Instalación o actualización de Winget

- 📦 Estado de cada aplicación (instalada, actualizada o con error)

- ⚠️ Mensajes de advertencia o fallos en tiempo real

- 🖥️ Detección de fabricante y acciones sugeridas

- 🧰 Resultado de instalación de drivers mediante SDI Lite

- 🎨 Proceso de descarga y configuración de fondos de pantalla y protector Lively

- 💬 Cualquier error crítico documentado con marcas de tiempo

---

## ⚙️ Requisitos
- 💻 Windows 10 o superior
Requiere sistema compatible con winget, PowerShell moderno y soporte para ejecutar scripts.

- 🟦 PowerShell 5.1 o superior
El script utiliza funciones avanzadas de manejo de errores y ejecución de procesos.

- 🌐 Conexión a Internet activa
Necesaria para descargar Winget (si no está instalado), aplicaciones, controladores y fondos.

- 🛡️ Permisos de administrador
El script realiza cambios en el sistema, instala software, configura el registro y copia archivos en directorios protegidos como C:\Windows.

- 🏬 Microsoft Store funcional
Para sistemas que no tengan Winget, se requiere acceso a Microsoft Store para descargar el instalador oficial (App Installer).

---

## 🛠 Preparación previa (Microsoft Store)

En la mayoría de los casos, no es necesario realizar ninguna preparación previa, ya que el script detecta automáticamente si Winget está instalado y lo instala en caso de no estar disponible.

⚠️ Sin embargo, si el instalador muestra errores relacionados con winget, asegúrate de que esté disponible el componente "Instalador de aplicación" (App Installer) desde Microsoft Store.

Pasos para verificarlo manualmente:

1️⃣ Abrir Microsoft Store
2️⃣ Buscar "Instalador de aplicación"
3️⃣ Instalarlo o actualizarlo si ya está presente

✅ No es necesario iniciar sesión en Microsoft Store para realizar este paso.

Esto garantizará la funcionalidad de Winget y evitará fallos en sistemas que no tienen este componente actualizado.

---

## 🚀 Pasos de uso

1.- Ejecutar el archivo Instalador.bat con doble clic. El script se lanzará con privilegios de administrador si es necesario.

2.- Se verificará automáticamente la conexión a Internet, y si Winget no está instalado, el sistema lo descargará e instalará.

3.- En caso de requerir drivers, se utilizará SDI Lite, que descargará primero un conjunto de archivos base ("application" e "index") de aproximadamente 20 MB.
Luego, se abrirá una ventana donde deberás seleccionar manualmente los drivers recomendados para tu equipo antes de iniciar su descarga e instalación.

4.- El proceso continuará automáticamente: se instalarán o actualizarán las aplicaciones necesarias usando Winget (o mediante descarga directa si Winget falla).

5.- Se descargarán los fondos corporativos y el video del protector de pantalla desde Google Drive.

6.- Si está instalado Lively Wallpaper, se configurará automáticamente como protector de pantalla con el video descargado.

7.- Al finalizar, puedes revisar el archivo de log generado junto al script (actualizacion_instalacion_log.txt) para validar cada paso.

---

## 🖥️ Consideraciones Especiales

- 🧪 Si el equipo está virtualizado (VirtualBox, VMware, Hyper-V, etc.), se omite la detección del fabricante y se utiliza directamente SDI Lite para la gestión de drivers.

- 🏷️ Si se detecta un fabricante reconocido (HP, Dell, Lenovo, ASUS, etc.), el script muestra la página oficial de soporte para la descarga manual de drivers actualizados, como recomendación principal.

- 🔍 Si el fabricante no es reconocido o no tiene una URL mapeada, se sugiere al usuario hacer la verificación manual en la web del fabricante, y luego usar SDI Lite como herramienta de respaldo.

- ⚙️ En todos los casos, SDI Lite se encarga de descargar primero los archivos base necesarios (~20 MB) y luego permite seleccionar manualmente los drivers sugeridos por el sistema antes de su descarga e instalación.

---

## 🏷️ Archivos Incluidos

📁 **Instalador-ActualizadorPrimerasComputadoras-Vidanova-main**  
Contiene los archivos principales del lanzador y documentación:

- `Instalador.bat`: lanzador inicial. Verifica permisos y ejecuta el script principal.
- `Instalador.ps1`: script maestro que orquesta todo el proceso (conexión, Winget, drivers, apps, fondos).
- `README_Vidanova.md`: documentación del proyecto.

📁 **Código Separado**  
Contiene scripts divididos por funcionalidad para mejor mantenimiento y reutilización:

### 📂 Fondo y Protector de Pantalla
- `ConfigurarProtectorYFondoDePantalla.ps1`: descarga y configura imágenes, videos y Lively.scr como protector de pantalla.
- `ConfigurarProtectorYFondoDePantalla.bat`: ejecuta el script anterior desde entorno Batch.

### 📂 Programas
- `InstalarProgramas.ps1`: instala y actualiza las aplicaciones predefinidas, usando Winget o descarga directa.
- `InstalarProgramas.bat`: lanza el script de instalación de programas desde entorno Batch.

### 📂 Drivers
- `ActualizarDrivers.ps1`: detecta fabricante, muestra enlaces oficiales y lanza SDI Lite como opción.
- `ActualizarDrivers.bat`: ejecuta el proceso de drivers desde entorno Batch.

---

## 🧾 Licencia y Uso Interno

Este proyecto es propiedad de **VIDANOVA** y está diseñado exclusivamente para uso interno en la preparación de equipos y soporte técnico. Puede ser adaptado y mejorado internamente según necesidades futuras.

---

## 🤝 Contacto y Soporte

**Desarrollador de Software de IT en VIDANOVA**:  
Isaac Quinapallo  
📧 iquinapallo@vidanova.com.ec  
📧 isaacquinapallo@gmail.com