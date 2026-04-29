#Requires -Version 5.1

# -- Instalador de SoportePRO ----------------------------------
# Uso: iwr -useb https://raw.githubusercontent.com/brayam-marre/SoportePRO/main/install.ps1 | iex

$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Stop'
chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseUrl     = "https://raw.githubusercontent.com/brayam-marre/SoportePRO/main"
$installPath = "$env:LOCALAPPDATA\SoportePRO"

# -- Cabecera --------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "   ____                       _       ____  ____   ___  " -ForegroundColor Cyan
Write-Host "  / ___|  ___  _ __   ___  _ __| |_ ___|  _ \|  _ \ / _ \ " -ForegroundColor Cyan
Write-Host "  \___ \ / _ \| '_ \ / _ \| '__| __/ _ \ |_) | |_) | | | |" -ForegroundColor Cyan
Write-Host "   ___) | (_) | |_) | (_) | |  | ||  __/  __/|  _ <| |_| |" -ForegroundColor Cyan
Write-Host "  |____/ \___/| .__/ \___/|_|   \__\___|_|   |_| \_\\___/ " -ForegroundColor Cyan
Write-Host "              |_|" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Herramienta de Soporte Tecnico Profesional  v1.0.0" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
Write-Host ""

# -- Verificar PowerShell version -----------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "  ERROR: Se requiere PowerShell 5.1 o superior." -ForegroundColor Red
    exit 1
}

# -- Verificar conexion a internet ----------------------------
Write-Host "  Verificando conexion a internet..." -ForegroundColor DarkGray
try {
    $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 8
    Write-Host "  [OK] Conexion verificada" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Sin conexion a internet. Verifica tu red e intenta nuevamente." -ForegroundColor Red
    exit 1
}

# -- Crear directorios -----------------------------------------
Write-Host "  Preparando directorio de instalacion..." -ForegroundColor DarkGray
New-Item -ItemType Directory -Path $installPath           -Force | Out-Null
New-Item -ItemType Directory -Path "$installPath\modules" -Force | Out-Null

# -- Descargar archivos ----------------------------------------
Write-Host "  Descargando modulos..." -ForegroundColor DarkGray
Write-Host ""

$files = @(
    @{ Url = "$baseUrl/SoportePRO.ps1";              Out = "$installPath\SoportePRO.ps1" },
    @{ Url = "$baseUrl/modules/diagnostico.ps1";     Out = "$installPath\modules\diagnostico.ps1" },
    @{ Url = "$baseUrl/modules/limpieza.ps1";        Out = "$installPath\modules\limpieza.ps1" },
    @{ Url = "$baseUrl/modules/reparacion.ps1";      Out = "$installPath\modules\reparacion.ps1" },
    @{ Url = "$baseUrl/modules/red.ps1";             Out = "$installPath\modules\red.ps1" },
    @{ Url = "$baseUrl/modules/seguridad.ps1";       Out = "$installPath\modules\seguridad.ps1" },
    @{ Url = "$baseUrl/modules/software.ps1";        Out = "$installPath\modules\software.ps1" },
    @{ Url = "$baseUrl/modules/usuarios.ps1";        Out = "$installPath\modules\usuarios.ps1" },
    @{ Url = "$baseUrl/modules/hardware.ps1";        Out = "$installPath\modules\hardware.ps1" },
    @{ Url = "$baseUrl/modules/sistema.ps1";         Out = "$installPath\modules\sistema.ps1" },
    @{ Url = "$baseUrl/modules/scanner.ps1";         Out = "$installPath\modules\scanner.ps1" },
    @{ Url = "$baseUrl/modules/reporte.ps1";         Out = "$installPath\modules\reporte.ps1" }
)

$success = $true
foreach ($file in $files) {
    try {
        Invoke-WebRequest -Uri $file.Url -OutFile $file.Out -UseBasicParsing
        $label = Split-Path $file.Out -Leaf
        Write-Host "  [OK] $label" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudo descargar: $(Split-Path $file.Out -Leaf)" -ForegroundColor Red
        $success = $false
    }
}

if (-not $success) {
    Write-Host ""
    Write-Host "  Hubo errores al descargar. Intenta nuevamente." -ForegroundColor Red
    Remove-Item -Path $installPath -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# -- Lanzar herramienta ----------------------------------------
Write-Host ""
Write-Host "  $('-' * 60)" -ForegroundColor DarkGray
Write-Host "  Todos los modulos descargados. Iniciando SoportePRO..." -ForegroundColor Cyan
Write-Host "  (Los archivos se eliminaran automaticamente al cerrar)" -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 2

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$installPath\SoportePRO.ps1"
} catch {
    Write-Host "  Error al ejecutar SoportePRO: $($_.Exception.Message)" -ForegroundColor Red
}
