function Invoke-Seguridad {
    Show-Header
    Write-Section "CIBERSEGURIDAD Y AUDITORIA" "Magenta"

    Write-Host "  [1]   Estado de seguridad del sistema"
    Write-Host "  [2]   Auditoria de puertos y conexiones sospechosas"
    Write-Host "  [3]   Procesos sin firma digital (potencialmente riesgosos)"
    Write-Host "  [4]   Auditoria de eventos de seguridad (logins, errores)"
    Write-Host "  [5]   Recuperar contrasenas WiFi guardadas"
    Write-Host "  [6]   Analisis de entradas de inicio sospechosas"
    Write-Host "  [7]   Auditoria de usuarios y grupos con privilegios"
    Write-Host "  [8]   Verificar vulnerabilidades SMB"
    Write-Host "  [9]   Auditoria completa de seguridad"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Show-SecurityStatus }
        '2' { Show-SuspiciousConnections }
        '3' { Show-UnsignedProcesses }
        '4' { Show-SecurityEvents }
        '5' { Show-WiFiPasswords }
        '6' { Show-SuspiciousStartup }
        '7' { Show-PrivilegedAccounts }
        '8' { Test-SMBVulnerabilities }
        '9' {
            Show-SecurityStatus
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-SuspiciousConnections
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-SecurityEvents
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-SuspiciousStartup
            Write-Host ""; Read-Host "  Enter para continuar..." | Out-Null
            Show-PrivilegedAccounts
        }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Log "Seguridad - opcion: $sub"
}

function Show-SecurityStatus {
    Write-Host ""
    Write-Host "  ESTADO DE SEGURIDAD DEL SISTEMA" -ForegroundColor Magenta
    Write-Host ""

    # Windows Defender
    $wdStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($wdStatus) {
        $avColor = if ($wdStatus.AntivirusEnabled) { 'Green' } else { 'Red' }
        $fwColor = if ($wdStatus.IsTamperProtected) { 'Green' } else { 'Yellow' }
        Write-Host "  Windows Defender"
        Write-Host "    Antivirus activo      : " -NoNewline; Write-Host $wdStatus.AntivirusEnabled -ForegroundColor $avColor
        Write-Host "    Proteccion en tiempo real: " -NoNewline; Write-Host $wdStatus.RealTimeProtectionEnabled -ForegroundColor $avColor
        Write-Host "    Proteccion contra tamper: " -NoNewline; Write-Host $wdStatus.IsTamperProtected -ForegroundColor $fwColor
        Write-Host "    Ultima actualizacion  : $($wdStatus.AntivirusSignatureLastUpdated.ToString('dd/MM/yyyy HH:mm'))"
        Write-Host "    Version de firmas     : $($wdStatus.AntivirusSignatureVersion)"
    } else {
        Write-Host "  Windows Defender: No disponible o antivirus de terceros activo." -ForegroundColor Yellow
    }
    Write-Host ""

    # Firewall
    Write-Host "  FIREWALL DE WINDOWS" -ForegroundColor Yellow
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $fwProfiles | ForEach-Object {
            $fwColor = if ($_.Enabled) { 'Green' } else { 'Red' }
            Write-Host "    Perfil $($_.Name.PadRight(12)): " -NoNewline
            Write-Host $_.Enabled -ForegroundColor $fwColor
        }
    } catch {
        Write-Host "  No se pudo obtener estado del firewall." -ForegroundColor DarkGray
    }
    Write-Host ""

    # UAC
    Write-Host "  CONTROL DE CUENTAS DE USUARIO (UAC)" -ForegroundColor Yellow
    $uac = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue
    if ($uac) {
        $uacColor = if ($uac.EnableLUA -eq 1) { 'Green' } else { 'Red' }
        Write-Host "    UAC habilitado        : " -NoNewline; Write-Host ($uac.EnableLUA -eq 1) -ForegroundColor $uacColor
        Write-Host "    Nivel de consentimiento: $($uac.ConsentPromptBehaviorAdmin)"
    }
    Write-Host ""

    # BitLocker
    Write-Host "  CIFRADO DE DISCO (BitLocker)" -ForegroundColor Yellow
    $bitlocker = manage-bde -status C: 2>&1
    if ($bitlocker -match 'Protection Status:\s+(.+)') {
        $blStatus = $Matches[1].Trim()
        $blColor  = if ($blStatus -match 'On') { 'Green' } else { 'Yellow' }
        Write-Host "    Unidad C: " -NoNewline; Write-Host $blStatus -ForegroundColor $blColor
    } else {
        Write-Host "    BitLocker: No disponible o no configurado." -ForegroundColor DarkGray
    }
    Write-Host ""

    # Windows Update
    Write-Host "  WINDOWS UPDATE" -ForegroundColor Yellow
    $wu = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1
    if ($wu) {
        Write-Host "    Ultimo parche instalado: $($wu.HotFixID) el $($wu.InstalledOn.ToString('dd/MM/yyyy'))"
        $daysSince = ((Get-Date) - $wu.InstalledOn).Days
        $wuColor   = if ($daysSince -gt 60) { 'Red' } elseif ($daysSince -gt 30) { 'Yellow' } else { 'Green' }
        Write-Host "    Dias desde ultimo parche: " -NoNewline; Write-Host $daysSince -ForegroundColor $wuColor
    }
    Write-Host ""

    # Secure Boot
    $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
    $sbColor    = if ($secureBoot -eq $true) { 'Green' } else { 'Yellow' }
    Write-Host "  Secure Boot               : " -NoNewline; Write-Host $secureBoot -ForegroundColor $sbColor
    Write-Host ""
}

function Show-SuspiciousConnections {
    Write-Host ""
    Write-Host "  CONEXIONES DE RED ACTIVAS" -ForegroundColor Magenta
    Write-Host "  {0,-22} {1,-22} {2,-15} {3}" -f "IP Local", "IP Remota", "Proceso", "Puerto"
    Write-Host "  $('-' * 72)"

    $suspicious = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
                  Where-Object { $_.RemoteAddress -notmatch '^(127|::1|0\.0|10\.|192\.168|172\.(1[6-9]|2[0-9]|3[0-1]))' } |
                  Sort-Object RemoteAddress

    if ($suspicious) {
        $suspicious | ForEach-Object {
            $conn = $_
            try {
                $proc  = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                $pName = if ($proc) { $proc.Name } else { "Sistema" }
            } catch { $pName = "N/D" }
            $portColor = if ($conn.RemotePort -in @(4444,1337,6667,31337,8888,9999)) { 'Red' } else { 'White' }
            Write-Host ("  {0,-22} {1,-22} {2,-15} " -f "$($conn.LocalAddress):$($conn.LocalPort)", "$($conn.RemoteAddress):$($conn.RemotePort)", $pName) -NoNewline
            Write-Host $conn.RemotePort -ForegroundColor $portColor
        }
        Write-Host ""
        Write-Host "  Total conexiones externas: $($suspicious.Count)" -ForegroundColor Cyan
    } else {
        Write-Host "  No se encontraron conexiones externas activas." -ForegroundColor Green
    }
    Write-Host ""
}

function Show-UnsignedProcesses {
    Write-Host ""
    Write-Host "  PROCESOS SIN FIRMA DIGITAL" -ForegroundColor Magenta
    Write-Host "  (Estos procesos no estan firmados por Microsoft o fabricante conocido)" -ForegroundColor DarkGray
    Write-Host ""

    $unsigned = Get-Process | Where-Object { $_.Path } | ForEach-Object {
        $sig = Get-AuthenticodeSignature -FilePath $_.Path -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -ne 'Valid') {
            [PSCustomObject]@{
                Name   = $_.Name
                Path   = $_.Path
                Status = $sig.Status
                RAM    = [math]::Round($_.WorkingSet64 / 1MB, 1)
            }
        }
    } | Where-Object { $_ }

    if ($unsigned) {
        Write-Host "  {0,-25} {1,-12} {2,8} {3}" -f "Proceso", "Estado", "RAM MB", "Ruta"
        Write-Host "  $('-' * 85)"
        $unsigned | ForEach-Object {
            $color = if ($_.Status -eq 'NotSigned') { 'Red' } else { 'Yellow' }
            $path  = if ($_.Path.Length -gt 45) { ".." + $_.Path.Substring($_.Path.Length - 43) } else { $_.Path }
            Write-Host ("  {0,-25} " -f $_.Name) -NoNewline
            Write-Host ("{0,-12} " -f $_.Status) -ForegroundColor $color -NoNewline
            Write-Host ("{0,8} {1}" -f $_.RAM, $path)
        }
    } else {
        Write-Host "  Todos los procesos tienen firma digital valida." -ForegroundColor Green
    }
    Write-Host ""
}

function Show-SecurityEvents {
    Write-Host ""
    Write-Host "  EVENTOS DE SEGURIDAD RECIENTES (ultimas 24h)" -ForegroundColor Magenta
    Write-Host ""

    $since = (Get-Date).AddHours(-24)

    # Logins fallidos (Event 4625)
    Write-Host "  INTENTOS DE LOGIN FALLIDOS (ID 4625)" -ForegroundColor Yellow
    $failedLogins = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=$since} -ErrorAction SilentlyContinue |
                    Select-Object -First 10
    if ($failedLogins) {
        Write-Host "  Total en ultimas 24h: $($failedLogins.Count)" -ForegroundColor Red
        $failedLogins | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.TimeCreated.ToString('HH:mm:ss')) - $($_.Message.Substring(0,[Math]::Min(100,$_.Message.Length)))"
        }
    } else {
        Write-Host "  No se encontraron intentos fallidos." -ForegroundColor Green
    }
    Write-Host ""

    # Logins exitosos (Event 4624)
    Write-Host "  INICIOS DE SESION EXITOSOS (ID 4624)" -ForegroundColor Yellow
    $successLogins = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=$since} -ErrorAction SilentlyContinue |
                     Select-Object -First 10
    if ($successLogins) {
        Write-Host "  Total en ultimas 24h: $($successLogins.Count)"
        $successLogins | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.TimeCreated.ToString('HH:mm:ss'))"
        }
    }
    Write-Host ""

    # Cambios en cuentas (4720, 4732, 4728)
    Write-Host "  CAMBIOS EN CUENTAS Y GRUPOS (IDs 4720, 4732, 4728)" -ForegroundColor Yellow
    $accountEvents = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=@(4720,4732,4728); StartTime=$since} -ErrorAction SilentlyContinue |
                     Select-Object -First 5
    if ($accountEvents) {
        $accountEvents | ForEach-Object {
            Write-Host "  [ALERTA] $($_.TimeCreated.ToString('HH:mm:ss')) - $($_.Id) - $($_.Message.Substring(0,[Math]::Min(80,$_.Message.Length)))" -ForegroundColor Red
        }
    } else {
        Write-Host "  No se encontraron cambios en cuentas o grupos." -ForegroundColor Green
    }
    Write-Host ""
}

function Show-WiFiPasswords {
    Write-Host ""
    Write-Host "  CONTRASENAS WIFI GUARDADAS EN ESTE EQUIPO" -ForegroundColor Magenta
    Write-Host "  (Solo contrasenas de redes a las que este equipo se ha conectado)" -ForegroundColor DarkGray
    Write-Host ""

    $profiles = netsh wlan show profiles 2>$null | Select-String "All User Profile" | ForEach-Object {
        ($_ -split ':')[1].Trim()
    }

    if (-not $profiles) {
        Write-Host "  No se encontraron perfiles WiFi guardados." -ForegroundColor DarkGray
        return
    }

    Write-Host "  {0,-35} {1}" -f "Red (SSID)", "Contrasena"
    Write-Host "  $('-' * 60)"

    $profiles | ForEach-Object {
        $profile = $_
        $data    = netsh wlan show profile name=$profile key=clear 2>$null
        if ($data -match 'Key Content\s+:\s+(.+)') {
            $pass = $Matches[1].Trim()
            Write-Host ("  {0,-35} {1}" -f $profile, $pass) -ForegroundColor Cyan
        } else {
            Write-Host ("  {0,-35} {1}" -f $profile, "(sin contrasena / no disponible)") -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

function Show-SuspiciousStartup {
    Write-Host ""
    Write-Host "  ENTRADAS DE INICIO DEL SISTEMA" -ForegroundColor Magenta
    Write-Host ""

    $regKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )

    $suspiciousPaths = @('temp','tmp','appdata\local\temp','downloads','desktop','public')

    $allEntries = $regKeys | ForEach-Object {
        $key = $_
        Get-ItemProperty $key -ErrorAction SilentlyContinue | ForEach-Object {
            $_.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                $entry       = $_
                $entryValue  = $entry.Value
                $isSuspicious = ($suspiciousPaths | Where-Object { $entryValue -ilike "*$_*" }).Count -gt 0
                [PSCustomObject]@{
                    Name       = $entry.Name
                    Value      = $entry.Value
                    Scope      = if ($key -like 'HKLM*') { 'Sistema' } else { 'Usuario' }
                    Suspicious = $isSuspicious
                }
            }
        }
    }

    if ($allEntries) {
        Write-Host "  {0,-30} {1,-10} {2}" -f "Nombre", "Alcance", "Ruta"
        Write-Host "  $('-' * 85)"
        $allEntries | ForEach-Object {
            $color = if ($_.Suspicious) { 'Red' } else { 'White' }
            $val   = if ($_.Value.Length -gt 50) { $_.Value.Substring(0,50) + ".." } else { $_.Value }
            $flag  = if ($_.Suspicious) { " [REVISAR]" } else { "" }
            Write-Host ("  {0,-30} {1,-10} " -f $_.Name, $_.Scope) -NoNewline
            Write-Host "$val$flag" -ForegroundColor $color
        }
        $suspicious = $allEntries | Where-Object { $_.Suspicious }
        if ($suspicious) {
            Write-Host ""
            Write-Host "  ATENCION: $($suspicious.Count) entrada(s) con ruta sospechosa encontrada(s)." -ForegroundColor Red
        }
    } else {
        Write-Host "  No se encontraron entradas de inicio." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Show-PrivilegedAccounts {
    Write-Host ""
    Write-Host "  USUARIOS Y GRUPOS CON PRIVILEGIOS ELEVADOS" -ForegroundColor Magenta
    Write-Host ""

    Write-Host "  MIEMBROS DEL GRUPO ADMINISTRADORES" -ForegroundColor Yellow
    $admins = net localgroup Administrators 2>$null
    $admins | Select-Object -Skip 6 | Where-Object { $_ -and $_ -notmatch '^-' -and $_ -notmatch 'The command' } |
        ForEach-Object { Write-Host "    · $_" -ForegroundColor Cyan }
    Write-Host ""

    Write-Host "  CUENTAS DE USUARIO LOCALES" -ForegroundColor Yellow
    Write-Host "  {0,-25} {1,-12} {2,-12} {3}" -f "Usuario", "Habilitada", "Admin", "Ultimo login"
    Write-Host "  $('-' * 65)"

    Get-LocalUser -ErrorAction SilentlyContinue | ForEach-Object {
        $u       = $_
        $isAdmin = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $u.Name }).Count -gt 0
        $lastLog = if ($u.LastLogon) { $u.LastLogon.ToString('dd/MM/yyyy') } else { "Nunca" }
        $enColor = if ($u.Enabled) { 'Green' } else { 'DarkGray' }
        $adColor = if ($isAdmin) { 'Yellow' } else { 'White' }
        Write-Host ("  {0,-25} " -f $u.Name) -NoNewline
        Write-Host ("{0,-12} " -f $u.Enabled) -ForegroundColor $enColor -NoNewline
        Write-Host ("{0,-12} " -f $isAdmin) -ForegroundColor $adColor -NoNewline
        Write-Host $lastLog
    }
    Write-Host ""
}

function Test-SMBVulnerabilities {
    Write-Host ""
    Write-Host "  VERIFICACION DE VULNERABILIDADES SMB" -ForegroundColor Magenta
    Write-Host "  (EternalBlue / WannaCry - SMBv1)" -ForegroundColor DarkGray
    Write-Host ""

    # SMBv1
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    if ($smb1) {
        $color = if ($smb1.State -eq 'Disabled') { 'Green' } else { 'Red' }
        Write-Host "  SMBv1 (EternalBlue): " -NoNewline
        Write-Host $smb1.State -ForegroundColor $color
        if ($smb1.State -eq 'Enabled') {
            Write-Host "  RIESGO: SMBv1 esta habilitado. DESHABILITAR de inmediato." -ForegroundColor Red
            $fix = Read-Host "  Deshabilitar SMBv1 ahora? (s/n)"
            if ($fix -ieq 's') {
                Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
                Write-Host "  SMBv1 deshabilitado. Reinicia el equipo para aplicar." -ForegroundColor Green
                Write-Log "SMBv1 deshabilitado"
            }
        }
    }

    # SMBv2/v3
    $smb2 = Get-SmbServerConfiguration -ErrorAction SilentlyContinue
    if ($smb2) {
        $s2Color = if ($smb2.EnableSMB2Protocol) { 'Green' } else { 'Yellow' }
        Write-Host "  SMBv2/v3 habilitado  : " -NoNewline; Write-Host $smb2.EnableSMB2Protocol -ForegroundColor $s2Color
        Write-Host "  Firma SMB requerida  : $($smb2.RequireSecuritySignature)"
        Write-Host "  Cifrado SMB          : $($smb2.EncryptData)"
    }

    # Puerto 445 expuesto
    Write-Host ""
    $port445 = Get-NetTCPConnection -LocalPort 445 -State Listen -ErrorAction SilentlyContinue
    if ($port445) {
        Write-Host "  Puerto 445 (SMB)     : " -NoNewline; Write-Host "ABIERTO Y ESCUCHANDO" -ForegroundColor Yellow
    } else {
        Write-Host "  Puerto 445 (SMB)     : " -NoNewline; Write-Host "No escuchando" -ForegroundColor Green
    }
    Write-Host ""
}
