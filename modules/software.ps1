function Invoke-Software {
    Show-Header
    Write-Section "SOFTWARE Y PROCESOS"

    Write-Host "  [1]   Top procesos por CPU y RAM"
    Write-Host "  [2]   Programas instalados"
    Write-Host "  [3]   Servicios criticos (estado)"
    Write-Host "  [4]   Programas de inicio (Startup)"
    Write-Host "  [5]   Gestionar servicios (iniciar/detener)"
    Write-Host "  [6]   Terminar proceso por nombre"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Show-TopProcesses }
        '2' { Show-InstalledSoftware }
        '3' { Show-CriticalServices }
        '4' { Show-StartupPrograms }
        '5' { Manage-Service }
        '6' { Stop-ProcessByName }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Log "Software - opcion: $sub"
}

function Show-TopProcesses {
    Write-Host ""
    Write-Host "  TOP 15 PROCESOS POR CPU" -ForegroundColor Yellow
    Write-Host "  {0,-35} {1,10} {2,12} {3}" -f "Proceso", "CPU (s)", "RAM (MB)", "PID"
    Write-Host "  $('-' * 65)"

    Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 | ForEach-Object {
        $ram   = [math]::Round($_.WorkingSet64 / 1MB, 1)
        $cpu   = [math]::Round($_.CPU, 1)
        $color = if ($cpu -gt 60) { 'Red' } elseif ($cpu -gt 20) { 'Yellow' } else { 'White' }
        Write-Host ("  {0,-35} {1,10} {2,12} {3}" -f $_.Name, $cpu, "$ram MB", $_.Id) -ForegroundColor $color
    }
    Write-Host ""

    Write-Host "  TOP 15 PROCESOS POR RAM" -ForegroundColor Yellow
    Write-Host "  {0,-35} {1,12} {2,12} {3}" -f "Proceso", "RAM (MB)", "CPU (s)", "PID"
    Write-Host "  $('-' * 65)"

    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 | ForEach-Object {
        $ram   = [math]::Round($_.WorkingSet64 / 1MB, 1)
        $cpu   = [math]::Round($_.CPU, 1)
        $color = if ($ram -gt 1000) { 'Red' } elseif ($ram -gt 300) { 'Yellow' } else { 'White' }
        Write-Host ("  {0,-35} {1,12} {2,12} {3}" -f $_.Name, "$ram MB", $cpu, $_.Id) -ForegroundColor $color
    }
    Write-Host ""

    # Totales
    $totalRam  = [math]::Round((Get-Process | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 0)
    $procCount = (Get-Process).Count
    Write-Host "  Procesos activos: $procCount  |  RAM total en uso por procesos: $totalRam MB" -ForegroundColor Cyan
    Write-Host ""
}

function Show-InstalledSoftware {
    Write-Host ""
    Write-Host "  PROGRAMAS INSTALADOS" -ForegroundColor Yellow

    $regPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $progs = $regPaths | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName -Unique

    Write-Host "  Total instalados: $($progs.Count)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Filtrar por nombre (Enter para ver todos): " -NoNewline
    $filter = Read-Host

    $filtered = if ($filter) { $progs | Where-Object { $_.DisplayName -ilike "*$filter*" } } else { $progs }

    Write-Host ""
    Write-Host "  {0,-45} {1,-15} {2}" -f "Nombre", "Version", "Editor"
    Write-Host "  $('-' * 85)"

    $filtered | Select-Object -First 40 | ForEach-Object {
        $name = if ($_.DisplayName.Length -gt 43) { $_.DisplayName.Substring(0,43) + ".." } else { $_.DisplayName }
        $ver  = if ($_.DisplayVersion -and $_.DisplayVersion.Length -gt 13) { $_.DisplayVersion.Substring(0,13) } else { $_.DisplayVersion }
        $pub  = if ($_.Publisher -and $_.Publisher.Length -gt 25) { $_.Publisher.Substring(0,25) + ".." } else { $_.Publisher }
        Write-Host ("  {0,-45} {1,-15} {2}" -f $name, $ver, $pub)
    }

    if ($filtered.Count -gt 40) {
        Write-Host ""
        Write-Host "  Mostrando 40 de $($filtered.Count). Genera un reporte para la lista completa." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-CriticalServices {
    Write-Host ""
    Write-Host "  SERVICIOS CRITICOS DEL SISTEMA" -ForegroundColor Yellow
    Write-Host "  {0,-35} {1,-15} {2,-15} {3}" -f "Servicio", "Estado", "Tipo inicio", "Nombre"
    Write-Host "  $('-' * 80)"

    $critical = @(
        @{ Name = 'wuauserv';       Display = 'Windows Update' },
        @{ Name = 'wscsvc';         Display = 'Centro de Seguridad' },
        @{ Name = 'WinDefend';      Display = 'Windows Defender' },
        @{ Name = 'mpssvc';         Display = 'Firewall de Windows' },
        @{ Name = 'EventLog';       Display = 'Registro de Eventos' },
        @{ Name = 'Spooler';        Display = 'Cola de Impresion' },
        @{ Name = 'dnscache';       Display = 'Cliente DNS' },
        @{ Name = 'LanmanServer';   Display = 'Servidor (compartir)' },
        @{ Name = 'LanmanWorkstation'; Display = 'Estacion de trabajo' },
        @{ Name = 'RpcSs';          Display = 'Llamada a procedimiento remoto' },
        @{ Name = 'W32Time';        Display = 'Hora de Windows' },
        @{ Name = 'BITS';           Display = 'Transferencia inteligente' },
        @{ Name = 'CryptSvc';       Display = 'Servicios criptograficos' },
        @{ Name = 'themes';         Display = 'Temas' },
        @{ Name = 'AudioSrv';       Display = 'Audio de Windows' }
    )

    foreach ($svc in $critical) {
        $s = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($s) {
            $stColor = switch ($s.Status) {
                'Running' { 'Green' }
                'Stopped' { 'Red' }
                default   { 'Yellow' }
            }
            Write-Host ("  {0,-35} " -f $svc.Display) -NoNewline
            Write-Host ("{0,-15} " -f $s.Status) -ForegroundColor $stColor -NoNewline
            Write-Host ("{0,-15} " -f $s.StartType) -NoNewline
            Write-Host $svc.Name -ForegroundColor DarkGray
        } else {
            Write-Host ("  {0,-35} " -f $svc.Display) -NoNewline
            Write-Host "No instalado" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

function Show-StartupPrograms {
    Write-Host ""
    Write-Host "  PROGRAMAS DE INICIO" -ForegroundColor Yellow

    $regKeys = @(
        @{ Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';     Scope = 'Sistema' },
        @{ Key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';     Scope = 'Usuario' },
        @{ Key = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Scope = 'Sistema x86' }
    )

    $startups = $regKeys | ForEach-Object {
        $scope = $_.Scope
        $props = Get-ItemProperty $_.Key -ErrorAction SilentlyContinue
        if ($props) {
            $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                [PSCustomObject]@{ Name = $_.Name; Value = $_.Value; Scope = $scope }
            }
        }
    }

    # Carpetas de startup
    $startupFolders = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )
    $startupFolders | ForEach-Object {
        Get-ChildItem $_ -ErrorAction SilentlyContinue | ForEach-Object {
            $startups += [PSCustomObject]@{ Name = $_.Name; Value = $_.FullName; Scope = 'Carpeta Startup' }
        }
    }

    if ($startups) {
        Write-Host "  Total: $($startups.Count) entradas" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  {0,-35} {1,-15} {2}" -f "Nombre", "Alcance", "Ruta/Valor"
        Write-Host "  $('-' * 85)"
        $startups | ForEach-Object {
            $val = if ($_.Value.Length -gt 45) { $_.Value.Substring(0,45) + ".." } else { $_.Value }
            Write-Host ("  {0,-35} {1,-15} {2}" -f $_.Name, $_.Scope, $val)
        }
    } else {
        Write-Host "  No se encontraron programas de inicio configurados." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Manage-Service {
    Write-Host ""
    $svcName = Read-Host "  Nombre del servicio"
    if (-not $svcName) { return }

    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  Servicio no encontrado: $svcName" -ForegroundColor Red
        return
    }

    Write-Host "  Servicio: $($svc.DisplayName) ($($svc.Status))"
    Write-Host "  [1] Iniciar  [2] Detener  [3] Reiniciar  [0] Cancelar"
    $action = Read-Host "  Accion"

    switch ($action) {
        '1' { Start-Service   $svcName -ErrorAction SilentlyContinue; Write-Host "  Servicio iniciado." -ForegroundColor Green }
        '2' { Stop-Service    $svcName -Force -ErrorAction SilentlyContinue; Write-Host "  Servicio detenido." -ForegroundColor Yellow }
        '3' { Restart-Service $svcName -Force -ErrorAction SilentlyContinue; Write-Host "  Servicio reiniciado." -ForegroundColor Green }
        '0' { return }
    }
    Write-Log "Servicio $svcName - accion: $action"
}

function Stop-ProcessByName {
    Write-Host ""
    $pName = Read-Host "  Nombre del proceso a terminar (sin .exe)"
    if (-not $pName) { return }

    $procs = Get-Process -Name $pName -ErrorAction SilentlyContinue
    if (-not $procs) {
        Write-Host "  No se encontro el proceso: $pName" -ForegroundColor Red
        return
    }

    Write-Host "  Procesos encontrados: $($procs.Count)"
    $procs | ForEach-Object { Write-Host "    PID $($_.Id): $($_.Name) ($([math]::Round($_.WorkingSet64/1MB,1)) MB)" }
    Write-Host ""
    $confirm = Read-Host "  Terminar todos estos procesos? (s/n)"
    if ($confirm -ieq 's') {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "  Proceso(s) terminado(s)." -ForegroundColor Green
        Write-Log "Proceso terminado: $pName"
    }
}
