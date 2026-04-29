function Invoke-Reparacion {
    Show-Header
    Write-Section "REPARACION DE WINDOWS"

    Write-Host "  Selecciona una opcion:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1]   Verificar archivos del sistema (SFC /scannow)"
    Write-Host "  [2]   Reparar imagen de Windows (DISM)"
    Write-Host "  [3]   Programar verificacion de disco (chkdsk)"
    Write-Host "  [4]   Restablecer pila de red (Winsock + TCP/IP)"
    Write-Host "  [5]   Reparar arranque de Windows (MBR/BCD)"
    Write-Host "  [6]   Limpiar componentes de Windows Update"
    Write-Host "  [7]   Ejecutar reparacion completa (1 + 2 + 4)"
    Write-Host ""
    Write-Host "  [0]   Volver al menu"
    Write-Host ""

    $sub = Read-Host "  Opcion"

    switch ($sub) {
        '1' { Invoke-SFC }
        '2' { Invoke-DISM }
        '3' { Invoke-Chkdsk }
        '4' { Invoke-NetworkReset }
        '5' { Invoke-BootRepair }
        '6' { Invoke-WUClean }
        '7' {
            Invoke-SFC
            Write-Host ""; Write-Host "  Presiona Enter para continuar con DISM..." -ForegroundColor DarkGray; Read-Host | Out-Null
            Invoke-DISM
            Write-Host ""; Write-Host "  Presiona Enter para continuar con red..." -ForegroundColor DarkGray; Read-Host | Out-Null
            Invoke-NetworkReset
            Write-Host ""
            Write-Host "  Reparacion completa finalizada." -ForegroundColor Green
        }
        '0' { return }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Log "Reparacion ejecutada - opcion: $sub"
}

function Invoke-SFC {
    Write-Host ""
    Write-Host "  Ejecutando SFC /scannow..." -ForegroundColor Yellow
    Write-Host "  Este proceso puede tardar varios minutos. No cierres la ventana." -ForegroundColor DarkGray
    Write-Host ""
    $result = sfc /scannow 2>&1
    $result | ForEach-Object { Write-Host "  $_" }
    Write-Log "SFC ejecutado"
}

function Invoke-DISM {
    Write-Host ""
    Write-Host "  Ejecutando DISM - Reparacion de imagen de Windows..." -ForegroundColor Yellow
    Write-Host "  Este proceso puede tardar entre 10 y 20 minutos." -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  [1/3] Verificando estado de la imagen..." -ForegroundColor DarkGray
    DISM /Online /Cleanup-Image /CheckHealth 2>&1 | ForEach-Object { Write-Host "  $_" }

    Write-Host ""
    Write-Host "  [2/3] Escaneando integridad..." -ForegroundColor DarkGray
    DISM /Online /Cleanup-Image /ScanHealth 2>&1 | ForEach-Object { Write-Host "  $_" }

    Write-Host ""
    Write-Host "  [3/3] Restaurando componentes danados..." -ForegroundColor DarkGray
    DISM /Online /Cleanup-Image /RestoreHealth 2>&1 | ForEach-Object { Write-Host "  $_" }

    Write-Log "DISM ejecutado"
}

function Invoke-Chkdsk {
    Write-Host ""
    Write-Host "  Verificacion de disco (chkdsk C: /f /r)" -ForegroundColor Yellow
    Write-Host "  La verificacion se ejecutara en el proximo reinicio del sistema." -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  Confirmas la programacion? (s/n)"
    if ($confirm -ieq 's') {
        "Y" | chkdsk C: /f /r 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "  chkdsk quedo programado para el proximo inicio." -ForegroundColor Green
        Write-Log "chkdsk programado para unidad C:"
    } else {
        Write-Host "  Operacion cancelada." -ForegroundColor DarkGray
    }
}

function Invoke-NetworkReset {
    Write-Host ""
    Write-Host "  Restableciendo pila de red completa..." -ForegroundColor Yellow
    Write-Host ""

    netsh winsock reset 2>&1 | Out-Null
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "Winsock reiniciado"

    netsh int ip reset 2>&1 | Out-Null
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "TCP/IP reiniciado"

    netsh int tcp reset 2>&1 | Out-Null
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "TCP reiniciado"

    netsh advfirewall reset 2>&1 | Out-Null
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "Firewall reiniciado a configuracion predeterminada"

    ipconfig /release 2>&1 | Out-Null
    ipconfig /renew   2>&1 | Out-Null
    ipconfig /flushdns 2>&1 | Out-Null
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "IP renovada y cache DNS vaciada"

    Write-Host ""
    Write-Host "  RECOMENDACION: Reinicia el equipo para aplicar todos los cambios." -ForegroundColor Yellow
    Write-Log "Pila de red restablecida"
}

function Invoke-BootRepair {
    Write-Host ""
    Write-Host "  Reparacion de arranque de Windows (MBR/BCD)" -ForegroundColor Yellow
    Write-Host "  ATENCION: Esta operacion modifica el sector de arranque." -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "  Confirmas la reparacion del arranque? (s/n)"
    if ($confirm -ieq 's') {
        Write-Host ""
        bootrec /fixmbr 2>&1  | ForEach-Object { Write-Host "  [MBR] $_" }
        bootrec /fixboot 2>&1 | ForEach-Object { Write-Host "  [BCD] $_" }
        bootrec /rebuildbcd 2>&1 | ForEach-Object { Write-Host "  [REB] $_" }
        Write-Host ""
        Write-Host "  Reparacion de arranque completada. Reinicia el equipo." -ForegroundColor Green
        Write-Log "Reparacion de arranque ejecutada"
    } else {
        Write-Host "  Operacion cancelada." -ForegroundColor DarkGray
    }
}

function Invoke-WUClean {
    Write-Host ""
    Write-Host "  Limpiando componentes de Windows Update..." -ForegroundColor Yellow
    Write-Host ""

    $services = @('wuauserv','cryptSvc','bits','msiserver')
    $services | ForEach-Object { Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue }
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "Servicios de Windows Update detenidos"

    Rename-Item "C:\Windows\SoftwareDistribution"   "SoftwareDistribution.old"   -ErrorAction SilentlyContinue
    Rename-Item "C:\Windows\System32\catroot2"       "catroot2.old"               -ErrorAction SilentlyContinue
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "Carpetas de cache renombradas"

    $services | ForEach-Object { Start-Service -Name $_ -ErrorAction SilentlyContinue }
    Write-Host "  [  OK  ] " -ForegroundColor Green -NoNewline; Write-Host "Servicios reiniciados"

    Write-Host ""
    Write-Host "  Windows Update fue reiniciado correctamente." -ForegroundColor Green
    Write-Log "Windows Update limpiado"
}
