function Invoke-Red {
    Show-Header
    Write-Section "REDES Y CONECTIVIDAD"

    Write-Host "  [1]   Informacion de adaptadores e IPs"
    Write-Host "  [2]   Prueba de conectividad (Ping + Traceroute)"
    Write-Host "  [3]   Puertos abiertos y conexiones activas"
    Write-Host "  [4]   Diagnostico WiFi"
    Write-Host "  [5]   Herramientas de red (DNS, WHOIS, NSLookup)"
    Write-Host "  [6]   Ver todo el diagnostico de red"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Show-NetworkAdapters }
        '2' { Invoke-ConnectivityTest }
        '3' { Show-OpenPorts }
        '4' { Show-WiFiInfo }
        '5' { Invoke-NetworkTools }
        '6' {
            Show-NetworkAdapters
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Invoke-ConnectivityTest
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-OpenPorts
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-WiFiInfo
        }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Log "Red - opcion: $sub"
}

function Show-NetworkAdapters {
    Write-Host ""
    Write-Host "  ADAPTADORES DE RED" -ForegroundColor Yellow
    Write-Host "  {0,-25} {1,-18} {2,-18} {3}" -f "Adaptador", "IPv4", "MAC", "Estado"
    Write-Host "  $('-' * 80)"

    Get-NetAdapter | ForEach-Object {
        $adapter = $_
        $ip4 = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
        $stColor = if ($adapter.Status -eq 'Up') { 'Green' } else { 'DarkGray' }
        $name = if ($adapter.Name.Length -gt 23) { $adapter.Name.Substring(0,23) + ".." } else { $adapter.Name }
        Write-Host ("  {0,-25} {1,-18} {2,-18} " -f $name, $ip4, $adapter.MacAddress) -NoNewline
        Write-Host $adapter.Status -ForegroundColor $stColor
    }
    Write-Host ""

    # Gateway y DNS
    Write-Host "  CONFIGURACION IP" -ForegroundColor Yellow
    $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric | Select-Object -First 1).NextHop
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.ServerAddresses }
    Write-Host "  Gateway predeterminado : $gateway"
    $dnsServers | ForEach-Object {
        Write-Host "  DNS ($($_.InterfaceAlias)): $($_.ServerAddresses -join ', ')"
    }

    # IP publica
    Write-Host ""
    Write-Host "  Obteniendo IP publica..." -ForegroundColor DarkGray
    try {
        $publicIp = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        Write-Host "  IP publica            : $publicIp" -ForegroundColor Cyan
    } catch {
        Write-Host "  IP publica            : No disponible (sin internet)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Invoke-ConnectivityTest {
    Write-Host ""
    Write-Host "  PRUEBA DE CONECTIVIDAD" -ForegroundColor Yellow
    Write-Host ""

    $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric | Select-Object -First 1).NextHop

    $targets = @(
        @{ Host = $gateway;          Label = "Gateway local      " },
        @{ Host = "8.8.8.8";         Label = "Google DNS (8.8.8.8)" },
        @{ Host = "1.1.1.1";         Label = "Cloudflare (1.1.1.1)" },
        @{ Host = "google.com";      Label = "Google (google.com)" },
        @{ Host = "microsoft.com";   Label = "Microsoft          " },
        @{ Host = "cloudflare.com";  Label = "Cloudflare DNS     " }
    )

    foreach ($t in $targets) {
        if (-not $t.Host) { continue }
        $ping = Test-Connection -ComputerName $t.Host -Count 3 -ErrorAction SilentlyContinue
        if ($ping) {
            $avg  = [math]::Round(($ping | Measure-Object -Property ResponseTime -Average).Average, 0)
            $min  = ($ping | Measure-Object -Property ResponseTime -Minimum).Minimum
            $max  = ($ping | Measure-Object -Property ResponseTime -Maximum).Maximum
            $latColor = if ($avg -gt 150) { 'Red' } elseif ($avg -gt 60) { 'Yellow' } else { 'Green' }
            Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline
            Write-Host "$($t.Label) " -NoNewline
            Write-Host "avg:$avg ms  min:$min  max:$max" -ForegroundColor $latColor
        } else {
            Write-Host "  [ FAIL ] " -ForegroundColor Red -NoNewline
            Write-Host "$($t.Label) SIN RESPUESTA" -ForegroundColor Red
        }
    }

    # Traceroute
    Write-Host ""
    $doTrace = Read-Host "  Ejecutar traceroute a google.com? (s/n)"
    if ($doTrace -ieq 's') {
        Write-Host ""
        Write-Host "  TRACEROUTE a google.com" -ForegroundColor Yellow
        $trace = tracert -d -h 15 google.com 2>&1
        $trace | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ""
}

function Show-OpenPorts {
    Write-Host ""
    Write-Host "  PUERTOS EN ESCUCHA (TCP)" -ForegroundColor Yellow
    Write-Host "  {0,-10} {1,-25} {2,-20} {3}" -f "Puerto", "Proceso", "PID", "Direccion"
    Write-Host "  $('-' * 70)"

    $connections = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                   Sort-Object LocalPort | Select-Object -First 30

    $connections | ForEach-Object {
        $conn = $_
        try {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $pName = if ($proc) { $proc.Name } else { "Sistema" }
        } catch { $pName = "N/D" }
        Write-Host ("  {0,-10} {1,-25} {2,-20} {3}" -f $conn.LocalPort, $pName, $conn.OwningProcess, $conn.LocalAddress)
    }

    Write-Host ""
    Write-Host "  CONEXIONES ESTABLECIDAS" -ForegroundColor Yellow
    Write-Host "  {0,-22} {1,-22} {2,-15} {3}" -f "Local", "Remoto", "Proceso", "PID"
    Write-Host "  $('-' * 70)"

    $estab = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
             Sort-Object RemotePort | Select-Object -First 20

    $estab | ForEach-Object {
        $conn = $_
        try {
            $proc  = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            $pName = if ($proc) { $proc.Name } else { "Sistema" }
        } catch { $pName = "N/D" }
        Write-Host ("  {0,-22} {1,-22} {2,-15} {3}" -f "$($conn.LocalAddress):$($conn.LocalPort)", "$($conn.RemoteAddress):$($conn.RemotePort)", $pName, $conn.OwningProcess)
    }
    Write-Host ""
}

function Show-WiFiInfo {
    Write-Host ""
    Write-Host "  DIAGNOSTICO WIFI" -ForegroundColor Yellow

    $wifiInfo = netsh wlan show interfaces 2>$null
    if ($wifiInfo -match 'SSID\s+:\s+(.+)') {
        $ssid = $Matches[1].Trim()
        Write-Host "  SSID conectado     : $ssid"

        if ($wifiInfo -match 'Signal\s+:\s+(.+)') {
            $signal   = $Matches[1].Trim()
            $sigVal   = [int]($signal -replace '[^0-9]', '')
            $sigColor = if ($sigVal -gt 70) { 'Green' } elseif ($sigVal -gt 40) { 'Yellow' } else { 'Red' }
            Write-Host "  Intensidad de senal: " -NoNewline; Write-Host $signal -ForegroundColor $sigColor
        }
        if ($wifiInfo -match 'Radio type\s+:\s+(.+)') { Write-Host "  Tipo de radio      : $($Matches[1].Trim())" }
        if ($wifiInfo -match 'Authentication\s+:\s+(.+)') { Write-Host "  Autenticacion      : $($Matches[1].Trim())" }
        if ($wifiInfo -match 'Cipher\s+:\s+(.+)') { Write-Host "  Cifrado            : $($Matches[1].Trim())" }
        if ($wifiInfo -match 'Receive rate.*?:\s+(.+)') { Write-Host "  Velocidad recep.   : $($Matches[1].Trim())" }
        if ($wifiInfo -match 'Transmit rate.*?:\s+(.+)') { Write-Host "  Velocidad transm.  : $($Matches[1].Trim())" }
        if ($wifiInfo -match 'BSSID\s+:\s+(.+)') { Write-Host "  BSSID (AP MAC)     : $($Matches[1].Trim())" }
    } else {
        Write-Host "  No hay conexion WiFi activa." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  REDES WIFI GUARDADAS" -ForegroundColor Yellow
    $profiles = netsh wlan show profiles 2>$null | Select-String "All User Profile" | ForEach-Object {
        ($_ -split ':')[1].Trim()
    }
    if ($profiles) {
        Write-Host "  Total de perfiles: $($profiles.Count)"
        $profiles | Select-Object -First 15 | ForEach-Object { Write-Host "  · $_" }
        if ($profiles.Count -gt 15) { Write-Host "  ... y $($profiles.Count - 15) mas" -ForegroundColor DarkGray }
    } else {
        Write-Host "  No se encontraron perfiles WiFi guardados." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Invoke-NetworkTools {
    Write-Host ""
    Write-Host "  HERRAMIENTAS DE RED" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1]  NSLookup (resolver dominio)"
    Write-Host "  [2]  Ping personalizado"
    Write-Host "  [3]  Test de velocidad basico (latencia a CDNs)"
    Write-Host "  [4]  Ver tabla ARP"
    Write-Host "  [5]  Ver tabla de rutas"
    Write-Host ""

    $t = Read-Host "  Opcion"
    switch ($t) {
        '1' {
            $domain = Read-Host "  Dominio a resolver"
            if ($domain) { nslookup $domain 2>&1 | ForEach-Object { Write-Host "  $_" } }
        }
        '2' {
            $host2 = Read-Host "  Host o IP a hacer ping"
            $count = Read-Host "  Cantidad de pings (Enter = 10)"
            if (-not $count) { $count = 10 }
            if ($host2) { ping -n $count $host2 2>&1 | ForEach-Object { Write-Host "  $_" } }
        }
        '3' {
            Write-Host ""
            Write-Host "  Midiendo latencia a CDNs globales..." -ForegroundColor DarkGray
            @("1.1.1.1","8.8.8.8","208.67.222.222","9.9.9.9") | ForEach-Object {
                $p = Test-Connection -ComputerName $_ -Count 5 -ErrorAction SilentlyContinue
                if ($p) {
                    $avg = [math]::Round(($p | Measure-Object -Property ResponseTime -Average).Average, 1)
                    Write-Host "  $_ -> $avg ms avg"
                }
            }
        }
        '4' { arp -a 2>&1 | ForEach-Object { Write-Host "  $_" } }
        '5' { route print 2>&1 | ForEach-Object { Write-Host "  $_" } }
    }
    Write-Host ""
}
