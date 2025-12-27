

He analizado el script `install.txt` profundamente. Aunque es un buen punto de partida, contiene varios errores lógicos, riesgos de seguridad y falta de robustez que pueden causar que la instalación falle o que el sistema quede en un estado inconsistente.

Aquí detallo los errores encontrados y sus soluciones:

### Análisis de Errores y Soluciones

1.  **Detección de Discos (Crítico):**
    *   *Error:* El comando `lsblk` usado filtra por "sd", "nvme" o "vd". Esto incluye **particiones** (ej: `sda1`, `nvme0n1p1`) en la lista de selección. Si el usuario selecciona una partición en lugar del disco, el script fallará o destruirá datos parciales.
    *   *Solución:* Usar `lsblk -d` (devices only) y filtrar específicamente por `TYPE="disk"`.

2.  **Detección de GPU (Lógica):**
    *   *Error:* Busca "amd" en todo el `lspci`. Si el usuario tiene un procesador AMD pero una gráfica NVIDIA, el script detectará "AMD" e instalará los drivers equivocados.
    *   *Solución:* Filtrar específicamente líneas que contengan "VGA" o "3D controller" antes de buscar el fabricante.

3.  **Configuración WiFi (Fragilidad):**
    *   *Error:* Hardcodea el nombre de la interfaz como `wlan0`. Los sistemas modernos usan nombres predictivos (ej: `wlp3s0`), lo que rompe los comandos de `iwctl`.
    *   *Solución:* Detectar dinámicamente el nombre de la interfaz inalámbrica antes de dar instrucciones.

4.  **Falta de Actualización de Llaves (Pacman):**
    *   *Error:* El script ejecuta `pacman -Syy` sin actualizar primero el paquete `archlinux-keyring`. Esto es una causa muy común de error en instalaciones frescas ("Invalid or corrupted package").
    *   *Solución:* Forzar la actualización de `archlinux-keyring` antes de instalar el sistema base.

5.  **Generación de Locale (Regex inseguro):**
    *   *Error:* El comando `sed` para descomentar el locale es demasiado genérico y podría romper el archivo si la variable no coincide exactamente.
    *   *Solución:* Usar un `sed` más robusto o simplemente eliminar los comentarios específicos de las líneas deseadas de forma segura.

6.  **Post-instalación (Ámbito de variables):**
    *   *Error:* En el script generado (`post_install.sh`), se usa la variable `$USER`. Si el usuario ejecuta el script en un entorno no estándar, esta variable podría no estar definida correctamente para el usuario actual.
    *   *Solución:* Usar `$(whoami)` dentro del script generado para garantizar que se obtiene el usuario correcto.

7.  **Configuración de GRUB (Os-prober):**
    *   *Error:* Instala `os-prober` pero no habilita su uso en `/etc/default/grub`. Las versiones recientes de GRUB lo tienen deshabilitado por defecto.
    *   *Solución:* Agregar `GRUB_DISABLE_OS_PROBER=false` al archivo de configuración.

---

### Script Corregido

A continuación presento el script completo con todas las correcciones integradas y comentarios en español indicando los cambios.

```bash
#!/bin/bash
# Arch Linux Auto Installer with KDE Plasma Minimal
# Improved version with network error handling & bug fixes

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DISK=""
HOSTNAME="archlinux"
USERNAME=""
USER_PASSWORD=""
ROOT_PASSWORD=""
TIMEZONE=""
KEYMAP="us"
LOCALE="en_US.UTF-8"
SWAP_SIZE="8"
IS_UEFI=0
CPU_VENDOR=""
GPU_VENDOR=""
LOG_FILE="/tmp/arch_install.log"

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Check internet connection
check_internet() {
    log "INFO" "Verificando conexión a Internet..."

    # Try multiple methods to check internet
    if ping -c 3 -W 5 8.8.8.8 &>/dev/null || \
       ping -c 3 -W 5 archlinux.org &>/dev/null || \
       curl -s --connect-timeout 10 https://archlinux.org &>/dev/null; then
        log "INFO" "Conexión a Internet verificada"
        return 0
    else
        log "ERROR" "No hay conexión a Internet"
        return 1
    fi
}

# Setup network if needed
setup_network() {
    log "INFO" "Configurando conexión de red..."

    # Check if network is already up
    if check_internet; then
        return 0
    fi

    echo -e "${YELLOW}Configuración de red requerida${NC}"
    echo -e "Selecciona tu tipo de conexión:"
    echo "1) Ethernet cableada (DHCP)"
    echo "2) WiFi"
    echo "3) Ya tengo conexión"
    read -p "Opción [1-3]: " net_choice

    case $net_choice in
        1)
            log "INFO" "Configurando Ethernet..."
            # FIX: Detectar interfaz ethernet dinámicamente (en*)
            ETH_DEV=$(ip link | grep -E '^[0-9]+: en' | awk '{print $2}' | cut -d: -f1 | head -1)
            if [[ -n "$ETH_DEV" ]]; then
                ip link set "$ETH_DEV" up
                dhcpcd "$ETH_DEV" 2>/dev/null || systemctl start dhcpcd@"$ETH_DEV" 2>/dev/null || true
            else
                log "WARN" "No se detectó interfaz Ethernet activa"
            fi
            sleep 5
            ;;
        2)
            log "INFO" "Configurando WiFi..."
            # FIX: Detectar interfaz wifi dinámicamente (wl*)
            WIFI_DEV=$(ip link | grep -E '^[0-9]+: wl' | awk '{print $2}' | cut -d: -f1 | head -1)
            if [[ -z "$WIFI_DEV" ]]; then
                log "WARN" "No se detectó interfaz WiFi. Verifica que tengas tarjeta inalámbrica."
            fi
            
            echo -e "${YELLOW}Usa iwctl para conectar WiFi:${NC}"
            echo "Comandos útiles:"
            if [[ -n "$WIFI_DEV" ]]; then
                echo "  iwctl station $WIFI_DEV scan"
                echo "  iwctl station $WIFI_DEV get-networks"
                echo "  iwctl station $WIFI_DEV connect SSID"
            else
                echo "  iwctl device list" 
                echo "  (Usa el nombre de dispositivo que aparezca)"
            fi
            echo -e "${BLUE}Presiona Enter cuando tengas conexión...${NC}"
            read
            ;;
        3)
            log "INFO" "Asumiendo conexión existente"
            ;;
    esac

    # Test connection again
    if ! check_internet; then
        echo -e "${RED}ERROR: No se pudo establecer conexión a Internet${NC}"
        echo -e "${YELLOW}Configura DNS temporalmente:${NC}"
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf

        if ! check_internet; then
            log "ERROR" "Imposible conectar a Internet. Verifica tu conexión."
            exit 1
        fi
    fi
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Este script debe ejecutarse como root. Usa: sudo bash $0${NC}"
        exit 1
    fi
}

# Detect system specifications
detect_system() {
    log "INFO" "Detectando especificaciones del sistema..."

    # Detect UEFI/BIOS
    if [[ -d /sys/firmware/efi/efivars ]]; then
        IS_UEFI=1
        log "INFO" "Sistema UEFI detectado"
    else
        IS_UEFI=0
        log "INFO" "Sistema BIOS detectado"
    fi

    # Detect CPU vendor
    if grep -qm1 "GenuineIntel" /proc/cpuinfo; then
        CPU_VENDOR="intel"
        log "INFO" "CPU Intel detectado"
    elif grep -qm1 "AuthenticAMD" /proc/cpuinfo; then
        CPU_VENDOR="amd"
        log "INFO" "CPU AMD detectado"
    else
        CPU_VENDOR="unknown"
        log "WARN" "Vendor de CPU no reconocido"
    fi

    # FIX: Detect GPU vendor filtrando solo controladores VGA/3D para evitar falsos positivos de CPU
    if lspci | grep -iE "VGA|3D" | grep -qi "nvidia"; then
        GPU_VENDOR="nvidia"
        log "INFO" "GPU NVIDIA detectada"
    elif lspci | grep -iE "VGA|3D" | grep -qi "amd"; then
        GPU_VENDOR="amd"
        log "INFO" "GPU AMD detectada"
    elif lspci | grep -iE "VGA|3D" | grep -qi "intel"; then
        GPU_VENDOR="intel"
        log "INFO" "GPU Intel detectada"
    else
        GPU_VENDOR="unknown"
        log "WARN" "Vendor de GPU no reconocido"
    fi

    # FIX: Mostrar solo discos, no particiones
    log "INFO" "Discos disponibles:"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | grep -E "disk"
}

# Get user input
get_user_input() {
    echo -e "${GREEN}=== Configuración de Instalación ===${NC}"

    # Select disk
    echo -e "\n${YELLOW}Discos disponibles:${NC}"
    # FIX: Filtrar solo discos nuevamente para la selección
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | grep "disk"
    read -p "Ingresa el nombre del disco para instalar (ej: sda, nvme0n1): " DISK
    DISK="/dev/${DISK}"

    # Validate disk exists
    if [[ ! -b "$DISK" ]]; then
        log "ERROR" "El disco $DISK no existe"
        exit 1
    fi

    # Hostname
    read -p "Nombre del equipo [archlinux]: " input
    HOSTNAME="${input:-archlinux}"

    # Username
    while [[ -z "$USERNAME" ]]; do
        read -p "Nombre de usuario: " USERNAME
        if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo -e "${RED}Nombre de usuario inválido. Solo letras minúsculas, números, '-' y '_'${NC}"
            USERNAME=""
        fi
    done

    # Passwords
    while [[ -z "$ROOT_PASSWORD" ]]; do
        echo -n "Contraseña para root: "
        read -s ROOT_PASSWORD
        echo
        if [[ ${#ROOT_PASSWORD} -lt 6 ]]; then
            echo -e "${RED}La contraseña debe tener al menos 6 caracteres${NC}"
            ROOT_PASSWORD=""
        fi
    done

    while [[ -z "$USER_PASSWORD" ]]; do
        echo -n "Contraseña para $USERNAME: "
        read -s USER_PASSWORD
        echo
        if [[ ${#USER_PASSWORD} -lt 6 ]]; then
            echo -e "${RED}La contraseña debe tener al menos 6 caracteres${NC}"
            USER_PASSWORD=""
        fi
    done

    # Timezone
    echo -e "\n${YELLOW}Zonas horarias comunes:${NC}"
    echo "1) America/Mexico_City"
    echo "2) America/New_York"
    echo "3) Europe/Madrid"
    echo "4) America/Santiago"
    echo "5) America/Buenos_Aires"
    echo "6) Otra (ingresar manualmente)"
    read -p "Selecciona [1-6]: " tz_choice

    case $tz_choice in
        1) TIMEZONE="America/Mexico_City" ;;
        2) TIMEZONE="America/New_York" ;;
        3) TIMEZONE="Europe/Madrid" ;;
        4) TIMEZONE="America/Santiago" ;;
        5) TIMEZONE="America/Buenos_Aires" ;;
        6)
            read -p "Ingresa zona horaria (ej: America/Lima): " TIMEZONE
            [[ -z "$TIMEZONE" ]] && TIMEZONE="America/Mexico_City"
            ;;
        *) TIMEZONE="America/Mexico_City" ;;
    esac

    # Swap size
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_total_gb=$((mem_total / 1024 / 1024))
    recommended_swap=$((mem_total_gb * 2))

    read -p "Tamaño de swap en GB [recomendado: $recommended_swap]: " input
    SWAP_SIZE="${input:-$recommended_swap}"

    # Confirmation
    echo -e "\n${RED}=== RESUMEN DE INSTALACIÓN ===${NC}"
    echo "Disco: $DISK"
    echo "Hostname: $HOSTNAME"
    echo "Usuario: $USERNAME"
    echo "Zona horaria: $TIMEZONE"
    echo "Swap: ${SWAP_SIZE}GB"
    echo "Tipo de sistema: $([ $IS_UEFI -eq 1 ] && echo "UEFI" || echo "BIOS")"
    echo "CPU: $CPU_VENDOR"
    echo "GPU: $GPU_VENDOR"
    echo -e "\n${RED}ADVERTENCIA: Todos los datos en $DISK serán destruidos.${NC}"

    read -p "¿Continuar con la instalación? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        log "INFO" "Instalación cancelada por el usuario"
        exit 0
    fi
}

# Update mirrors with fallback
update_mirrors() {
    log "INFO" "Actualizando lista de mirrors..."

    # Backup original mirrorlist
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup 2>/dev/null || true

    # Try reflector with timeout and fallback
    if command -v reflector &>/dev/null; then
        # Try with 10 second timeout
        timeout 10 reflector \
            --verbose \
            --latest 10 \
            --protocol https \
            --sort rate \
            --save /etc/pacman.d/mirrorlist 2>>"$LOG_FILE" && {
            log "INFO" "Mirrorlist actualizado con reflector"
            return 0
        } || {
            log "WARN" "Reflector falló, usando mirrors alternativos"
        }
    fi

    # Fallback: Use known good mirrors
    log "INFO" "Usando mirrors predefinidos..."
    cat > /etc/pacman.d/mirrorlist << 'MIRRORLIST'
## Arch Linux repository mirrorlist
## Generated on $(date)
## Fallback mirrors

# Worldwide
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirrors.kernel.org/archlinux/$repo/os/$arch
Server = https://archlinux.mirror.liteserver.nl/$repo/os/$arch
Server = https://mirror.f4st.host/archlinux/$repo/os/$arch

# North America
Server = https://mirror.csclub.uwaterloo.ca/archlinux/$repo/os/$arch
Server = https://mirror.leaseweb.com/archlinux/$repo/os/$arch

# Europe
Server = https://archlinux.mirror.wearetriple.com/$repo/os/$arch
Server = https://mirror.nl.leaseweb.net/archlinux/$repo/os/$arch

# Asia
Server = https://mirror.0x.sg/archlinux/$repo/os/$arch
MIRRORLIST

    log "INFO" "Mirrorlist configurado con servidores alternativos"
}

# Partitioning
partition_disk() {
    log "INFO" "Creando particiones en $DISK..."

    # Unmount any mounted partitions
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # Clear existing partition table
    log "INFO" "Limpiando tabla de particiones..."
    wipefs -a -f "$DISK" 2>/dev/null || true
    sgdisk -Z "$DISK" 2>/dev/null || dd if=/dev/zero of="$DISK" bs=1M count=100 2>/dev/null
    partprobe "$DISK"
    sleep 2

    if [[ $IS_UEFI -eq 1 ]]; then
        # UEFI partitioning
        log "INFO" "Creando tabla de particiones GPT para UEFI"

        # Create partitions
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$DISK"
        sgdisk -n 2:0:+${SWAP_SIZE}G -t 2:8200 -c 2:"Linux swap" "$DISK"
        sgdisk -n 3:0:0 -t 3:8304 -c 3:"Linux root" "$DISK"

        # Set partition variables
        if [[ "$DISK" =~ "nvme" ]]; then
            EFI_PART="${DISK}p1"
            SWAP_PART="${DISK}p2"
            ROOT_PART="${DISK}p3"
        else
            EFI_PART="${DISK}1"
            SWAP_PART="${DISK}2"
            ROOT_PART="${DISK}3"
        fi

        # Format partitions
        log "INFO" "Formateando particiones..."
        mkfs.fat -F32 "$EFI_PART" 2>>"$LOG_FILE"
        mkswap "$SWAP_PART" 2>>"$LOG_FILE"
        mkfs.ext4 -F "$ROOT_PART" 2>>"$LOG_FILE"

        # Mount partitions
        swapon "$SWAP_PART"
        mount "$ROOT_PART" /mnt
        mkdir -p /mnt/boot/efi
        mount "$EFI_PART" /mnt/boot/efi
    else
        # BIOS partitioning
        log "INFO" "Creando tabla de particiones MBR para BIOS"

        # Create partitions using fdisk
        # o:nueva tabla, n:particion primaria, p:primaria, 1:id, enter:default sector, +512M:size
        # n:p:2:enter:+SWAP, t:2:82(swap), n:p:3:enter:enter(root)
        echo -e "o\nn\np\n1\n\n+512M\nn\np\n2\n\n+${SWAP_SIZE}G\nt\n2\n82\nn\np\n3\n\n\nw" | fdisk -W always "$DISK"

        # Set partition variables
        # La lógica de sufijo 'p' para nvme es correcta
        if [[ "$DISK" =~ "nvme" ]]; then
            BOOT_PART="${DISK}p1"
            SWAP_PART="${DISK}p2"
            ROOT_PART="${DISK}p3"
        else
            BOOT_PART="${DISK}1"
            SWAP_PART="${DISK}2"
            ROOT_PART="${DISK}3"
        fi

        # Format partitions
        log "INFO" "Formateando particiones..."
        mkfs.ext4 -F "$BOOT_PART" 2>>"$LOG_FILE"
        mkswap "$SWAP_PART" 2>>"$LOG_FILE"
        mkfs.ext4 -F "$ROOT_PART" 2>>"$LOG_FILE"

        # Mount partitions
        swapon "$SWAP_PART"
        mount "$ROOT_PART" /mnt
        mkdir -p /mnt/boot
        mount "$BOOT_PART" /mnt/boot
    fi

    log "INFO" "Particionamiento completado"
}

# Install base system
install_base() {
    log "INFO" "Instalando sistema base..."

    # Update mirrorlist with fallback
    update_mirrors

    # FIX: Actualizar archlinux-keyring antes de sync para evitar errores de firma
    log "INFO" "Actualizando llaves Pacman..."
    pacman -Sy --noconfirm archlinux-keyring 2>>"$LOG_FILE" || log "WARN" "Fallo al actualizar keyring (puede no ser crítico)"

    # Update pacman database with retry
    log "INFO" "Actualizando base de datos de pacman..."
    for i in {1..3}; do
        if pacman -Syy --noconfirm 2>>"$LOG_FILE"; then
            log "INFO" "Base de datos actualizada en intento $i"
            break
        else
            log "WARN" "Intento $i fallado, reintentando..."
            sleep 2
            if [[ $i -eq 3 ]]; then
                log "ERROR" "No se pudo actualizar la base de datos"
                exit 1
            fi
        fi
    done

    # Install base packages
    log "INFO" "Instalando paquetes base..."
    if ! pacstrap /mnt base base-devel linux linux-firmware 2>>"$LOG_FILE"; then
        log "ERROR" "Falló la instalación base. Verificando dependencias..."

        # Try minimal installation first
        pacstrap /mnt base linux linux-firmware 2>>"$LOG_FILE" || {
            log "ERROR" "Instalación mínima fallada. Verifica conexión y mirrors."
            exit 1
        }

        # Install base-devel later
        arch-chroot /mnt pacman -S --noconfirm base-devel 2>>"$LOG_FILE"
    fi

    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab 2>>"$LOG_FILE"

    log "INFO" "Sistema base instalado"
}

# Configure system (chroot script)
configure_system() {
    log "INFO" "Configurando sistema..."

    # Create chroot script
    cat > /mnt/configure_system.sh << 'CHROOT_EOF'
#!/bin/bash
set -euo pipefail

log() {
    echo "[CHROOT] $1: $2"
}

# Read variables
HOSTNAME="$1"
USERNAME="$2"
TIMEZONE="$3"
LOCALE="$4"
KEYMAP="$5"
IS_UEFI="$6"
CPU_VENDOR="$7"
GPU_VENDOR="$8"
ROOT_PASSWORD="$9"
USER_PASSWORD="${10}"
DISK_DEVICE="${11}"

# Setup logging
exec 2>>/install.log

# Set timezone
log "INFO" "Configurando zona horaria: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"
hwclock --systohc

# Localization
log "INFO" "Configurando localización"
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
# FIX: Usar sed con regex más segura o reemplazo directo. 
# Descomentamos específicamente la línea que coincide con el locale
sed -i "s/^#\($LOCALE\)/\1/" /etc/locale.gen
locale-gen

# Network configuration
log "INFO" "Configurando red"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS_EOF

# Set root password
log "INFO" "Configurando contraseña de root"
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user
log "INFO" "Creando usuario: $USERNAME"
useradd -m -G wheel,audio,video,storage -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudoers
log "INFO" "Configurando sudoers"
# Eliminar línea duplicada si existe al re-ejecutar (aunque este script corre una vez)
sed -i '/^%wheel ALL=(ALL) ALL/d' /etc/sudoers 2>/dev/null || true
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults timestamp_timeout=30" >> /etc/sudoers

# Install essential packages
log "INFO" "Instalando paquetes esenciales"
pacman -Sy --noconfirm --needed \
    networkmanager \
    grub \
    efibootmgr \
    dosfstools \
    os-prober \
    git \
    curl \
    wget \
    nano \
    vim \
    htop \
    neofetch \
    man-db \
    man-pages \
    texinfo 2>/dev/null

# Install CPU microcode
log "INFO" "Instalando microcódigo para CPU: $CPU_VENDOR"
if [[ "$CPU_VENDOR" == "intel" ]]; then
    pacman -S --noconfirm intel-ucode 2>/dev/null
elif [[ "$CPU_VENDOR" == "amd" ]]; then
    pacman -S --noconfirm amd-ucode 2>/dev/null
fi

# Install GPU drivers
log "INFO" "Instalando drivers para GPU: $GPU_VENDOR"
case "$GPU_VENDOR" in
    "nvidia")
        pacman -S --noconfirm nvidia nvidia-utils nvidia-settings 2>/dev/null
        ;;
    "amd")
        pacman -S --noconfirm mesa vulkan-radeon xf86-video-amdgpu 2>/dev/null
        ;;
    "intel")
        pacman -S --noconfirm mesa vulkan-intel xf86-video-intel 2>/dev/null
        ;;
    *)
        pacman -S --noconfirm mesa 2>/dev/null
        ;;
esac

# Install KDE Plasma Minimal
log "INFO" "Instalando KDE Plasma Minimal"
pacman -S --noconfirm --needed \
    plasma-desktop \
    plasma-nm \
    plasma-pa \
    dolphin \
    konsole \
    kate \
    kdegraphics-thumbnailers \
    ffmpegthumbs \
    sddm \
    sddm-kcm \
    ark \
    spectacle \
    okular \
    print-manager \
    cups \
    cups-pdf \
    firefox \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    ttf-dejavu \
    ttf-liberation \
    ttf-ubuntu-font-family \
    pulseaudio \
    pulseaudio-alsa \
    pavucontrol \
    papirus-icon-theme \
    breeze-gtk \
    xdg-user-dirs \
    xdg-utils 2>/dev/null

# Enable services
log "INFO" "Habilitando servicios"
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable cups

# Install GRUB
log "INFO" "Instalando GRUB"
# FIX: Habilitar os-prober para detectar Windows si existe dual boot
if ! grep -q "GRUB_DISABLE_OS_PROBER=false" /etc/default/grub; then
    echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
fi

if [[ "$IS_UEFI" -eq 1 ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck 2>/dev/null
else
    grub-install --target=i386-pc "$DISK_DEVICE" --recheck 2>/dev/null
fi

# Configure GRUB
log "INFO" "Configurando GRUB"
if [[ "$CPU_VENDOR" == "intel" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&intel_iommu=on /' /etc/default/grub
elif [[ "$CPU_VENDOR" == "amd" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&amd_iommu=on /' /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null

# Create user directories
log "INFO" "Creando directorios de usuario"
sudo -u "$USERNAME" xdg-user-dirs-update

# Configure audio
log "INFO" "Configurando audio"
echo "load-module module-switch-on-connect" >> /etc/pulse/default.pa

# Clean up
log "INFO" "Limpiando instalación"
rm -f /configure_system.sh

log "INFO" "Configuración completada exitosamente"
CHROOT_EOF

    # Make script executable
    chmod +x /mnt/configure_system.sh

    # Get disk device without partition number for BIOS install
    DISK_DEVICE=$(echo "$DISK" | sed 's/[0-9]*$//')

    # Run configuration in chroot
    log "INFO" "Ejecutando configuración en chroot..."
    arch-chroot /mnt /configure_system.sh \
        "$HOSTNAME" \
        "$USERNAME" \
        "$TIMEZONE" \
        "$LOCALE" \
        "$KEYMAP" \
        "$IS_UEFI" \
        "$CPU_VENDOR" \
        "$GPU_VENDOR" \
        "$ROOT_PASSWORD" \
        "$USER_PASSWORD" \
        "$DISK_DEVICE" 2>>"$LOG_FILE"

    log "INFO" "Configuración completada"
}

# Post-installation
post_install() {
    log "INFO" "Realizando configuración post-instalación..."

    # Create post-install script for user
    cat > /mnt/home/$USERNAME/post_install.sh << 'POST_EOF'
#!/bin/bash
# FIX: Usar whoami para asegurar el usuario correcto
CURRENT_USER=$(whoami)
echo "=== Configuración Post-Instalación ==="
echo "Usuario: $CURRENT_USER"
echo

# Create directories
mkdir -p ~/{Downloads,Documents,Pictures,Music,Videos,Desktop,Public,Templates}

# Install yay (AUR helper) if not present
if ! command -v yay &> /dev/null; then
    echo "Instalando yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    rm -rf /tmp/yay
fi

# Ask about additional software
read -p "¿Instalar software adicional? (s/N): " install_extra
if [[ "$install_extra" =~ ^[Ss]$ ]]; then
    echo "Opciones de software:"
    echo "1) Oficina (LibreOffice)"
    echo "2) Multimedia (VLC, GIMP)"
    echo "3) Desarrollo (VSCode, Docker)"
    echo "4) Todo lo anterior"
    read -p "Selecciona opción [1-4]: " software_choice

    case $software_choice in
        1)
            sudo pacman -S --noconfirm libreoffice-fresh
            ;;
        2)
            sudo pacman -S --noconfirm vlc gimp
            ;;
        3)
            sudo pacman -S --noconfirm code docker docker-compose
            sudo systemctl enable docker
            # FIX: Usar variable CURRENT_USER en lugar de $USER (que podría no estar seteada)
            sudo usermod -aG docker $CURRENT_USER
            ;;
        4)
            sudo pacman -S --noconfirm libreoffice-fresh vlc gimp code docker docker-compose
            sudo systemctl enable docker
            sudo usermod -aG docker $CURRENT_USER
            ;;
    esac
fi

echo "=== Configuración recomendada ==="
echo "1. Configura KDE Plasma desde 'System Settings'"
echo "2. Configura NetworkManager para tu red WiFi"
echo "3. Actualiza el sistema regularmente: sudo pacman -Syu"
echo "4. Instala AUR packages con: yay -S package-name"
echo
echo "Para reiniciar: sudo reboot"
POST_EOF

    chmod +x /mnt/home/$USERNAME/post_install.sh
    chown $USERNAME:$USERNAME /mnt/home/$USERNAME/post_install.sh

    log "INFO" "Instalación completada exitosamente!"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Instalación completada exitosamente!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Hostname: $HOSTNAME"
    echo -e "Usuario: $USERNAME"
    echo -e "Contraseña: ********"
    echo -e "Timezone: $TIMEZONE"
    echo -e "Tipo de sistema: $([ $IS_UEFI -eq 1 ] && echo "UEFI" || echo "BIOS")"
    echo -e "CPU: $CPU_VENDOR"
    echo -e "GPU: $GPU_VENDOR"
    echo -e "Log de instalación: $LOG_FILE"
    echo -e "\n${YELLOW}Para configuraciones adicionales, ejecuta:${NC}"
    echo -e "sudo -u $USERNAME /home/$USERNAME/post_install.sh"
    echo -e "\n${YELLOW}Para reiniciar:${NC}"
    echo -e "1. umount -R /mnt"
    echo -e "2. reboot"
}

# Cleanup function
cleanup() {
    log "INFO" "Realizando limpieza..."

    # Unmount partitions
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # Remove temporary files
    rm -f /mnt/configure_system.sh 2>/dev/null || true

    log "INFO" "Limpieza completada"
}

# Main function with error handling
main() {
    trap 'echo -e "${RED}Error en línea $LINENO. Ver log: $LOG_FILE${NC}"; cleanup; exit 1' ERR

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Arch Linux Auto Installer${NC}"
    echo -e "${BLUE}   con KDE Plasma Minimal${NC}"
    echo -e "${BLUE}   (Versión corregida y robusta)${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Create log file
    > "$LOG_FILE"

    # Check root
    check_root

    # Setup network
    setup_network

    # Detect system
    detect_system

    # Get user input
    get_user_input

    # Partition disk
    partition_disk

    # Install base system
    install_base

    # Configure system
    configure_system

    # Post-installation
    post_install

    # Cleanup
    cleanup

    # Final message
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Instalación finalizada!${NC}"
    echo -e "${GREEN}Log guardado en: $LOG_FILE${NC}"
    echo -e "\n${YELLOW}Pasos finales:${NC}"
    echo -e "1. Desmontar: umount -R /mnt"
    echo -e "2. Reiniciar: reboot"
    echo -e "3. Retirar medio de instalación"
    echo -e "4. Iniciar sesión con usuario: $USERNAME"
    echo -e "${BLUE}========================================${NC}"
}

# Run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```
