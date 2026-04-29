function Invoke-Limpieza {
    Show-Header
    Write-Section "LIMPIEZA Y OPTIMIZACION"

    $totalFreed = 0

    function Clear-Dir {
        param([string]$Path, [string]$Label)
        if (-not (Test-Path $Path)) {
            Write-Host "  [ -- ] $Label (no existe)" -ForegroundColor DarkGray
            return 0
        }
        $before = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
        Remove-Item "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue
        $freed = if ($before) { [math]::Round($before / 1MB, 2) } else { 0 }
        Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
        Write-Host "$Label" -NoNewline
        Write-Host "  ->  $freed MB liberados" -ForegroundColor Cyan
        return $freed
    }

    Write-Host "  Iniciando limpieza del sistema..." -ForegroundColor Yellow
    Write-Host ""

    # Temporales usuario
    $totalFreed += Clear-Dir -Path $env:TEMP                              -Label "Temporales de usuario (%TEMP%)"
    $totalFreed += Clear-Dir -Path "C:\Windows\Temp"                      -Label "Temporales del sistema (Windows\Temp)"
    $totalFreed += Clear-Dir -Path "C:\Windows\Prefetch"                  -Label "Archivos Prefetch"
    $totalFreed += Clear-Dir -Path "C:\Windows\Minidump"                  -Label "Volcados de memoria (Minidump)"
    $totalFreed += Clear-Dir -Path "$env:LOCALAPPDATA\Temp"               -Label "Temp de AppData Local"
    $totalFreed += Clear-Dir -Path "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" -Label "Cache de Internet Explorer / Edge"
    $totalFreed += Clear-Dir -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" -Label "Cache Google Chrome"
    $totalFreed += Clear-Dir -Path "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles" -Label "Cache Mozilla Firefox"

    # DNS
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
    ipconfig /flushdns 2>&1 | Out-Null
    Write-Host "Cache DNS vaciada"

    # Papelera
    try {
        $shell   = New-Object -ComObject Shell.Application
        $recycle = $shell.Namespace(0xA)
        $recycleSize = ($recycle.Items() | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $recycleFreed = if ($recycleSize) { [math]::Round($recycleSize / 1MB, 2) } else { 0 }
        $totalFreed += $recycleFreed
        Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
        Write-Host "Papelera de reciclaje vaciada" -NoNewline
        Write-Host "  ->  $recycleFreed MB liberados" -ForegroundColor Cyan
    } catch {
        Write-Host "  [ WARN ] Papelera de reciclaje: no se pudo vaciar" -ForegroundColor Yellow
    }

    # Windows Update cache
    Write-Host ""
    Write-Host "  Deteniendo Windows Update para limpiar cache..." -ForegroundColor DarkGray
    Stop-Service -Name wuauserv,bits -Force -ErrorAction SilentlyContinue
    $totalFreed += Clear-Dir -Path "C:\Windows\SoftwareDistribution\Download" -Label "Cache de Windows Update"
    Start-Service -Name wuauserv,bits -ErrorAction SilentlyContinue

    # Logs antiguos del sistema (mayores a 30 dias)
    Write-Host ""
    Write-Host "  Limpiando logs del sistema mayores a 30 dias..." -ForegroundColor DarkGray
    $logPaths = @("C:\Windows\Logs", "$env:LOCALAPPDATA\CrashDumps")
    foreach ($lp in $logPaths) {
        if (Test-Path $lp) {
            $oldLogs = Get-ChildItem $lp -Recurse -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
            $logSize = ($oldLogs | Measure-Object -Property Length -Sum).Sum
            $oldLogs | Remove-Item -Force -ErrorAction SilentlyContinue
            $freed = if ($logSize) { [math]::Round($logSize / 1MB, 2) } else { 0 }
            $totalFreed += $freed
            if ($freed -gt 0) {
                Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
                Write-Host "Logs antiguos ($lp)" -NoNewline
                Write-Host "  ->  $freed MB liberados" -ForegroundColor Cyan
            }
        }
    }

    # Optimizacion de memoria RAM
    Write-Host ""
    Write-Host "  Optimizando memoria RAM..." -ForegroundColor DarkGray
    [System.GC]::Collect()
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
    Write-Host "Recolector de basura de .NET ejecutado"

    Write-Host ""
    Write-Host "  $('-' * 85)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  TOTAL LIBERADO: $([math]::Round($totalFreed, 2)) MB  ($([math]::Round($totalFreed / 1024, 2)) GB)" -ForegroundColor Cyan
    Write-Host ""

    Write-Log "Limpieza ejecutada - $([math]::Round($totalFreed, 2)) MB liberados"
}
