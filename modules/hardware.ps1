function Invoke-Hardware {
    Show-Header
    Write-Section "HARDWARE AVANZADO"

    Write-Host "  [1]   Salud del disco (SMART)"
    Write-Host "  [2]   Informacion de bateria"
    Write-Host "  [3]   Benchmark del sistema"
    Write-Host "  [4]   Ver todo"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Show-DiskSMART }
        '2' { Show-BatteryInfo }
        '3' { Invoke-Benchmark }
        '4' {
            Show-DiskSMART
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-BatteryInfo
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Invoke-Benchmark
        }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }
    Write-Log "Hardware - opcion: $sub"
}

function Show-DiskSMART {
    Write-Host ""
    Write-Host "  SALUD DE DISCOS (SMART)" -ForegroundColor Yellow
    Write-Host ""

    $disks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($disks) {
        Write-Host "  {0,-35} {1,-12} {2,-12} {3,-10} {4}" -f "Disco", "Tipo", "Salud", "Estado", "Tamano"
        Write-Host "  $('-' * 80)"
        $disks | ForEach-Object {
            $hColor = switch ($_.HealthStatus) {
                'Healthy'  { 'Green' }
                'Warning'  { 'Yellow' }
                'Unhealthy'{ 'Red' }
                default    { 'White' }
            }
            $sColor = if ($_.OperationalStatus -eq 'OK') { 'Green' } else { 'Red' }
            $size   = "$([math]::Round($_.Size / 1GB, 0)) GB"
            $name   = if ($_.FriendlyName.Length -gt 33) { $_.FriendlyName.Substring(0,33) + ".." } else { $_.FriendlyName }
            Write-Host ("  {0,-35} {1,-12} " -f $name, $_.MediaType) -NoNewline
            Write-Host ("{0,-12} " -f $_.HealthStatus) -ForegroundColor $hColor -NoNewline
            Write-Host ("{0,-10} " -f $_.OperationalStatus) -ForegroundColor $sColor -NoNewline
            Write-Host $size
        }
        Write-Host ""

        # Contadores de confiabilidad
        Write-Host "  CONTADORES DE CONFIABILIDAD" -ForegroundColor Yellow
        $disks | ForEach-Object {
            $disk = $_
            $rel  = Get-StorageReliabilityCounter -PhysicalDisk $_ -ErrorAction SilentlyContinue
            if ($rel) {
                Write-Host ""
                Write-Host "  $($disk.FriendlyName)" -ForegroundColor Cyan
                if ($rel.Temperature -gt 0) {
                    $tColor = if ($rel.Temperature -gt 55) { 'Red' } elseif ($rel.Temperature -gt 45) { 'Yellow' } else { 'Green' }
                    Write-Host "    Temperatura       : " -NoNewline; Write-Host "$($rel.Temperature) C" -ForegroundColor $tColor
                }
                if ($rel.Wear -ne $null -and $rel.Wear -gt 0) {
                    $wColor = if ($rel.Wear -gt 80) { 'Red' } elseif ($rel.Wear -gt 50) { 'Yellow' } else { 'Green' }
                    Write-Host "    Desgaste (SSD)    : " -NoNewline; Write-Host "$($rel.Wear)%" -ForegroundColor $wColor
                }
                if ($rel.PowerOnHours -gt 0) {
                    Write-Host "    Horas encendido   : $($rel.PowerOnHours) h ($([math]::Round($rel.PowerOnHours / 24 / 365, 1)) años)"
                }
                if ($rel.ReadErrorsTotal -gt 0) {
                    Write-Host "    Errores de lectura: " -NoNewline; Write-Host $rel.ReadErrorsTotal -ForegroundColor Yellow
                }
                if ($rel.WriteErrorsTotal -gt 0) {
                    Write-Host "    Errores de escrit.: " -NoNewline; Write-Host $rel.WriteErrorsTotal -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "  No se pudieron obtener datos SMART." -ForegroundColor DarkGray
        Write-Host "  Usando informacion basica de discos:" -ForegroundColor DarkGray
        Write-Host ""
        Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null } | ForEach-Object {
            $total = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
            $pct   = [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100, 1)
            $color = if ($pct -gt 90) { 'Red' } elseif ($pct -gt 75) { 'Yellow' } else { 'Green' }
            Write-Host "  Unidad $($_.Name): $total GB - " -NoNewline
            Write-Host "$pct% usado" -ForegroundColor $color
        }
    }
    Write-Host ""
    Write-Log "SMART ejecutado"
}

function Show-BatteryInfo {
    Write-Host ""
    Write-Host "  INFORMACION DE BATERIA" -ForegroundColor Yellow
    Write-Host ""

    $batteries = Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue
    if ($batteries) {
        $batteries | ForEach-Object {
            $bat = $_
            $chargeColor = if ($bat.EstimatedChargeRemaining -lt 20) { 'Red' } `
                           elseif ($bat.EstimatedChargeRemaining -lt 50) { 'Yellow' } else { 'Green' }

            $statusMap = @{
                1 = 'Descargando'; 2 = 'En carga'; 3 = 'Carga completa'
                4 = 'Bajo'; 5 = 'Critico'; 6 = 'Cargando y alto'
                7 = 'Cargando y bajo'; 8 = 'Cargando y critico'
                9 = 'Desconocido'; 10 = 'Parcialmente cargado'
            }
            $statusText = $statusMap[[int]$bat.BatteryStatus]

            Write-Host "  Nombre          : $($bat.Name)"
            Write-Host "  Estado          : $statusText"
            Write-Host "  Carga actual    : " -NoNewline
            Write-Host "$($bat.EstimatedChargeRemaining)%" -ForegroundColor $chargeColor
            Write-Host "  Tiempo restante : " -NoNewline
            if ($bat.EstimatedRunTime -lt 71582) {
                $hours = [math]::Floor($bat.EstimatedRunTime / 60)
                $mins  = $bat.EstimatedRunTime % 60
                Write-Host "$hours h $mins min" -ForegroundColor $chargeColor
            } else {
                Write-Host "Conectado a corriente" -ForegroundColor Green
            }
            Write-Host "  Quimica         : $($bat.Chemistry)"
            Write-Host "  Voltaje         : $($bat.DesignVoltage) mV"
        }

        # Reporte de bateria con powercfg
        Write-Host ""
        $ask = Read-Host "  Generar reporte detallado de bateria en el escritorio? (s/n)"
        if ($ask -ieq 's') {
            $reportPath = "$([Environment]::GetFolderPath('Desktop'))\bateria_report.html"
            powercfg /batteryreport /output $reportPath 2>&1 | Out-Null
            if (Test-Path $reportPath) {
                Write-Host "  [OK] Reporte guardado: $reportPath" -ForegroundColor Green
                Start-Process $reportPath
            } else {
                Write-Host "  No se pudo generar el reporte." -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "  No se detecto bateria en este equipo (equipo de escritorio)." -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Log "Bateria ejecutado"
}

function Invoke-Benchmark {
    Write-Host ""
    Write-Host "  BENCHMARK DEL SISTEMA" -ForegroundColor Yellow
    Write-Host "  (Prueba de rendimiento rapida — aprox. 30 segundos)" -ForegroundColor DarkGray
    Write-Host ""

    # CPU Benchmark
    Write-Host "  Ejecutando benchmark de CPU..." -ForegroundColor DarkGray
    $cpuStart = Get-Date
    $result   = 0
    for ($i = 1; $i -le 1000000; $i++) { $result += [math]::Sqrt($i) * [math]::Log($i) }
    $cpuTime  = ([math]::Round(((Get-Date) - $cpuStart).TotalMilliseconds, 0))
    $cpuScore = [math]::Round(1000000 / ($cpuTime / 1000), 0)
    $cpuColor = if ($cpuScore -gt 800000) { 'Green' } elseif ($cpuScore -gt 400000) { 'Yellow' } else { 'Red' }
    Write-Host "  CPU Score    : " -NoNewline; Write-Host "$cpuScore pts  ($cpuTime ms)" -ForegroundColor $cpuColor

    # RAM Benchmark
    Write-Host "  Ejecutando benchmark de RAM..." -ForegroundColor DarkGray
    $ramStart = Get-Date
    $arr      = New-Object int[] 5000000
    for ($i = 0; $i -lt $arr.Length; $i++) { $arr[$i] = $i }
    $ramTime  = [math]::Round(((Get-Date) - $ramStart).TotalMilliseconds, 0)
    $ramScore = [math]::Round(5000000 / ($ramTime / 1000), 0)
    $ramColor = if ($ramScore -gt 10000000) { 'Green' } elseif ($ramScore -gt 5000000) { 'Yellow' } else { 'Red' }
    Write-Host "  RAM Score    : " -NoNewline; Write-Host "$ramScore pts  ($ramTime ms)" -ForegroundColor $ramColor
    $arr = $null

    # Disk Benchmark
    Write-Host "  Ejecutando benchmark de disco..." -ForegroundColor DarkGray
    $testFile = "$env:TEMP\soportepro_bench.tmp"
    $data     = New-Object byte[] (50MB)
    (New-Object Random).NextBytes($data)

    $writeStart = Get-Date
    [System.IO.File]::WriteAllBytes($testFile, $data)
    $writeTime  = [math]::Round(((Get-Date) - $writeStart).TotalMilliseconds, 0)
    $writeMBps  = [math]::Round(50 / ($writeTime / 1000), 1)

    $readStart = Get-Date
    $null = [System.IO.File]::ReadAllBytes($testFile)
    $readTime  = [math]::Round(((Get-Date) - $readStart).TotalMilliseconds, 0)
    $readMBps  = [math]::Round(50 / ($readTime / 1000), 1)
    Remove-Item $testFile -Force -ErrorAction SilentlyContinue

    $diskWColor = if ($writeMBps -gt 200) { 'Green' } elseif ($writeMBps -gt 80) { 'Yellow' } else { 'Red' }
    $diskRColor = if ($readMBps  -gt 300) { 'Green' } elseif ($readMBps  -gt 100) { 'Yellow' } else { 'Red' }
    Write-Host "  Disco Escrit.: " -NoNewline; Write-Host "$writeMBps MB/s" -ForegroundColor $diskWColor
    Write-Host "  Disco Lectura: " -NoNewline; Write-Host "$readMBps MB/s"  -ForegroundColor $diskRColor

    Write-Host ""
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
    Write-Host "  RESUMEN" -ForegroundColor Cyan
    Write-Host "  CPU    : $cpuScore pts  - " -NoNewline
    Write-Host $(if ($cpuScore -gt 800000) { "Excelente" } elseif ($cpuScore -gt 400000) { "Bueno" } else { "Bajo" }) -ForegroundColor $cpuColor
    Write-Host "  Disco  : $readMBps MB/s lectura - " -NoNewline
    Write-Host $(if ($readMBps -gt 300) { "SSD rapido" } elseif ($readMBps -gt 100) { "SSD/HDD normal" } else { "HDD lento" }) -ForegroundColor $diskRColor
    Write-Host ""
    Write-Log "Benchmark ejecutado"
}
