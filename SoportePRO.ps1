#Requires -Version 5.1

# ============================================================
#  SoportePRO - Herramienta de Soporte Tecnico para Windows
# ============================================================

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

chcp 65001 | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$script:InstallPath = $PSScriptRoot
$script:LogFile     = "$script:InstallPath\soportepro.log"
$script:Version     = "2.0.0"

# -- Elevacion de privilegios ----------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ""
    Write-Host "  Se requieren permisos de administrador. Reiniciando elevado..." -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# -- Carga de modulos ------------------------------------------
$modules = @('diagnostico','limpieza','reparacion','red','seguridad','software',
             'usuarios','hardware','sistema','scanner','reporte')
foreach ($mod in $modules) {
    $path = "$script:InstallPath\modules\$mod.ps1"
    if (Test-Path $path) { . $path }
    else { Write-Warning "Modulo no encontrado: $mod.ps1" }
}

# -- Utilidades globales ---------------------------------------
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "[$ts][$Level] $Message" | Add-Content -Path $script:LogFile -Encoding UTF8
}

function Write-Section {
    param([string]$Title, [string]$Color = 'Cyan')
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $Color
    Write-Host "  $('-' * 85)" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Header {
    Clear-Host
    $c = 'Cyan'
    Write-Host ""
    Write-Host "   ____                       _       ____  ____   ___  " -ForegroundColor $c
    Write-Host "  / ___|  ___  _ __   ___  _ __| |_ ___|  _ \|  _ \ / _ \ " -ForegroundColor $c
    Write-Host "  \___ \ / _ \| '_ \ / _ \| '__| __/ _ \ |_) | |_) | | | |" -ForegroundColor $c
    Write-Host "   ___) | (_) | |_) | (_) | |  | ||  __/  __/|  _ <| |_| |" -ForegroundColor $c
    Write-Host "  |____/ \___/| .__/ \___/|_|   \__\___|_|   |_| \_\\___/ " -ForegroundColor $c
    Write-Host "              |_|" -ForegroundColor $c
    Write-Host ""
    Write-Host "  Herramienta de Soporte Tecnico Profesional  v$script:Version" -ForegroundColor DarkCyan
    Write-Host "  $(Get-Date -Format 'dddd, dd MMMM yyyy  HH:mm')" -ForegroundColor DarkGray
    Write-Host "  Equipo: $env:COMPUTERNAME  |  Usuario: $env:USERNAME  |  Admin: Si" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $('-' * 85)" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Menu {
    Show-Header
    Write-Host "  MENU PRINCIPAL" -ForegroundColor White
    Write-Host ""
    Write-Host "  -- SOPORTE TI --" -ForegroundColor DarkGray
    Write-Host "  [1]" -ForegroundColor Yellow -NoNewline; Write-Host "   Diagnostico del Sistema"
    Write-Host "  [A]" -ForegroundColor Yellow -NoNewline; Write-Host "   Analisis del Equipo (que se puede mejorar)"
    Write-Host "  [2]" -ForegroundColor Yellow -NoNewline; Write-Host "   Limpieza y Optimizacion"
    Write-Host "  [3]" -ForegroundColor Yellow -NoNewline; Write-Host "   Reparacion de Windows"
    Write-Host "  [4]" -ForegroundColor Yellow -NoNewline; Write-Host "   Software y Procesos"
    Write-Host "  [5]" -ForegroundColor Yellow -NoNewline; Write-Host "   Usuarios y Cuentas"
    Write-Host "  [6]" -ForegroundColor Yellow -NoNewline; Write-Host "   Hardware  (SMART · Bateria · Benchmark)"
    Write-Host "  [7]" -ForegroundColor Yellow -NoNewline; Write-Host "   Sistema   (BSOD · Restauracion · Activacion)"
    Write-Host ""
    Write-Host "  -- REDES Y CIBERSEGURIDAD --" -ForegroundColor DarkGray
    Write-Host "  [8]" -ForegroundColor Magenta -NoNewline; Write-Host "   Redes y Conectividad"
    Write-Host "  [9]" -ForegroundColor Magenta -NoNewline; Write-Host "   Ciberseguridad y Auditoria"
    Write-Host "  [10]" -ForegroundColor Magenta -NoNewline; Write-Host "  Escaner LAN · Trafico · Hashes · Baseline"
    Write-Host ""
    Write-Host "  -- REPORTES --" -ForegroundColor DarkGray
    Write-Host "  [R]" -ForegroundColor Green -NoNewline; Write-Host "   Generar Reporte (TXT + HTML)"
    Write-Host "  [M]" -ForegroundColor Cyan  -NoNewline; Write-Host "   Modo Mantenimiento Completo"
    Write-Host ""
    Write-Host "  [0]" -ForegroundColor Red -NoNewline; Write-Host "   Salir"
    Write-Host ""
    Write-Host "  $('-' * 85)" -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-Cleanup {
    Write-Host ""
    Write-Host "  Cerrando SoportePRO..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    $path = $script:InstallPath
    # Solo auto-eliminar si se ejecuta desde la instalacion temporal en AppData
    if ($path -like "*$env:LOCALAPPDATA*") {
        Write-Host "  Los archivos temporales seran eliminados automaticamente." -ForegroundColor DarkGray
        $cleanupCmd = "ping 127.0.0.1 -n 4 > nul & rd /s /q `"$path`""
        Start-Process cmd -ArgumentList "/c $cleanupCmd" -WindowStyle Hidden
    }
}

function Pause-Menu {
    Write-Host ""
    Write-Host "  Presiona Enter para volver al menu..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

function Invoke-Mantenimiento {
    Show-Header
    Write-Section "MODO MANTENIMIENTO COMPLETO" "Cyan"
    Write-Host "  Ejecutara automaticamente:" -ForegroundColor Yellow
    Write-Host "  1. Diagnostico del sistema"
    Write-Host "  2. Limpieza y optimizacion"
    Write-Host "  3. Reparacion de Windows (SFC + DISM)"
    Write-Host "  4. Restablecimiento de red"
    Write-Host "  5. Baseline de seguridad"
    Write-Host "  6. Reporte final completo"
    Write-Host ""
    $confirm = Read-Host "  Iniciar mantenimiento completo? (s/n)"
    if ($confirm -ine 's') { return }

    Write-Log "Mantenimiento completo iniciado"

    Show-Header; Write-Host "  [1/6] DIAGNOSTICO" -ForegroundColor Cyan
    Invoke-Diagnostico
    Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null

    Show-Header; Write-Host "  [2/6] LIMPIEZA" -ForegroundColor Cyan
    Invoke-Limpieza
    Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null

    Show-Header; Write-Host "  [3/6] REPARACION - SFC" -ForegroundColor Cyan
    Invoke-SFC
    Write-Host ""; Read-Host "  Enter para continuar con DISM..." | Out-Null
    Invoke-DISM
    Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null

    Show-Header; Write-Host "  [4/6] RED" -ForegroundColor Cyan
    Invoke-NetworkReset
    Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null

    Show-Header; Write-Host "  [5/6] BASELINE DE SEGURIDAD" -ForegroundColor Cyan
    Invoke-SecurityBaseline
    Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null

    Show-Header; Write-Host "  [6/6] GENERANDO REPORTE FINAL" -ForegroundColor Cyan
    Invoke-Reporte

    Write-Host ""
    Write-Host "  Mantenimiento completo finalizado." -ForegroundColor Green
    Write-Log "Mantenimiento completo finalizado"
}

# -- Bucle principal -------------------------------------------
Write-Log "SoportePRO v$script:Version iniciado - Usuario: $env:USERNAME - Equipo: $env:COMPUTERNAME"

while ($true) {
    Show-Menu
    $choice = Read-Host "  Selecciona una opcion"
    Write-Log "Opcion seleccionada: $choice"

    switch ($choice.ToUpper()) {
        '1'  { Invoke-Diagnostico;      Pause-Menu }
        'A'  { Invoke-AnalisisEquipo;  Pause-Menu }
        '2'  { Invoke-Limpieza;        Pause-Menu }
        '3'  { Invoke-Reparacion;     Pause-Menu }
        '4'  { Invoke-Software;       Pause-Menu }
        '5'  { Invoke-Usuarios;       Pause-Menu }
        '6'  { Invoke-Hardware;       Pause-Menu }
        '7'  { Invoke-Sistema;        Pause-Menu }
        '8'  { Invoke-Red;            Pause-Menu }
        '9'  { Invoke-Seguridad;      Pause-Menu }
        '10' { Invoke-Scanner;        Pause-Menu }
        'R'  { Invoke-Reporte;        Pause-Menu }
        'M'  { Invoke-Mantenimiento;  Pause-Menu }
        '0'  { Invoke-Cleanup; exit }
        default {
            Write-Host ""
            Write-Host "  Opcion no valida. Intenta nuevamente." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
