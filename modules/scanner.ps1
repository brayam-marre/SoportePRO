function Invoke-Scanner {
    Show-Header
    Write-Section "ESCANER DE RED Y TRAFICO"

    Write-Host "  [1]   Escaner de red LAN (dispositivos conectados)"
    Write-Host "  [2]   Trafico de red por proceso (tiempo real)"
    Write-Host "  [3]   Verificador de hashes de archivos"
    Write-Host "  [4]   Baseline de seguridad (CIS basico)"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Invoke-LANScanner }
        '2' { Show-NetworkTraffic }
        '3' { Invoke-HashChecker }
        '4' { Invoke-SecurityBaseline }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }
    Write-Log "Scanner - opcion: $sub"
}

# ── Escaner LAN ───────────────────────────────────────────────
function Invoke-LANScanner {
    Write-Host ""
    Write-Host "  ESCANER DE RED LOCAL (LAN)" -ForegroundColor Yellow
    Write-Host ""

    # Obtener IP y subnet locales
    $localAdapter = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -notmatch '^(127|169)' -and $_.PrefixOrigin -ne 'WellKnown' } |
                    Select-Object -First 1

    if (-not $localAdapter) {
        Write-Host "  No se pudo obtener la IP local." -ForegroundColor Red
        return
    }

    $localIP   = $localAdapter.IPAddress
    $prefix    = $localAdapter.PrefixLength
    $subnet    = $localIP -replace '\.\d+$', ''
    $rangeEnd  = [math]::Pow(2, 32 - $prefix) - 2
    $scanRange = [math]::Min($rangeEnd, 254)

    Write-Host "  IP local    : $localIP / $prefix" -ForegroundColor Cyan
    Write-Host "  Subnet      : $subnet.0/$prefix"
    Write-Host "  Escaneando  : $subnet.1 - $subnet.$scanRange"
    Write-Host "  Esto puede tardar 1-2 minutos..." -ForegroundColor DarkGray
    Write-Host ""

    # Ping sweep en paralelo
    $pingJobs = 1..$scanRange | ForEach-Object {
        $ip = "$subnet.$_"
        Start-Job -ScriptBlock {
            param($ip)
            $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
            if ($ping) { $ip }
        } -ArgumentList $ip
    }

    Write-Host "  Escaneando..." -ForegroundColor DarkGray
    $activeIPs = $pingJobs | Wait-Job | Receive-Job | Where-Object { $_ }
    $pingJobs | Remove-Job -Force

    if ($activeIPs) {
        # Obtener tabla ARP para MAC addresses
        $arpTable = arp -a 2>$null

        Write-Host "  DISPOSITIVOS ENCONTRADOS: $($activeIPs.Count)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  {0,-18} {1,-20} {2,-20} {3}" -f "IP", "MAC", "Hostname", "Tipo"
        Write-Host "  $('-' * 75)"

        $activeIPs | Sort-Object { [Version]$_ } | ForEach-Object {
            $ip = $_
            # Buscar MAC en tabla ARP
            $arpLine = $arpTable | Select-String $ip
            $mac = if ($arpLine -match '([0-9a-f]{2}[-:][0-9a-f]{2}[-:][0-9a-f]{2}[-:][0-9a-f]{2}[-:][0-9a-f]{2}[-:][0-9a-f]{2})') {
                $Matches[1]
            } else { "N/D" }

            # Resolver hostname
            $hostname = try {
                ([System.Net.Dns]::GetHostEntry($ip)).HostName
            } catch { "Sin nombre" }
            if ($hostname.Length -gt 18) { $hostname = $hostname.Substring(0,18) + ".." }

            # Identificar tipo por MAC OUI (primeros 3 octetos)
            $tipo = if ($ip -eq $localIP) { "Este equipo" }
                    elseif ($mac -match '^(00:50:56|00:0c:29|00:05:69)') { "VMware" }
                    elseif ($ip -eq (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop) { "Gateway/Router" }
                    else { "Dispositivo" }

            $color = if ($tipo -eq "Este equipo") { 'Cyan' } elseif ($tipo -eq "Gateway/Router") { 'Yellow' } else { 'White' }
            Write-Host ("  {0,-18} {1,-20} {2,-20} {3}" -f $ip, $mac, $hostname, $tipo) -ForegroundColor $color
        }
        Write-Host ""

        # Preguntar si hacer port scan a una IP especifica
        Write-Host "  Hacer escaneo de puertos a una IP? (Enter para omitir)" -ForegroundColor DarkGray
        $scanIP = Read-Host "  IP"
        if ($scanIP) {
            Write-Host ""
            Write-Host "  Escaneando puertos comunes en $scanIP..." -ForegroundColor DarkGray
            $commonPorts = @(21,22,23,25,53,80,110,135,139,143,443,445,3389,8080,8443)
            $openPorts   = @()
            $commonPorts | ForEach-Object {
                $port = $_
                $tcp  = New-Object System.Net.Sockets.TcpClient
                try {
                    $conn = $tcp.BeginConnect($scanIP, $port, $null, $null)
                    $wait = $conn.AsyncWaitHandle.WaitOne(300, $false)
                    if ($wait -and -not $tcp.Client.Connected -eq $false) {
                        $tcp.EndConnect($conn)
                        $openPorts += $port
                    }
                } catch {} finally { $tcp.Close() }
            }
            if ($openPorts) {
                $portNames = @{21='FTP';22='SSH';23='Telnet';25='SMTP';53='DNS';80='HTTP';
                               110='POP3';135='RPC';139='NetBIOS';143='IMAP';443='HTTPS';
                               445='SMB';3389='RDP';8080='HTTP-Alt';8443='HTTPS-Alt'}
                Write-Host "  Puertos abiertos en $scanIP :" -ForegroundColor Yellow
                $openPorts | ForEach-Object {
                    $name = $portNames[$_]
                    Write-Host "    $_ ($name)" -ForegroundColor Cyan
                }
            } else {
                Write-Host "  No se encontraron puertos comunes abiertos." -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "  No se encontraron dispositivos activos." -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Log "LAN Scanner ejecutado - $($activeIPs.Count) dispositivos"
}

# ── Trafico de red por proceso ────────────────────────────────
function Show-NetworkTraffic {
    Write-Host ""
    Write-Host "  TRAFICO DE RED POR PROCESO" -ForegroundColor Yellow
    Write-Host "  (Conexiones activas con datos de transferencia)" -ForegroundColor DarkGray
    Write-Host ""

    # Obtener contadores de red
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $stats1   = $adapters | Get-NetAdapterStatistics -ErrorAction SilentlyContinue

    Write-Host "  Midiendo trafico durante 3 segundos..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 3
    $stats2 = $adapters | Get-NetAdapterStatistics -ErrorAction SilentlyContinue

    Write-Host ""
    Write-Host "  VELOCIDAD DE RED ACTUAL" -ForegroundColor Yellow
    for ($i = 0; $i -lt $adapters.Count; $i++) {
        $rx = if ($stats2[$i] -and $stats1[$i]) {
            [math]::Round(($stats2[$i].ReceivedBytes - $stats1[$i].ReceivedBytes) / 3 / 1KB, 1)
        } else { 0 }
        $tx = if ($stats2[$i] -and $stats1[$i]) {
            [math]::Round(($stats2[$i].SentBytes - $stats1[$i].SentBytes) / 3 / 1KB, 1)
        } else { 0 }
        Write-Host "  $($adapters[$i].Name):"
        Write-Host "    Descarga : " -NoNewline; Write-Host "$rx KB/s" -ForegroundColor Green
        Write-Host "    Subida   : " -NoNewline; Write-Host "$tx KB/s" -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  PROCESOS CON CONEXIONES ACTIVAS" -ForegroundColor Yellow
    Write-Host "  {0,-25} {1,-22} {2,-22} {3}" -f "Proceso", "IP Local", "IP Remota", "PID"
    Write-Host "  $('-' * 80)"

    $conns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
             Where-Object { $_.RemoteAddress -notmatch '^(127|::1)' } |
             Sort-Object OwningProcess -Unique

    $conns | Select-Object -First 20 | ForEach-Object {
        $c    = $_
        $proc = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.Name } else { "Sistema" }
        Write-Host ("  {0,-25} {1,-22} {2,-22} {3}" -f $name, "$($c.LocalAddress):$($c.LocalPort)", "$($c.RemoteAddress):$($c.RemotePort)", $c.OwningProcess)
    }
    Write-Host ""
    Write-Log "Trafico de red analizado"
}

# ── Verificador de hashes ─────────────────────────────────────
function Invoke-HashChecker {
    Write-Host ""
    Write-Host "  VERIFICADOR DE HASHES DE ARCHIVOS" -ForegroundColor Yellow
    Write-Host "  (Verifica integridad de archivos con MD5, SHA1 y SHA256)" -ForegroundColor DarkGray
    Write-Host ""

    $filePath = Read-Host "  Ruta del archivo (o arrastra el archivo aqui)"
    $filePath = $filePath.Trim('"')

    if (-not (Test-Path $filePath)) {
        Write-Host "  Archivo no encontrado: $filePath" -ForegroundColor Red
        return
    }

    $fileInfo = Get-Item $filePath
    Write-Host ""
    Write-Host "  Archivo  : $($fileInfo.Name)"
    Write-Host "  Tamano   : $([math]::Round($fileInfo.Length / 1KB, 2)) KB  ($([math]::Round($fileInfo.Length / 1MB, 2)) MB)"
    Write-Host "  Fecha    : $($fileInfo.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))"
    Write-Host ""
    Write-Host "  Calculando hashes..." -ForegroundColor DarkGray

    $md5    = (Get-FileHash $filePath -Algorithm MD5    -ErrorAction SilentlyContinue).Hash
    $sha1   = (Get-FileHash $filePath -Algorithm SHA1   -ErrorAction SilentlyContinue).Hash
    $sha256 = (Get-FileHash $filePath -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash

    Write-Host ""
    Write-Host "  MD5    : " -NoNewline; Write-Host $md5    -ForegroundColor Cyan
    Write-Host "  SHA1   : " -NoNewline; Write-Host $sha1   -ForegroundColor Cyan
    Write-Host "  SHA256 : " -NoNewline; Write-Host $sha256 -ForegroundColor Cyan
    Write-Host ""

    # Comparar con hash conocido
    $known = Read-Host "  Pega un hash para comparar (Enter para omitir)"
    if ($known) {
        $known = $known.Trim().ToUpper()
        $match = ($md5 -eq $known) -or ($sha1 -eq $known) -or ($sha256 -eq $known)
        if ($match) {
            Write-Host "  RESULTADO: " -NoNewline; Write-Host "HASH COINCIDE - Archivo integro" -ForegroundColor Green
        } else {
            Write-Host "  RESULTADO: " -NoNewline; Write-Host "HASH NO COINCIDE - Archivo posiblemente alterado" -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Log "Hash verificado: $($fileInfo.Name)"
}

# ── Baseline de seguridad ─────────────────────────────────────
function Invoke-SecurityBaseline {
    Write-Host ""
    Write-Host "  BASELINE DE SEGURIDAD (CIS Benchmark basico)" -ForegroundColor Yellow
    Write-Host ""

    $score = 0
    $total = 0

    function Check-Item {
        param([string]$Label, [bool]$Pass, [string]$Fix = "")
        $script:total++
        if ($Pass) {
            $script:score++
            Write-Host "  [PASS] " -ForegroundColor Green -NoNewline
        } else {
            Write-Host "  [FAIL] " -ForegroundColor Red -NoNewline
        }
        Write-Host $Label
        if (-not $Pass -and $Fix) {
            Write-Host "         -> $Fix" -ForegroundColor DarkGray
        }
    }

    Write-Host "  CUENTAS Y AUTENTICACION" -ForegroundColor Yellow
    $adminBuiltin = Get-LocalUser -Name "Administrator" -ErrorAction SilentlyContinue
    Check-Item "Cuenta Administrador integrada deshabilitada" ($adminBuiltin -and -not $adminBuiltin.Enabled) "Deshabilita la cuenta 'Administrator' integrada"
    $guestAcc = Get-LocalUser -Name "Guest" -ErrorAction SilentlyContinue
    Check-Item "Cuenta Invitado deshabilitada" ($guestAcc -and -not $guestAcc.Enabled) "Deshabilita la cuenta 'Guest'"
    $uac = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue).EnableLUA
    Check-Item "UAC habilitado" ($uac -eq 1) "Habilita UAC en Panel de Control > Cuentas de usuario"
    $passPolicy = net accounts 2>$null
    $minPass = ($passPolicy | Select-String "Minimum password length" | ForEach-Object { ($_ -split ':')[1].Trim() })
    Check-Item "Longitud minima de contrasena >= 8" ([int]$minPass -ge 8) "Configura longitud minima de 8 en 'secpol.msc'"

    Write-Host ""
    Write-Host "  ACTUALIZACIONES Y PARCHES" -ForegroundColor Yellow
    $lastPatch = (Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
    $patchDays = if ($lastPatch) { ((Get-Date) - $lastPatch).Days } else { 999 }
    Check-Item "Sistema actualizado (ultimo parche < 30 dias)" ($patchDays -lt 30) "Ejecuta Windows Update"
    $wuService = (Get-Service wuauserv -ErrorAction SilentlyContinue).Status
    Check-Item "Servicio Windows Update activo" ($wuService -eq 'Running') "Inicia el servicio 'wuauserv'"

    Write-Host ""
    Write-Host "  FIREWALL Y RED" -ForegroundColor Yellow
    $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $domainFW  = ($fw | Where-Object { $_.Name -eq 'Domain' }).Enabled
    $privateFW = ($fw | Where-Object { $_.Name -eq 'Private' }).Enabled
    $publicFW  = ($fw | Where-Object { $_.Name -eq 'Public' }).Enabled
    Check-Item "Firewall activo (perfil Dominio)" $domainFW   "Activa el Firewall de Windows"
    Check-Item "Firewall activo (perfil Privado)" $privateFW  "Activa el Firewall de Windows"
    Check-Item "Firewall activo (perfil Publico)" $publicFW   "Activa el Firewall de Windows"
    $smb1 = (Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue).State
    Check-Item "SMBv1 deshabilitado (EternalBlue)" ($smb1 -ne 'Enabled') "Deshabilita SMBv1 en 'Caracteristicas de Windows'"
    $rdp = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -ErrorAction SilentlyContinue).fDenyTSConnections
    Check-Item "RDP deshabilitado (si no se usa)" ($rdp -eq 1) "Deshabilita RDP si no lo necesitas"

    Write-Host ""
    Write-Host "  ANTIVIRUS Y PROTECCION" -ForegroundColor Yellow
    $wd = Get-MpComputerStatus -ErrorAction SilentlyContinue
    Check-Item "Windows Defender activo" ($wd -and $wd.AntivirusEnabled) "Activa Windows Defender"
    Check-Item "Proteccion en tiempo real activa" ($wd -and $wd.RealTimeProtectionEnabled) "Activa la proteccion en tiempo real"
    $sigAge = if ($wd) { ((Get-Date) - $wd.AntivirusSignatureLastUpdated).Days } else { 999 }
    Check-Item "Firmas antivirus actualizadas (< 3 dias)" ($sigAge -lt 3) "Actualiza Windows Defender"
    Check-Item "Proteccion contra Tamper activa" ($wd -and $wd.IsTamperProtected) "Activa Tamper Protection en Seguridad de Windows"

    Write-Host ""
    Write-Host "  CIFRADO Y AUDITORIA" -ForegroundColor Yellow
    $bitlocker = manage-bde -status C: 2>&1
    $blEnabled = $bitlocker -match 'Protection Status.*On'
    Check-Item "BitLocker activo en C:" $blEnabled "Activa BitLocker en Administrar BitLocker"
    $auditLogon = auditpol /get /category:"Logon/Logoff" 2>$null | Select-String "Logon"
    Check-Item "Auditoria de inicios de sesion habilitada" ($auditLogon -match 'Success|Failure') "Ejecuta: auditpol /set /category:'Logon/Logoff' /success:enable /failure:enable"

    Write-Host ""
    Write-Host "  $('-' * 50)" -ForegroundColor DarkGray
    $percent = [math]::Round(($score / $total) * 100, 0)
    $baseColor = if ($percent -ge 80) { 'Green' } elseif ($percent -ge 60) { 'Yellow' } else { 'Red' }
    Write-Host "  PUNTUACION: " -NoNewline
    Write-Host "$score / $total  ($percent%)" -ForegroundColor $baseColor
    Write-Host "  Estado  : " -NoNewline
    Write-Host $(if ($percent -ge 80) { "Bueno" } elseif ($percent -ge 60) { "Mejorable" } else { "Requiere atencion" }) -ForegroundColor $baseColor
    Write-Host ""
    Write-Log "Baseline ejecutado: $score/$total ($percent%)"
}
