function Invoke-Diagnostico {
    Show-Header
    Write-Section "DIAGNOSTICO DEL SISTEMA"

    # -- Sistema operativo -------------------------------------
    $os   = Get-CimInstance Win32_OperatingSystem
    $cs   = Get-CimInstance Win32_ComputerSystem
    $cpu  = Get-CimInstance Win32_Processor
    $bios = Get-CimInstance Win32_BIOS
    $mb   = Get-CimInstance Win32_BaseBoard
    $gpu  = Get-CimInstance Win32_VideoController | Select-Object -First 1
    $uptime = (Get-Date) - $os.LastBootUpTime

    Write-Host "  SISTEMA OPERATIVO" -ForegroundColor Yellow
    Write-Host "  Nombre del equipo  : $($cs.Name)"
    Write-Host "  Fabricante         : $($cs.Manufacturer) $($cs.Model)"
    Write-Host "  Sistema operativo  : $($os.Caption) $($os.OSArchitecture)"
    Write-Host "  Version            : $($os.Version)  (Build $($os.BuildNumber))"
    Write-Host "  Idioma             : $($os.MUILanguages -join ', ')"
    Write-Host "  Tiempo encendido   : $([int]$uptime.TotalDays)d $($uptime.Hours)h $($uptime.Minutes)m"
    Write-Host "  Ultimo reinicio    : $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm'))"
    Write-Host "  BIOS               : $($bios.SMBIOSBIOSVersion) ($($bios.ReleaseDate.ToString('dd/MM/yyyy')))"
    Write-Host "  Placa madre        : $($mb.Manufacturer) $($mb.Product)"
    Write-Host ""

    # -- CPU ---------------------------------------------------
    Write-Host "  PROCESADOR" -ForegroundColor Yellow
    Write-Host "  Modelo             : $($cpu.Name.Trim())"
    Write-Host "  Nucleo(s)          : $($cpu.NumberOfCores) fisicos / $($cpu.NumberOfLogicalProcessors) logicos"
    Write-Host "  Velocidad base     : $([math]::Round($cpu.MaxClockSpeed / 1000, 2)) GHz"
    Write-Host "  Socket             : $($cpu.SocketDesignation)"
    $cpuLoad = (Get-CimInstance Win32_Processor).LoadPercentage
    $cpuColor = if ($cpuLoad -gt 80) { 'Red' } elseif ($cpuLoad -gt 50) { 'Yellow' } else { 'Green' }
    Write-Host "  Uso actual         : " -NoNewline
    Write-Host "$cpuLoad%" -ForegroundColor $cpuColor
    Write-Host ""

    # -- RAM ---------------------------------------------------
    Write-Host "  MEMORIA RAM" -ForegroundColor Yellow
    $totalRam   = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    $freeRam    = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedRam    = [math]::Round($totalRam - $freeRam, 2)
    $ramPercent = [math]::Round(($usedRam / $totalRam) * 100, 1)
    $ramColor   = if ($ramPercent -gt 85) { 'Red' } elseif ($ramPercent -gt 65) { 'Yellow' } else { 'Green' }
    Write-Host "  Total              : $totalRam GB"
    Write-Host "  En uso             : " -NoNewline; Write-Host "$usedRam GB ($ramPercent%)" -ForegroundColor $ramColor
    Write-Host "  Libre              : $freeRam GB"

    # Capacidad maxima soportada
    $ramArray = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue
    $ramModules = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    if ($ramArray) {
        $maxRamGB   = [math]::Round($ramArray.MaxCapacity / 1MB, 0)
        $totalSlots = $ramArray.MemoryDevices
        $usedSlots  = ($ramModules | Measure-Object).Count
        $freeSlots  = $totalSlots - $usedSlots
        Write-Host "  Maximo soportado   : " -NoNewline; Write-Host "$maxRamGB GB" -ForegroundColor Cyan
        Write-Host "  Slots totales      : $totalSlots  (usados: $usedSlots  libres: $freeSlots)"
    }

    # Bancos de RAM
    if ($ramModules) {
        Write-Host "  Modulos instalados :"
        $ramModules | ForEach-Object {
            $ramGB   = [math]::Round($_.Capacity / 1GB, 0)
            $memType = switch ($_.MemoryType) {
                20 { 'DDR' }; 21 { 'DDR2' }; 22 { 'DDR2 FB-DIMM' }
                24 { 'DDR3' }; 26 { 'DDR4' }; 34 { 'DDR5' }
                default { "Tipo $($_.MemoryType)" }
            }
            Write-Host "    -> Slot $($_.DeviceLocator): $ramGB GB $memType @ $($_.Speed) MHz"
        }
    }
    Write-Host ""

    # -- GPU ---------------------------------------------------
    if ($gpu) {
        Write-Host "  TARJETA GRAFICA" -ForegroundColor Yellow
        Write-Host "  Modelo             : $($gpu.Name)"
        $vram = if ($gpu.AdapterRAM -gt 0) { "$([math]::Round($gpu.AdapterRAM / 1GB, 1)) GB" } else { "N/D" }
        Write-Host "  VRAM               : $vram"
        Write-Host "  Driver             : $($gpu.DriverVersion)"
        Write-Host ""
    }

    # -- Almacenamiento ----------------------------------------
    Write-Host "  ALMACENAMIENTO" -ForegroundColor Yellow
    Write-Host "  {0,-10} {1,10} {2,10} {3,10} {4,8}" -f "Unidad", "Total", "Usado", "Libre", "% Uso"
    Write-Host "  $('-' * 52)"
    Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used } | ForEach-Object {
        $total = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
        $used  = [math]::Round($_.Used / 1GB, 2)
        $free  = [math]::Round($_.Free / 1GB, 2)
        $pct   = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }
        $color = if ($pct -gt 90) { 'Red' } elseif ($pct -gt 75) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-10} {1,10} {2,10} {3,10} " -f "$($_.Name):", "$total GB", "$used GB", "$free GB") -NoNewline
        Write-Host ("{0,8}" -f "$pct%") -ForegroundColor $color
    }
    Write-Host ""

    # Discos fisicos instalados
    $physicalDisks = Get-PhysicalDisk -ErrorAction SilentlyContinue
    if ($physicalDisks) {
        Write-Host "  Discos fisicos instalados:" -ForegroundColor Yellow
        $physicalDisks | ForEach-Object {
            $sizeGB  = [math]::Round($_.Size / 1GB, 0)
            $hColor  = if ($_.HealthStatus -eq 'Healthy') { 'Green' } else { 'Red' }

            $diskType = switch -Regex ("$($_.MediaType)|$($_.BusType)") {
                'SSD.*NVMe|NVMe.*SSD|NVMe' { 'NVMe SSD (muy rapido)';   break }
                'SSD.*SATA|SATA.*SSD'       { 'SATA SSD (rapido)';       break }
                'SSD'                        { 'SSD';                      break }
                'HDD'                        { 'HDD - Disco duro (lento)'; break }
                'SCM'                        { 'Intel Optane';             break }
                default                      { "$($_.MediaType) / $($_.BusType)" }
            }

            $typeColor = switch -Wildcard ($diskType) {
                'NVMe*' { 'Cyan' }
                'SATA*' { 'Green' }
                'HDD*'  { 'Yellow' }
                default { 'White' }
            }

            Write-Host "    -> $($_.FriendlyName)  $sizeGB GB" -NoNewline
            Write-Host "  [$diskType]" -ForegroundColor $typeColor -NoNewline
            Write-Host "  Estado: " -NoNewline
            Write-Host $_.HealthStatus -ForegroundColor $hColor
        }
        Write-Host "  Discos instalados  : $($physicalDisks.Count)"
    }
    Write-Host ""

    # -- Temperatura (si disponible) ---------------------------
    $temps = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    if ($temps) {
        Write-Host "  TEMPERATURA" -ForegroundColor Yellow
        $temps | ForEach-Object {
            $tempC = [math]::Round(($_.CurrentTemperature - 2732) / 10, 1)
            $tColor = if ($tempC -gt 85) { 'Red' } elseif ($tempC -gt 70) { 'Yellow' } else { 'Green' }
            Write-Host "  $($_.InstanceName.Split('\')[-1]): " -NoNewline
            Write-Host "$tempC C" -ForegroundColor $tColor
        }
        Write-Host ""
    }

    # -- Eventos criticos recientes ----------------------------
    Write-Host "  EVENTOS CRITICOS (ultimas 24 horas)" -ForegroundColor Yellow
    $since  = (Get-Date).AddHours(-24)
    $events = Get-EventLog -LogName System -EntryType Error,Warning -After $since -Newest 8 -ErrorAction SilentlyContinue
    if ($events) {
        $events | ForEach-Object {
            $eColor = if ($_.EntryType -eq 'Error') { 'Red' } else { 'Yellow' }
            $msg    = $_.Message.Substring(0, [Math]::Min(75, $_.Message.Length))
            Write-Host "  [$($_.EntryType.ToString().PadRight(7))] " -ForegroundColor $eColor -NoNewline
            Write-Host "$($_.TimeGenerated.ToString('HH:mm')) - $($_.Source): $msg..."
        }
    } else {
        Write-Host "  No se encontraron eventos criticos recientes." -ForegroundColor Green
    }
    Write-Host ""

    Write-Log "Diagnostico ejecutado"
}

# ── Analisis de compatibilidad - retorna datos estructurados ──
function Get-AnalisisEquipo {
    $os       = Get-CimInstance Win32_OperatingSystem
    $cs       = Get-CimInstance Win32_ComputerSystem
    $cpu      = Get-CimInstance Win32_Processor
    $ramArray = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue
    $ramMods  = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $disks    = Get-PhysicalDisk -ErrorAction SilentlyContinue
    $tpm      = Get-WmiObject -Namespace "root\cimv2\security\microsofttpm" -Class Win32_Tpm -ErrorAction SilentlyContinue
    $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue

    $totalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    $cpuName    = $cpu.Name.Trim()
    $osName     = $os.Caption
    $score      = 0
    $maxScore   = 0
    $upgrades   = @()
    $warnings   = @()

    # -- CPU ------------------------------------------------------
    $cpuGen = 0; $cpuBrand = ""
    if ($cpuName -match 'Intel') {
        $cpuBrand = "Intel"
        if    ($cpuName -match '12th|13th|14th')              { $cpuGen = 13 }
        elseif($cpuName -match '11th')                         { $cpuGen = 11 }
        elseif($cpuName -match '10th')                         { $cpuGen = 10 }
        elseif($cpuName -match 'Core.*i[3579]-(\d{2})\d{3}')  { $cpuGen = [int]$Matches[1] }
        elseif($cpuName -match 'Core.*i[3579]-(\d)\d{3}')     { $cpuGen = [int]$Matches[1] }
        elseif($cpuName -match 'Core 2')                       { $cpuGen = 1 }
        elseif($cpuName -match 'Pentium|Celeron|Atom')         { $cpuGen = 2 }
    } elseif ($cpuName -match 'AMD') {
        $cpuBrand = "AMD"
        if    ($cpuName -match 'Ryzen.*[579].*7[0-9]{3}')    { $cpuGen = 12 }
        elseif($cpuName -match 'Ryzen.*[579].*[56][0-9]{3}') { $cpuGen = 10 }
        elseif($cpuName -match 'Ryzen.*[579].*[34][0-9]{3}') { $cpuGen = 8 }
        elseif($cpuName -match 'Ryzen.*[579].*[12][0-9]{3}') { $cpuGen = 7 }
        elseif($cpuName -match 'FX|Phenom|Athlon')            { $cpuGen = 3 }
    }

    $maxScore += 30
    $cpuStatus = ""; $cpuDetail = ""
    if ($cpuGen -ge 10) {
        $score += 30; $cpuStatus = "BIEN"
        $cpuDetail = "CPU moderno, rendimiento correcto para Windows 11"
    } elseif ($cpuGen -ge 7) {
        $score += 20; $cpuStatus = "REGULAR"
        $cpuDetail = "CPU de generacion media. Funciona, pero puede ser lento en tareas pesadas"
        $upgrades += "PROCESADOR: Tu CPU tiene algunos anos pero aun funciona. Si el equipo va lento, considera actualizar."
    } elseif ($cpuGen -ge 4) {
        $score += 10; $cpuStatus = "MEJORAR"
        $cpuDetail = "CPU antiguo. Puede causar lentitud general en Windows 10/11"
        $upgrades += "PROCESADOR: CPU de generacion antigua. Considera cambiar el equipo en los proximos 1-2 anos."
    } else {
        $cpuStatus = "CRITICO"
        $cpuDetail = "CPU muy antiguo. No recomendado para Windows 10 o 11"
        $warnings += "PROCESADOR: CPU muy antiguo. No es compatible oficialmente con Windows 11."
    }

    # -- RAM ------------------------------------------------------
    $ramType = if ($ramMods) {
        $t = ($ramMods | Select-Object -First 1).MemoryType
        switch ($t) { 26 {'DDR4'}; 34 {'DDR5'}; 24 {'DDR3'}; 21 {'DDR2'}; 20 {'DDR'}; default {'Desconocida'} }
    } else { "Desconocida" }

    $ramFreeSlots = 0; $ramMaxGB = 0
    if ($ramArray) {
        $ramMaxGB     = [math]::Round($ramArray.MaxCapacity / 1MB, 0)
        $ramFreeSlots = $ramArray.MemoryDevices - ($ramMods | Measure-Object).Count
    }

    $maxScore += 25
    $ramStatus = ""; $ramDetail = ""; $ramSlotNote = ""
    if ($totalRamGB -ge 16) {
        $score += 25; $ramStatus = "BIEN"
        $ramDetail = "Suficiente para uso diario, oficina, navegacion y multitarea"
    } elseif ($totalRamGB -ge 8) {
        $score += 18; $ramStatus = "REGULAR"
        $ramDetail = "Funciona, pero puede ir lento con varios programas abiertos"
        $upgrades += "RAM: Tienes $totalRamGB GB. Ampliar a 16 GB mejoraria notablemente la velocidad. Costo aproximado: `$25.000 - `$50.000 CLP."
    } elseif ($totalRamGB -ge 4) {
        $score += 8; $ramStatus = "MEJORAR"
        $ramDetail = "Muy poca RAM para el uso actual. Lentitud frecuente"
        $upgrades += "RAM: Solo $totalRamGB GB es poco para Windows 10/11. Ampliar a 8-16 GB es la mejora mas economica y efectiva. Costo aproximado: `$15.000 - `$40.000 CLP."
    } else {
        $ramStatus = "CRITICO"
        $ramDetail = "Insuficiente para cualquier version de Windows moderna"
        $warnings += "RAM: Solo $totalRamGB GB. El equipo apenas puede funcionar con Windows. Necesita mas RAM urgentemente."
    }

    if ($ramFreeSlots -gt 0) {
        $ramSlotNote = "Tienes $ramFreeSlots slot(s) libre(s). Puedes agregar mas RAM sin reemplazar la actual."
    } else {
        $ramSlotNote = "Todos los slots ocupados. Para ampliar RAM debes reemplazar los modulos actuales."
    }

    if ($ramType -eq 'DDR2' -or $ramType -eq 'DDR') {
        $warnings += "RAM: Tipo $ramType muy antigua. Probablemente el equipo completo debe ser reemplazado."
    } elseif ($ramType -eq 'DDR3') {
        $upgrades += "RAM: Tienes DDR3, tecnologia de 2007. Si cambias de placa madre podrias usar DDR4/DDR5 mucho mas rapida."
    }

    # -- DISCO ----------------------------------------------------
    $hasHDD  = $disks | Where-Object { $_.MediaType -eq 'HDD' }
    $hasSSD  = $disks | Where-Object { $_.MediaType -eq 'SSD' -and $_.BusType -ne 'NVMe' }
    $hasNVMe = $disks | Where-Object { $_.BusType -eq 'NVMe' }

    $maxScore += 25
    $diskStatus = ""; $diskDetail = ""; $diskType = ""
    if ($hasNVMe) {
        $score += 25; $diskStatus = "BIEN"; $diskType = "NVMe SSD"
        $diskDetail = "El tipo de disco mas rapido disponible. Excelente rendimiento"
    } elseif ($hasSSD) {
        $score += 20; $diskStatus = "BIEN"; $diskType = "SSD SATA"
        $diskDetail = "Disco rapido. El equipo enciende y responde bien"
    } elseif ($hasHDD -and $disks.Count -gt 1) {
        $score += 12; $diskStatus = "REGULAR"; $diskType = "HDD + otro disco"
        $diskDetail = "El HDD es lento. Agrega un SSD para el sistema operativo"
        $upgrades += "DISCO: Tienes un HDD como disco principal. Cambiarlo por un SSD es la mejora mas notable que puedes hacer (3-5x mas rapido). Costo: `$30.000 - `$65.000 CLP."
    } elseif ($hasHDD) {
        $score += 5; $diskStatus = "MEJORAR"; $diskType = "HDD - Disco duro mecanico"
        $diskDetail = "HDD es 5x mas lento que un SSD. Causa lentitud al iniciar y abrir programas"
        $upgrades += "DISCO: Solo tienes un HDD (disco duro mecanico). Cambiarlo por un SSD transformaria completamente la velocidad del equipo. Costo: `$25.000 - `$55.000 CLP."
    } else {
        $score += 15; $diskStatus = "REGULAR"; $diskType = "Tipo no detectado"
        $diskDetail = "No se pudo identificar el tipo de disco"
    }

    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $null -ne $_.Used }
    $drives | ForEach-Object {
        $total = [math]::Round(($_.Used + $_.Free) / 1GB, 2)
        $pct   = if ($total -gt 0) { [math]::Round(($_.Used / ($_.Used + $_.Free)) * 100, 0) } else { 0 }
        if ($pct -gt 90) {
            $warnings += "DISCO $($_.Name): Esta al $pct% de capacidad. Libera espacio o agrega almacenamiento."
        }
    }

    # -- WINDOWS --------------------------------------------------
    $maxScore += 20
    $tpmOk      = $tpm -and $tpm.IsEnabled_InitialValue
    $sbOk       = $secureBoot -eq $true
    $isWin11    = $osName -match 'Windows 11'
    $isWin10    = $osName -match 'Windows 10'
    $win11Ready = $tpmOk -and $sbOk -and ($cpuGen -ge 8)

    $winStatus = ""; $winDetail = ""
    if ($win11Ready -and $isWin11) {
        $score += 20; $winStatus = "BIEN"
        $winDetail = "Tu equipo es compatible con Windows 11 y lo tienes instalado. Correcto."
    } elseif ($win11Ready -and $isWin10) {
        $score += 18; $winStatus = "REGULAR"
        $winDetail = "Tu equipo puede correr Windows 11. Puedes actualizar cuando quieras."
    } elseif (-not $win11Ready -and $isWin11) {
        $score += 5; $winStatus = "CRITICO"
        $winDetail = "Tienes Windows 11 en hardware no compatible. Ver recomendacion de SO abajo."
        $warnings += "SO: Tienes Windows 11 en un equipo que no cumple los requisitos oficiales. Puede tener problemas de rendimiento o actualizaciones."
    } elseif ($isWin10) {
        $score += 15; $winStatus = "BIEN"
        $winDetail = "Windows 10 es adecuado para tu equipo."
    }

    # -- PUNTUACION FINAL -----------------------------------------
    $pct     = [math]::Round(($score / $maxScore) * 100, 0)
    $verdict = if ($pct -ge 80) { "EQUIPO EN BUEN ESTADO" }
               elseif ($pct -ge 60) { "EQUIPO FUNCIONAL CON MEJORAS POSIBLES" }
               elseif ($pct -ge 40) { "EQUIPO ANTIGUO - SE RECOMIENDA ACTUALIZAR" }
               else                  { "EQUIPO MUY ANTIGUO - CONSIDERAR REEMPLAZO" }

    # -- RECOMENDACION SO -----------------------------------------
    $osRecMain = ""; $osRecDetail = ""; $osRecAlts = @()
    if ($pct -ge 75 -and $win11Ready) {
        $osRecMain   = "Windows 11 Home o Pro"
        $osRecDetail = "Tu equipo cumple todos los requisitos. Windows 11 es lo ideal."
    } elseif ($pct -ge 55) {
        $osRecMain   = "Windows 10 Pro (soporte hasta octubre 2025)"
        $osRecDetail = "Tu equipo funciona mejor con Windows 10. Considera actualizar hardware antes de pasar a Win11."
        $osRecAlts   = @(
            "Windows 10 LTSC 2021: version liviana, sin bloatware, ideal para equipos limitados",
            "Linux Mint (Cinnamon): gratuito, muy liviano, interfaz similar a Windows, ideal si solo navegas y usas Office"
        )
    } elseif ($pct -ge 35) {
        $osRecMain   = "Windows 10 LTSC 2021 o Linux Mint"
        $osRecDetail = "Tu equipo es antiguo. Windows 11 no es recomendable."
        $osRecAlts   = @(
            "Windows 10 LTSC 2021: la opcion Windows mas liviana disponible",
            "Linux Mint 21 (Cinnamon): GRATIS, rapido en hardware antiguo, muy facil de usar",
            "Zorin OS Lite: disenado especialmente para equipos con pocos recursos"
        )
    } else {
        $osRecMain   = "Linux Mint Xfce o Lubuntu (o cambiar el equipo)"
        $osRecDetail = "El equipo es demasiado antiguo para Windows 10/11 de forma comoda."
        $osRecAlts   = @(
            "Linux Mint Xfce: funciona con 1-2 GB de RAM, muy liviano",
            "Lubuntu: el Linux mas liviano, para equipos con menos de 2 GB de RAM",
            "Puppy Linux: extremadamente liviano, corre desde una USB",
            "Equipo basico nuevo (~`$200.000 - `$350.000 CLP) puede ser mas economico que seguir invirtiendo en este"
        )
    }

    return @{
        CPUName      = $cpuName;      CPUStatus   = $cpuStatus;   CPUDetail   = $cpuDetail
        RAMTotal     = $totalRamGB;   RAMType     = $ramType;     RAMStatus   = $ramStatus
        RAMDetail    = $ramDetail;    RAMSlotNote = $ramSlotNote; RAMMaxGB    = $ramMaxGB
        DiskType     = $diskType;     DiskStatus  = $diskStatus;  DiskDetail  = $diskDetail
        TPMOk        = $tpmOk;        SecureBoot  = $sbOk;        OSName      = $osName
        WinStatus    = $winStatus;    WinDetail   = $winDetail;   Win11Ready  = $win11Ready
        Score        = $pct;          Verdict     = $verdict
        Upgrades     = $upgrades;     Warnings    = $warnings
        OSRecMain    = $osRecMain;    OSRecDetail = $osRecDetail; OSRecAlts   = $osRecAlts
    }
}

# ── Mostrar analisis en consola ────────────────────────────────
function Invoke-AnalisisEquipo {
    Show-Header
    Write-Section "ANALISIS DEL EQUIPO - RECOMENDACIONES" "Cyan"
    Write-Host "  Analizando tu equipo, por favor espera..." -ForegroundColor DarkGray
    Write-Host ""

    $d = Get-AnalisisEquipo

    function Show-Check {
        param([string]$Label, [string]$Value, [string]$Status, [string]$Detail = "")
        $icon  = switch ($Status) {
            'BIEN'    { "[  BIEN  ]" }; 'REGULAR' { "[ REGULAR]" }
            'MEJORAR' { "[ MEJORAR]" }; default   { "[ CRITICO]" }
        }
        $color = if ($Status -eq 'BIEN') { 'Green' } elseif ($Status -eq 'REGULAR') { 'Yellow' } else { 'Red' }
        Write-Host "  $icon " -ForegroundColor $color -NoNewline
        Write-Host "$Label" -NoNewline
        Write-Host ": $Value" -ForegroundColor Cyan
        if ($Detail) { Write-Host "            $Detail" -ForegroundColor DarkGray }
    }

    Write-Host "  PROCESADOR (CPU)" -ForegroundColor Yellow
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    Show-Check "Procesador" $d.CPUName $d.CPUStatus $d.CPUDetail
    Write-Host ""

    Write-Host "  MEMORIA RAM" -ForegroundColor Yellow
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    Show-Check "Cantidad de RAM" "$($d.RAMTotal) GB $($d.RAMType)" $d.RAMStatus $d.RAMDetail
    Write-Host "            $($d.RAMSlotNote)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  ALMACENAMIENTO (DISCO)" -ForegroundColor Yellow
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    Show-Check "Disco principal" $d.DiskType $d.DiskStatus $d.DiskDetail
    Write-Host ""

    Write-Host "  COMPATIBILIDAD CON WINDOWS" -ForegroundColor Yellow
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    Write-Host "  TPM 2.0          : " -NoNewline
    if ($d.TPMOk) { Write-Host "Presente" -ForegroundColor Green } else { Write-Host "No detectado" -ForegroundColor Red }
    Write-Host "  Secure Boot      : " -NoNewline
    if ($d.SecureBoot) { Write-Host "Habilitado" -ForegroundColor Green } else { Write-Host "Deshabilitado" -ForegroundColor Yellow }
    Write-Host "  Sistema actual   : $($d.OSName)" -ForegroundColor Cyan
    $winColor = if ($d.WinStatus -eq 'BIEN') { 'Green' } elseif ($d.WinStatus -eq 'REGULAR') { 'Yellow' } else { 'Red' }
    $winIcon  = switch ($d.WinStatus) {
        'BIEN'    { "[  BIEN  ]" }; 'REGULAR' { "[ REGULAR]" }; default { "[ CRITICO]" }
    }
    Write-Host ""; Write-Host "  $winIcon " -ForegroundColor $winColor -NoNewline
    Write-Host $d.WinDetail
    Write-Host ""

    $barFilled = [math]::Round($d.Score / 5, 0)
    $bar       = ('#' * $barFilled).PadRight(20, '-')
    $vColor    = if ($d.Score -ge 80) { 'Green' } elseif ($d.Score -ge 60) { 'Yellow' } else { 'Red' }

    Write-Host "  $('=' * 70)" -ForegroundColor DarkGray
    Write-Host "  PUNTUACION GENERAL" -ForegroundColor White
    Write-Host ""
    Write-Host "  [$bar] $($d.Score) / 100" -ForegroundColor Cyan
    Write-Host "  $($d.Verdict)" -ForegroundColor $vColor
    Write-Host ""

    if ($d.Upgrades) {
        Write-Host "  QUE PUEDES MEJORAR:" -ForegroundColor Yellow
        $d.Upgrades | ForEach-Object { Write-Host "  -> $_" }
        Write-Host ""
    }
    if ($d.Warnings) {
        Write-Host "  ADVERTENCIAS IMPORTANTES:" -ForegroundColor Red
        $d.Warnings | ForEach-Object { Write-Host "  !! $_" -ForegroundColor Red }
        Write-Host ""
    }

    Write-Host "  RECOMENDACION DE SISTEMA OPERATIVO" -ForegroundColor Yellow
    Write-Host "  $('-' * 70)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  RECOMENDADO: " -NoNewline
    Write-Host $d.OSRecMain -ForegroundColor $(if ($d.Score -ge 75) { 'Green' } else { 'Yellow' })
    Write-Host "  $($d.OSRecDetail)"
    if ($d.OSRecAlts) {
        Write-Host ""
        Write-Host "  ALTERNATIVAS:" -ForegroundColor DarkGray
        $d.OSRecAlts | ForEach-Object { Write-Host "  -> $_" }
    }

    Write-Host ""
    Write-Host "  $('=' * 70)" -ForegroundColor DarkGray
    Write-Log "Analisis de equipo ejecutado - Score: $($d.Score)/100"
}
