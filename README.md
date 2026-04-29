# SoportePRO

Herramienta de soporte técnico profesional para Windows. Se ejecuta con un solo comando, no requiere instalación y elimina sus archivos automáticamente al cerrar.

## Ejecución rápida

```powershell
iwr -useb https://raw.githubusercontent.com/brayam-marre/SoportePRO/main/install.ps1 | iex
```

> Requiere PowerShell 5.1+ y ejecución como Administrador.

---

## Módulos

### Soporte TI

| Módulo | Funciones |
|---|---|
| **Diagnóstico** | SO, CPU, RAM, GPU, temperatura, discos, eventos críticos |
| **Limpieza** | Temporales, caché, Papelera, Windows Update, logs antiguos |
| **Reparación** | SFC, DISM, chkdsk, reset de red, reparación MBR/BCD, limpieza WU |
| **Software** | Top procesos, programas instalados, servicios críticos, startup, kill process |
| **Usuarios** | Crear/deshabilitar cuentas, reset de contraseña, grupos, sesiones activas |
| **Hardware** | Salud de disco (SMART), información de batería, benchmark CPU/RAM/disco |
| **Sistema** | Analizador de BSOD, puntos de restauración, activación de Windows |

### Redes y Ciberseguridad

| Módulo | Funciones |
|---|---|
| **Redes** | Adaptadores, IPs públicas/privadas, ping, traceroute, puertos, WiFi, NSLookup |
| **Ciberseguridad** | Estado AV/Firewall/UAC/BitLocker, conexiones sospechosas, procesos sin firma, eventos de seguridad, contraseñas WiFi, SMBv1 |
| **Escaner** | Escaner LAN con ping sweep + port scan, tráfico por proceso, verificador de hashes (MD5/SHA1/SHA256), baseline CIS |

### Reportes

| Función | Descripción |
|---|---|
| **Reporte TXT + HTML** | Genera un reporte completo del sistema en el Escritorio |
| **Modo Mantenimiento** | Ejecuta diagnóstico + limpieza + reparación + red + baseline + reporte en secuencia automática |

---

## Características

- Sin instalación — descarga, ejecuta y se autoeliminan los archivos al cerrar
- Solicita privilegios de administrador automáticamente
- Menú interactivo organizado por categorías
- Genera reportes en TXT y HTML con diseño visual
- Log automático de todas las acciones con timestamp
- Compatible con Windows 10 y Windows 11

---

## Estructura del proyecto

```
SoportePRO/
├── install.ps1               <- Instalador one-liner
├── SoportePRO.ps1            <- Script principal y menú
└── modules/
    ├── diagnostico.ps1
    ├── limpieza.ps1
    ├── reparacion.ps1
    ├── software.ps1
    ├── usuarios.ps1
    ├── hardware.ps1
    ├── sistema.ps1
    ├── red.ps1
    ├── seguridad.ps1
    ├── scanner.ps1
    └── reporte.ps1
```

---

## Uso ético

Esta herramienta está diseñada para administradores de sistemas y técnicos de soporte TI. Úsala únicamente en equipos sobre los que tengas autorización.
