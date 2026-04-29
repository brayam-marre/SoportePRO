function Invoke-Reporte {
    Show-Header
    Write-Section "GENERAR REPORTE DEL SISTEMA" "Green"

    Write-Host "  Recopilando informacion del sistema..." -ForegroundColor Yellow
    Write-Host ""

    $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $reportName = "SoportePRO_$env:COMPUTERNAME`_$timestamp"
    $desktop    = [Environment]::GetFolderPath('Desktop')
    $txtPath    = "$desktop\$reportName.txt"
    $htmlPath   = "$desktop\$reportName.html"

    # -- Recoleccion --------------------------------------------
    $os     = Get-CimInstance Win32_OperatingSystem
    $cs     = Get-CimInstance Win32_ComputerSystem
    $cpu    = Get-CimInstance Win32_Processor
    $bios   = Get-CimInstance Win32_BIOS
    $gpu    = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $uptime = (Get-Date) - $os.LastBootUpTime

    $totalRam   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRam    = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRam    = [math]::Round($totalRam - $freeRam, 2)
    $ramPercent = [math]::Round(($usedRam / $totalRam) * 100, 1)

    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used }

    $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10

    $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric | Select-Object -First 1).NextHop
    $dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses } | Select-Object -First 1).ServerAddresses
    $pingGoogle = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue

    $regPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installedProgs = $regPaths | ForEach-Object {
        Get-ItemProperty $_ -ErrorAction SilentlyContinue
    } | Where-Object { $_.DisplayName } | Sort-Object DisplayName -Unique

    $wdStatus  = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $fwStatus  = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $openPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Sort-Object LocalPort

    $localUsers = Get-LocalUser -ErrorAction SilentlyContinue
    $adminUsers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue

    # Hotfixes recientes
    $hotfixes = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5

    Write-Host "  [OK] Datos del sistema recopilados" -ForegroundColor Green
    Write-Host "  Analizando equipo..." -ForegroundColor DarkGray
    $analisis = Get-AnalisisEquipo
    Write-Host "  [OK] Analisis del equipo completado" -ForegroundColor Green
    Write-Host "  Generando reporte TXT..." -ForegroundColor DarkGray

    # -- Reporte TXT --------------------------------------------
    $drivesText = ($drives | ForEach-Object {
        $t = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
        $u = [math]::Round($_.Used / 1GB, 2)
        $p = if ($t -gt 0) { [math]::Round(($u / $t) * 100, 1) } else { 0 }
        "  Unidad $($_.Name):  $u GB / $t GB  ($p%)"
    }) -join "`n"

    $procsText = ($topProcs | ForEach-Object {
        $r = [math]::Round($_.WorkingSet64 / 1MB, 1)
        "  {0,-40} {1} MB" -f $_.Name, $r
    }) -join "`n"

    $avText = if ($wdStatus) {
        "  Activo: $($wdStatus.AntivirusEnabled)`n  Tiempo real: $($wdStatus.RealTimeProtectionEnabled)`n  Firmas: $($wdStatus.AntivirusSignatureVersion)"
    } else { "  No disponible" }

    $fwText = ($fwStatus | ForEach-Object { "  $($_.Name): $($_.Enabled)" }) -join "`n"

    $hotfixText = ($hotfixes | ForEach-Object { "  $($_.HotFixID) - $($_.InstalledOn.ToString('dd/MM/yyyy'))" }) -join "`n"

    $usersText = ($localUsers | ForEach-Object {
        $u       = $_
        $isAdmin = ($adminUsers | Where-Object { $_.Name -like "*$($u.Name)" }).Count -gt 0
        "  $($u.Name.PadRight(25)) Habilitado: $($u.Enabled)  Admin: $isAdmin"
    }) -join "`n"

    $portsText = ($openPorts | Select-Object -First 20 | ForEach-Object {
        "  Puerto $($_.LocalPort) - PID $($_.OwningProcess)"
    }) -join "`n"

    $progText = ($installedProgs | Select-Object -First 50 | ForEach-Object {
        "  $($_.DisplayName)"
    }) -join "`n"

    $report = @"
================================================================================
  SOPORTEPRO - REPORTE COMPLETO DEL SISTEMA
  Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
  Tecnico  : $env:USERNAME
  Equipo   : $env:COMPUTERNAME
================================================================================

SISTEMA OPERATIVO
  SO          : $($os.Caption) $($os.OSArchitecture)
  Version     : $($os.Version)  Build: $($os.BuildNumber)
  Fabricante  : $($cs.Manufacturer) $($cs.Model)
  Encendido   : $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm'))
  Tiempo activo: $([int]$uptime.TotalDays)d $($uptime.Hours)h $($uptime.Minutes)m
  BIOS        : $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate.ToString('dd/MM/yyyy')))

PROCESADOR
  CPU         : $($cpu.Name.Trim())
  Nucleos     : $($cpu.NumberOfCores) fisicos / $($cpu.NumberOfLogicalProcessors) logicos
  Velocidad   : $([math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz

MEMORIA RAM
  Total       : $totalRam GB
  En uso      : $usedRam GB ($ramPercent%)
  Libre       : $freeRam GB

TARJETA GRAFICA
  GPU         : $($gpu.Name)
  Driver      : $($gpu.DriverVersion)

ALMACENAMIENTO
$drivesText

RED
  Gateway     : $gateway
  DNS         : $($dns -join ', ')
  Internet    : $(if ($pingGoogle) {'Conectado'} else {'SIN CONEXION'})

SEGURIDAD - ANTIVIRUS
$avText

SEGURIDAD - FIREWALL
$fwText

ACTUALIZACIONES RECIENTES
$hotfixText

USUARIOS LOCALES
$usersText

PUERTOS EN ESCUCHA
$portsText

TOP 10 PROCESOS POR RAM
$procsText

PROGRAMAS INSTALADOS ($($installedProgs.Count) total)
$progText

================================================================================
  ANALISIS DEL EQUIPO - RECOMENDACIONES
================================================================================

PUNTUACION GENERAL: $($analisis.Score) / 100  -  $($analisis.Verdict)

PROCESADOR  [$($analisis.CPUStatus.PadRight(7))]  $($analisis.CPUName)
  $($analisis.CPUDetail)

MEMORIA RAM [$($analisis.RAMStatus.PadRight(7))]  $($analisis.RAMTotal) GB $($analisis.RAMType)
  $($analisis.RAMDetail)
  $($analisis.RAMSlotNote)

DISCO       [$($analisis.DiskStatus.PadRight(7))]  $($analisis.DiskType)
  $($analisis.DiskDetail)

WINDOWS     [$($analisis.WinStatus.PadRight(7))]  $($analisis.OSName)
  TPM 2.0: $(if($analisis.TPMOk){'Presente'}else{'No detectado'})   Secure Boot: $(if($analisis.SecureBoot){'Habilitado'}else{'Deshabilitado'})
  $($analisis.WinDetail)

$(if($analisis.Upgrades){"QUE PUEDES MEJORAR:`n" + ($analisis.Upgrades | ForEach-Object {"  -> $_"} | Out-String).TrimEnd()})

$(if($analisis.Warnings){"ADVERTENCIAS:`n" + ($analisis.Warnings | ForEach-Object {"  !! $_"} | Out-String).TrimEnd()})

SISTEMA OPERATIVO RECOMENDADO: $($analisis.OSRecMain)
  $($analisis.OSRecDetail)
$(if($analisis.OSRecAlts){($analisis.OSRecAlts | ForEach-Object {"  -> $_"} | Out-String).TrimEnd()})

================================================================================
  Reporte generado por SoportePRO v$script:Version
================================================================================
"@

    $report | Out-File -FilePath $txtPath -Encoding UTF8
    Write-Host "  [OK] Reporte TXT: $txtPath" -ForegroundColor Green

    # -- Reporte HTML -------------------------------------------
    Write-Host "  Generando reporte HTML..." -ForegroundColor DarkGray

    $diskRows = ($drives | ForEach-Object {
        $t = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
        $u = [math]::Round($_.Used / 1GB, 2)
        $p = if ($t -gt 0) { [math]::Round(($u / $t) * 100, 1) } else { 0 }
        $bc = if ($p -gt 90) { '#e74c3c' } elseif ($p -gt 75) { '#f39c12' } else { '#27ae60' }
        "<tr><td>$($_.Name):</td><td>$u / $t GB</td><td><div class='bbar'><div class='bfill' style='width:$p%;background:$bc'></div></div> $p%</td></tr>"
    }) -join ''

    $procRows = ($topProcs | ForEach-Object {
        $r = [math]::Round($_.WorkingSet64 / 1MB, 1)
        "<tr><td>$($_.Name)</td><td>$r MB</td><td>$($_.Id)</td></tr>"
    }) -join ''

    $fwRows = ($fwStatus | ForEach-Object {
        $fc = if ($_.Enabled) { 'ok' } else { 'err' }
        "<tr><td>$($_.Name)</td><td class='$fc'>$($_.Enabled)</td></tr>"
    }) -join ''

    $avOn  = if ($wdStatus -and $wdStatus.AntivirusEnabled) { 'ok' } else { 'err' }
    $avRT  = if ($wdStatus -and $wdStatus.RealTimeProtectionEnabled) { 'ok' } else { 'err' }
    $avSig = if ($wdStatus) { $wdStatus.AntivirusSignatureVersion } else { 'N/D' }
    $avUpd = if ($wdStatus) { $wdStatus.AntivirusSignatureLastUpdated.ToString('dd/MM/yyyy') } else { 'N/D' }

    $userRows = ($localUsers | ForEach-Object {
        $u = $_
        $ia = ($adminUsers | Where-Object { $_.Name -like "*$($u.Name)" }).Count -gt 0
        $uc = if ($u.Enabled) { 'ok' } else { 'dim' }
        $ac = if ($ia) { 'warn' } else { '' }
        "<tr><td>$($u.Name)</td><td class='$uc'>$($u.Enabled)</td><td class='$ac'>$ia</td></tr>"
    }) -join ''

    $portRows = ($openPorts | Select-Object -First 20 | ForEach-Object {
        $pName = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name
        "<tr><td>$($_.LocalPort)</td><td>$($_.LocalAddress)</td><td>$pName</td><td>$($_.OwningProcess)</td></tr>"
    }) -join ''

    $hfRows = ($hotfixes | ForEach-Object {
        "<tr><td>$($_.HotFixID)</td><td>$($_.Description)</td><td>$($_.InstalledOn.ToString('dd/MM/yyyy'))</td></tr>"
    }) -join ''

    $internet = if ($pingGoogle) { "<span class='ok'>Conectado</span>" } else { "<span class='err'>SIN CONEXION</span>" }
    $uptimeStr = "$([int]$uptime.TotalDays)d $($uptime.Hours)h $($uptime.Minutes)m"
    $ramColor  = if ($ramPercent -gt 85) { 'err' } elseif ($ramPercent -gt 65) { 'warn' } else { 'ok' }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SoportePRO - Reporte $env:COMPUTERNAME</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;padding:24px}
h1{color:#58a6ff;font-size:1.8em;margin-bottom:4px}
.sub{color:#8b949e;font-size:.85em;margin-bottom:24px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}
.card{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:18px}
.card h2{color:#58a6ff;font-size:.95em;border-bottom:1px solid #21262d;padding-bottom:8px;margin-bottom:12px}
table{width:100%;border-collapse:collapse}
td{padding:4px 8px;font-size:.84em;vertical-align:middle}
td:first-child{color:#8b949e;width:42%}
.ok{color:#3fb950}.warn{color:#d29922}.err{color:#f85149}.dim{color:#484f58}
.bbar{display:inline-block;width:70px;height:7px;background:#21262d;border-radius:4px;vertical-align:middle;margin-right:5px}
.bfill{height:7px;border-radius:4px}
.footer{margin-top:24px;text-align:center;color:#484f58;font-size:.78em}
.tag{background:#21262d;border-radius:4px;padding:2px 8px;font-size:.78em;margin-right:4px}
</style>
</head>
<body>
<h1>SoportePRO</h1>
<p class="sub">
  <span class="tag">$(Get-Date -Format 'dd/MM/yyyy HH:mm')</span>
  <span class="tag">Equipo: <strong>$env:COMPUTERNAME</strong></span>
  <span class="tag">Tecnico: <strong>$env:USERNAME</strong></span>
</p>

<div class="grid">

  <div class="card">
    <h2>Sistema Operativo</h2>
    <table>
      <tr><td>SO</td><td>$($os.Caption)</td></tr>
      <tr><td>Arquitectura</td><td>$($os.OSArchitecture)</td></tr>
      <tr><td>Version / Build</td><td>$($os.Version) / $($os.BuildNumber)</td></tr>
      <tr><td>Fabricante</td><td>$($cs.Manufacturer) $($cs.Model)</td></tr>
      <tr><td>Tiempo activo</td><td>$uptimeStr</td></tr>
      <tr><td>Ultimo reinicio</td><td>$($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm'))</td></tr>
      <tr><td>BIOS</td><td>$($bios.SMBIOSBIOSVersion)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Procesador y Memoria</h2>
    <table>
      <tr><td>CPU</td><td>$($cpu.Name.Trim())</td></tr>
      <tr><td>Nucleos</td><td>$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors) logicos</td></tr>
      <tr><td>Velocidad</td><td>$([math]::Round($cpu.MaxClockSpeed/1000,2)) GHz</td></tr>
      <tr><td>RAM Total</td><td>$totalRam GB</td></tr>
      <tr><td>RAM Usada</td><td class="$ramColor">$usedRam GB ($ramPercent%)</td></tr>
      <tr><td>RAM Libre</td><td>$freeRam GB</td></tr>
      <tr><td>GPU</td><td>$($gpu.Name)</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Almacenamiento</h2>
    <table>$diskRows</table>
  </div>

  <div class="card">
    <h2>Red</h2>
    <table>
      <tr><td>Gateway</td><td>$gateway</td></tr>
      <tr><td>DNS</td><td>$($dns -join ', ')</td></tr>
      <tr><td>Internet</td><td>$internet</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Antivirus (Windows Defender)</h2>
    <table>
      <tr><td>Activo</td><td class="$avOn">$(if($wdStatus){$wdStatus.AntivirusEnabled}else{'N/D'})</td></tr>
      <tr><td>Tiempo real</td><td class="$avRT">$(if($wdStatus){$wdStatus.RealTimeProtectionEnabled}else{'N/D'})</td></tr>
      <tr><td>Version firmas</td><td>$avSig</td></tr>
      <tr><td>Ultima actualizacion</td><td>$avUpd</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Firewall</h2>
    <table>$fwRows</table>
  </div>

  <div class="card">
    <h2>Actualizaciones recientes</h2>
    <table>
      <tr><td>ID</td><td>Descripcion</td><td>Fecha</td></tr>
      $hfRows
    </table>
  </div>

  <div class="card">
    <h2>Usuarios locales</h2>
    <table>
      <tr><td>Usuario</td><td>Activo</td><td>Admin</td></tr>
      $userRows
    </table>
  </div>

  <div class="card">
    <h2>Top 10 Procesos (RAM)</h2>
    <table>
      <tr><td>Proceso</td><td>RAM</td><td>PID</td></tr>
      $procRows
    </table>
  </div>

  <div class="card">
    <h2>Puertos en escucha</h2>
    <table>
      <tr><td>Puerto</td><td>Direccion</td><td>Proceso</td><td>PID</td></tr>
      $portRows
    </table>
  </div>

  <div class="card">
    <h2>Software instalado ($($installedProgs.Count) programas)</h2>
    <table>
      $(($installedProgs | Select-Object -First 15 | ForEach-Object {
          "<tr><td colspan='2'>$($_.DisplayName)</td></tr>"
      }) -join '')
      $(if($installedProgs.Count -gt 15){"<tr><td colspan='2' style='color:#484f58'>... y $($installedProgs.Count - 15) mas en el reporte TXT</td></tr>"})
    </table>
  </div>

</div>

<div style="margin-top:20px;background:#161b22;border:1px solid #30363d;border-radius:10px;padding:20px">
  <h2 style="color:#58a6ff;font-size:1em;border-bottom:1px solid #21262d;padding-bottom:8px;margin-bottom:16px">Analisis del Equipo - Recomendaciones</h2>

  <div style="display:flex;align-items:center;gap:16px;margin-bottom:18px">
    <div style="font-size:2em;font-weight:bold;color:$(if($analisis.Score -ge 80){'#3fb950'}elseif($analisis.Score -ge 60){'#d29922'}else{'#f85149'})">$($analisis.Score)<span style="font-size:.5em;color:#8b949e">/100</span></div>
    <div>
      <div style="font-weight:bold;color:$(if($analisis.Score -ge 80){'#3fb950'}elseif($analisis.Score -ge 60){'#d29922'}else{'#f85149'})">$($analisis.Verdict)</div>
      <div style="font-size:.8em;color:#8b949e;margin-top:2px">$($analisis.OSName)</div>
    </div>
  </div>

  <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px;margin-bottom:16px">
$(
    @(
      @{ Label='Procesador'; Val=$analisis.CPUName;   Status=$analisis.CPUStatus;  Detail=$analisis.CPUDetail  }
      @{ Label='RAM';        Val="$($analisis.RAMTotal) GB $($analisis.RAMType)"; Status=$analisis.RAMStatus; Detail=$analisis.RAMDetail }
      @{ Label='Disco';      Val=$analisis.DiskType;  Status=$analisis.DiskStatus; Detail=$analisis.DiskDetail }
      @{ Label='Windows';    Val=$analisis.OSName;    Status=$analisis.WinStatus;  Detail=$analisis.WinDetail  }
    ) | ForEach-Object {
        $sc = if($_.Status -eq 'BIEN'){'#3fb950'}elseif($_.Status -eq 'REGULAR'){'#d29922'}else{'#f85149'}
        "    <div style='background:#0d1117;border:1px solid #21262d;border-radius:8px;padding:12px'>
      <div style='font-size:.75em;color:#8b949e'>$($_.Label)</div>
      <div style='font-size:.82em;color:#c9d1d9;margin:3px 0'>$($_.Val)</div>
      <div style='font-size:.78em;font-weight:bold;color:$sc'>$($_.Status)</div>
      <div style='font-size:.75em;color:#8b949e;margin-top:2px'>$($_.Detail)</div>
    </div>"
    }
)
  </div>

$(
    $tpmC = if($analisis.TPMOk){'#3fb950'}else{'#f85149'}
    $sbC  = if($analisis.SecureBoot){'#3fb950'}else{'#d29922'}
    "  <div style='font-size:.82em;color:#8b949e;margin-bottom:14px'>
    TPM 2.0: <span style='color:$tpmC'>$(if($analisis.TPMOk){'Presente'}else{'No detectado'})</span>
    &nbsp;&nbsp; Secure Boot: <span style='color:$sbC'>$(if($analisis.SecureBoot){'Habilitado'}else{'Deshabilitado'})</span>
  </div>"
)

$(if($analisis.Upgrades -or $analisis.Warnings){
    $items = ""
    $analisis.Upgrades | ForEach-Object { $items += "<li style='margin-bottom:5px;color:#c9d1d9'>$_</li>" }
    $analisis.Warnings | ForEach-Object { $items += "<li style='margin-bottom:5px;color:#f85149'>!! $_</li>" }
    "  <div style='margin-bottom:14px'>
    <div style='font-size:.82em;font-weight:bold;color:#d29922;margin-bottom:6px'>Recomendaciones:</div>
    <ul style='font-size:.8em;padding-left:18px;margin:0'>$items</ul>
  </div>"
})

  <div style="background:#0d1117;border:1px solid #21262d;border-radius:8px;padding:12px">
    <div style="font-size:.75em;color:#8b949e;margin-bottom:4px">Sistema Operativo Recomendado</div>
    <div style="font-size:.88em;color:#58a6ff;font-weight:bold">$($analisis.OSRecMain)</div>
    <div style="font-size:.8em;color:#8b949e;margin-top:4px">$($analisis.OSRecDetail)</div>
    $(if($analisis.OSRecAlts){
        $alts = ($analisis.OSRecAlts | ForEach-Object { "<li style='margin-top:3px'>$_</li>" }) -join ''
        "<ul style='font-size:.78em;color:#8b949e;padding-left:16px;margin-top:6px'>$alts</ul>"
    })
  </div>
</div>

<div class="footer">SoportePRO v$script:Version &nbsp;|&nbsp; Reporte generado el $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlPath -Encoding UTF8
    Write-Host "  [OK] Reporte HTML: $htmlPath" -ForegroundColor Green
    Write-Host ""

    $open = Read-Host "  Abrir reporte HTML en el navegador? (s/n)"
    if ($open -ieq 's') { Start-Process $htmlPath }

    Write-Log "Reporte generado: $reportName"
}
