function Invoke-Sistema {
    Show-Header
    Write-Section "SISTEMA"

    Write-Host "  [1]   Analizador de pantallazos azules (BSOD)"
    Write-Host "  [2]   Puntos de restauracion"
    Write-Host "  [3]   Activacion y licencia de Windows"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Invoke-BSODAnalyzer }
        '2' { Invoke-RestorePoints }
        '3' { Invoke-WindowsActivation }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }
    Write-Log "Sistema - opcion: $sub"
}

# ── BSOD Analyzer ─────────────────────────────────────────────
function Invoke-BSODAnalyzer {
    Write-Host ""
    Write-Host "  ANALIZADOR DE PANTALLAZOS AZULES (BSOD)" -ForegroundColor Yellow
    Write-Host ""

    # Buscar eventos BugCheck en el log del sistema
    $bsodEvents = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = @(1001, 41)
        StartTime = (Get-Date).AddDays(-30)
    } -ErrorAction SilentlyContinue | Select-Object -First 15

    if ($bsodEvents) {
        Write-Host "  EVENTOS BSOD (ultimos 30 dias)" -ForegroundColor Yellow
        Write-Host "  Total encontrados: $($bsodEvents.Count)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  {0,-20} {1,-10} {2}" -f "Fecha", "ID", "Descripcion"
        Write-Host "  $('-' * 70)"

        $bsodEvents | ForEach-Object {
            $ev = $_
            $color = if ($ev.Id -eq 41) { 'Red' } else { 'Yellow' }
            $msg   = if ($ev.Message) { $ev.Message.Substring(0, [Math]::Min(50, $ev.Message.Length)) } else { "Sin descripcion" }
            Write-Host ("  {0,-20} {1,-10} {2}" -f $ev.TimeCreated.ToString('dd/MM/yy HH:mm'), $ev.Id, $msg) -ForegroundColor $color
        }
    } else {
        Write-Host "  No se encontraron BSOD en los ultimos 30 dias." -ForegroundColor Green
    }

    Write-Host ""

    # Minidumps
    Write-Host "  ARCHIVOS MINIDUMP" -ForegroundColor Yellow
    $dumpPath = "C:\Windows\Minidump"
    if (Test-Path $dumpPath) {
        $dumps = Get-ChildItem $dumpPath -Filter "*.dmp" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($dumps) {
            Write-Host "  Dumps encontrados: $($dumps.Count)"
            Write-Host ""
            Write-Host "  {0,-35} {1,-15} {2}" -f "Archivo", "Fecha", "Tamano"
            Write-Host "  $('-' * 60)"
            $dumps | Select-Object -First 10 | ForEach-Object {
                Write-Host ("  {0,-35} {1,-15} {2}" -f $_.Name, $_.LastWriteTime.ToString('dd/MM/yyyy HH:mm'), "$([math]::Round($_.Length/1KB,0)) KB") -ForegroundColor Yellow
            }
        } else {
            Write-Host "  No hay minidumps almacenados." -ForegroundColor Green
        }
    } else {
        Write-Host "  Carpeta Minidump no encontrada." -ForegroundColor DarkGray
    }

    Write-Host ""

    # Ultimo apagado inesperado
    Write-Host "  HISTORIAL DE APAGADOS INESPERADOS (ultimos 10)" -ForegroundColor Yellow
    $unexpectedShutdowns = Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        Id        = 6008
        StartTime = (Get-Date).AddDays(-90)
    } -ErrorAction SilentlyContinue | Select-Object -First 10

    if ($unexpectedShutdowns) {
        $unexpectedShutdowns | ForEach-Object {
            Write-Host "  $($_.TimeCreated.ToString('dd/MM/yyyy HH:mm')) - Apagado inesperado del sistema" -ForegroundColor Red
        }
    } else {
        Write-Host "  No se registraron apagados inesperados recientes." -ForegroundColor Green
    }
    Write-Host ""
    Write-Log "BSOD analyzer ejecutado"
}

# ── Puntos de restauracion ────────────────────────────────────
function Invoke-RestorePoints {
    Write-Host ""
    Write-Host "  PUNTOS DE RESTAURACION DEL SISTEMA" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1]   Ver puntos de restauracion existentes"
    Write-Host "  [2]   Crear nuevo punto de restauracion"
    Write-Host "  [3]   Habilitar Restauracion del sistema en C:"
    Write-Host "  [0]   Volver"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' {
            Write-Host ""
            $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
            if ($points) {
                Write-Host "  {0,-5} {1,-30} {2,-20} {3}" -f "#", "Descripcion", "Fecha", "Tipo"
                Write-Host "  $('-' * 75)"
                $points | Select-Object -Last 15 | ForEach-Object {
                    $typeMap = @{ 0='Manual'; 1='Sistema'; 2='Actualiz.'; 3='Aplic.'; 4='Desinstala.' }
                    $tipo = $typeMap[[int]$_.RestorePointType]
                    if (-not $tipo) { $tipo = "Tipo $($_.RestorePointType)" }
                    $fecha = [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
                    Write-Host ("  {0,-5} {1,-30} {2,-20} {3}" -f $_.SequenceNumber, $_.Description.Substring(0,[Math]::Min(28,$_.Description.Length)), $fecha.ToString('dd/MM/yyyy HH:mm'), $tipo)
                }
                Write-Host ""
                Write-Host "  Total: $($points.Count) puntos de restauracion" -ForegroundColor Cyan
            } else {
                Write-Host "  No se encontraron puntos de restauracion." -ForegroundColor Yellow
                Write-Host "  Es posible que la Restauracion del sistema este deshabilitada." -ForegroundColor DarkGray
            }
        }
        '2' {
            $desc = Read-Host "  Descripcion del punto (Enter = 'SoportePRO - Mantenimiento')"
            if (-not $desc) { $desc = "SoportePRO - Mantenimiento $(Get-Date -Format 'dd/MM/yyyy')" }
            Write-Host "  Creando punto de restauracion..." -ForegroundColor DarkGray
            try {
                Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
                Write-Host "  [OK] Punto de restauracion creado: $desc" -ForegroundColor Green
                Write-Log "Punto de restauracion creado: $desc"
            } catch {
                Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  Intenta habilitar la Restauracion del sistema primero (opcion 3)." -ForegroundColor DarkGray
            }
        }
        '3' {
            Write-Host "  Habilitando Restauracion del sistema en C:..." -ForegroundColor DarkGray
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            vssadmin resize shadowstorage /for=C: /on=C: /maxsize=10% 2>&1 | Out-Null
            Write-Host "  [OK] Restauracion del sistema habilitada en C:" -ForegroundColor Green
            Write-Log "Restauracion del sistema habilitada"
        }
        '0' { return }
    }
    Write-Host ""
}

# ── Activacion de Windows ─────────────────────────────────────
function Invoke-WindowsActivation {
    Write-Host ""
    Write-Host "  ACTIVACION Y LICENCIA DE WINDOWS" -ForegroundColor Yellow
    Write-Host ""

    # Estado de activacion via WMI
    $license = Get-WmiObject SoftwareLicensingProduct -ErrorAction SilentlyContinue |
               Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" } |
               Select-Object -First 1

    if ($license) {
        $statusMap = @{
            0 = 'No licenciado'
            1 = 'Licenciado'
            2 = 'Fuera de caja (OOB Grace)'
            3 = 'Periodo de gracia'
            4 = 'Periodo de gracia no genuino'
            5 = 'Notificacion'
            6 = 'Periodo de gracia extendido'
        }
        $activationStatus = $statusMap[[int]$license.LicenseStatus]
        $actColor = if ($license.LicenseStatus -eq 1) { 'Green' } else { 'Red' }

        Write-Host "  Producto          : $($license.Name)"
        Write-Host "  Clave parcial     : $($license.PartialProductKey)"
        Write-Host "  Estado            : " -NoNewline; Write-Host $activationStatus -ForegroundColor $actColor
        Write-Host "  Canal             : $($license.ProductKeyChannel)"

        if ($license.LicenseStatus -eq 1) {
            Write-Host ""
            Write-Host "  Windows esta activado correctamente." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  Windows NO esta activado." -ForegroundColor Red
        }
    }

    # slmgr /xpr para ver expiracion
    Write-Host ""
    Write-Host "  DETALLE EXTENDIDO (slmgr)" -ForegroundColor Yellow
    $slmgr = cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
    $slmgr | Select-String "Name|Description|License Status|Partial Product Key|License Type" | ForEach-Object {
        Write-Host "  $_"
    }

    Write-Host ""
    Write-Host "  OPCIONES" -ForegroundColor Yellow
    Write-Host "  [1]  Ver estado completo (slmgr /xpr)"
    Write-Host "  [2]  Abrir activacion de Windows (GUI)"
    Write-Host "  [0]  Volver"
    Write-Host ""

    $opt = Read-Host "  Opcion"
    switch ($opt) {
        '1' {
            cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /xpr 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
        '2' {
            Start-Process ms-settings:activation
            Write-Host "  Abriendo configuracion de activacion..." -ForegroundColor Green
        }
    }
    Write-Host ""
    Write-Log "Activacion de Windows verificada"
}
