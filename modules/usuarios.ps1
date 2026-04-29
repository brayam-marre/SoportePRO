function Invoke-Usuarios {
    Show-Header
    Write-Section "USUARIOS Y CUENTAS"

    Write-Host "  [1]   Listar todos los usuarios locales"
    Write-Host "  [2]   Crear usuario local"
    Write-Host "  [3]   Habilitar / Deshabilitar usuario"
    Write-Host "  [4]   Restablecer contrasena de usuario"
    Write-Host "  [5]   Listar grupos y miembros"
    Write-Host "  [6]   Agregar usuario a grupo"
    Write-Host "  [7]   Sesiones activas y logins recientes"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"
    switch ($sub) {
        '1' { Show-LocalUsers }
        '2' { New-LocalUserAccount }
        '3' { Toggle-UserAccount }
        '4' { Reset-UserPassword }
        '5' { Show-LocalGroups }
        '6' { Add-UserToGroup }
        '7' { Show-ActiveSessions }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Log "Usuarios - opcion: $sub"
}

function Show-LocalUsers {
    Write-Host ""
    Write-Host "  USUARIOS LOCALES" -ForegroundColor Yellow
    Write-Host "  {0,-25} {1,-12} {2,-12} {3,-12} {4}" -f "Usuario", "Habilitado", "Admin", "Ultimo login", "Descripcion"
    Write-Host "  $('-' * 85)"

    Get-LocalUser -ErrorAction SilentlyContinue | ForEach-Object {
        $u = $_
        $isAdmin = (Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -like "*$($u.Name)" }).Count -gt 0
        $lastLog = if ($u.LastLogon) { $u.LastLogon.ToString('dd/MM/yy HH:mm') } else { "Nunca" }
        $enColor = if ($u.Enabled) { 'Green' } else { 'DarkGray' }
        $adColor = if ($isAdmin) { 'Yellow' } else { 'White' }

        Write-Host ("  {0,-25} " -f $u.Name) -NoNewline
        Write-Host ("{0,-12} " -f $u.Enabled) -ForegroundColor $enColor -NoNewline
        Write-Host ("{0,-12} " -f $isAdmin) -ForegroundColor $adColor -NoNewline
        Write-Host ("{0,-12} {1}" -f $lastLog, $u.Description)
    }
    Write-Host ""

    $total    = (Get-LocalUser -ErrorAction SilentlyContinue).Count
    $enabled  = (Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Enabled }).Count
    $disabled = $total - $enabled
    Write-Host "  Total: $total  |  Habilitados: $enabled  |  Deshabilitados: $disabled" -ForegroundColor Cyan
    Write-Host ""
}

function New-LocalUserAccount {
    Write-Host ""
    Write-Host "  CREAR USUARIO LOCAL" -ForegroundColor Yellow
    Write-Host ""

    $userName = Read-Host "  Nombre de usuario"
    if (-not $userName) { return }

    if (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue) {
        Write-Host "  El usuario '$userName' ya existe." -ForegroundColor Red
        return
    }

    $fullName = Read-Host "  Nombre completo (opcional)"
    $desc     = Read-Host "  Descripcion (opcional)"
    $pass     = Read-Host "  Contrasena" -AsSecureString
    $isAdmin  = Read-Host "  Agregar al grupo Administradores? (s/n)"

    try {
        $params = @{ Name = $userName; Password = $pass; AccountNeverExpires = $true }
        if ($fullName) { $params.FullName    = $fullName }
        if ($desc)     { $params.Description = $desc }

        New-LocalUser @params -ErrorAction Stop | Out-Null
        Write-Host "  [OK] Usuario '$userName' creado." -ForegroundColor Green

        if ($isAdmin -ieq 's') {
            Add-LocalGroupMember -Group "Administrators" -Member $userName -ErrorAction SilentlyContinue
            Write-Host "  [OK] Agregado al grupo Administradores." -ForegroundColor Green
        } else {
            Add-LocalGroupMember -Group "Users" -Member $userName -ErrorAction SilentlyContinue
        }

        Write-Log "Usuario creado: $userName"
    } catch {
        Write-Host "  Error al crear usuario: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Toggle-UserAccount {
    Write-Host ""
    $userName = Read-Host "  Nombre de usuario"
    if (-not $userName) { return }

    $user = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "  Usuario no encontrado: $userName" -ForegroundColor Red
        return
    }

    if ($user.Enabled) {
        Disable-LocalUser -Name $userName -ErrorAction SilentlyContinue
        Write-Host "  Usuario '$userName' DESHABILITADO." -ForegroundColor Yellow
        Write-Log "Usuario deshabilitado: $userName"
    } else {
        Enable-LocalUser -Name $userName -ErrorAction SilentlyContinue
        Write-Host "  Usuario '$userName' HABILITADO." -ForegroundColor Green
        Write-Log "Usuario habilitado: $userName"
    }
    Write-Host ""
}

function Reset-UserPassword {
    Write-Host ""
    Write-Host "  RESTABLECER CONTRASENA" -ForegroundColor Yellow
    $userName = Read-Host "  Nombre de usuario"
    if (-not $userName) { return }

    if (-not (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
        Write-Host "  Usuario no encontrado: $userName" -ForegroundColor Red
        return
    }

    $newPass = Read-Host "  Nueva contrasena" -AsSecureString

    try {
        Set-LocalUser -Name $userName -Password $newPass -ErrorAction Stop
        Write-Host "  Contrasena cambiada correctamente para '$userName'." -ForegroundColor Green
        Write-Log "Contrasena cambiada: $userName"
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Show-LocalGroups {
    Write-Host ""
    Write-Host "  GRUPOS LOCALES" -ForegroundColor Yellow
    Write-Host ""

    Get-LocalGroup -ErrorAction SilentlyContinue | ForEach-Object {
        $group   = $_
        $members = Get-LocalGroupMember -Group $group.Name -ErrorAction SilentlyContinue
        $mCount  = if ($members) { $members.Count } else { 0 }

        Write-Host "  $($group.Name)" -ForegroundColor Cyan -NoNewline
        Write-Host "  ($mCount miembro(s))"

        if ($mCount -gt 0 -and $mCount -le 10) {
            $members | ForEach-Object {
                Write-Host "    · $($_.Name) [$($_.ObjectClass)]" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
}

function Add-UserToGroup {
    Write-Host ""
    $userName  = Read-Host "  Nombre de usuario"
    $groupName = Read-Host "  Nombre del grupo (ej: Administrators, Users)"

    if (-not $userName -or -not $groupName) { return }

    try {
        Add-LocalGroupMember -Group $groupName -Member $userName -ErrorAction Stop
        Write-Host "  '$userName' agregado al grupo '$groupName'." -ForegroundColor Green
        Write-Log "Usuario $userName agregado a grupo: $groupName"
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Show-ActiveSessions {
    Write-Host ""
    Write-Host "  SESIONES ACTIVAS" -ForegroundColor Yellow
    query session 2>&1 | ForEach-Object { Write-Host "  $_" }
    Write-Host ""

    Write-Host "  LOGINS RECIENTES (Event ID 4624 - ultimas 48h)" -ForegroundColor Yellow
    $since = (Get-Date).AddHours(-48)
    $logins = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=$since} -ErrorAction SilentlyContinue |
              Select-Object -First 15
    if ($logins) {
        $logins | ForEach-Object {
            Write-Host "  $($_.TimeCreated.ToString('dd/MM HH:mm:ss'))" -ForegroundColor DarkGray -NoNewline
            if ($_.Message -match 'Account Name:\s+(.+)') {
                Write-Host "  Usuario: $($Matches[1].Trim())" -NoNewline
            }
            if ($_.Message -match 'Logon Type:\s+(\d+)') {
                $type = switch ($Matches[1]) {
                    '2'  { 'Interactivo' }
                    '3'  { 'Red' }
                    '4'  { 'Tarea programada' }
                    '5'  { 'Servicio' }
                    '10' { 'Remoto (RDP)' }
                    '11' { 'Desbloqueo' }
                    default { "Tipo $($Matches[1])" }
                }
                Write-Host "  | $type"
            } else { Write-Host "" }
        }
    } else {
        Write-Host "  No se encontraron eventos de login recientes (requiere auditoria activa)." -ForegroundColor DarkGray
    }
    Write-Host ""
}
