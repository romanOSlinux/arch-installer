#!/usr/bin/env bash
# Arch Linux Installer - KDE Plasma Argentina
# Script completo para instalación automatizada
# Licencia: MIT

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

# Variables regionales para Argentina
readonly COUNTRY="Argentina"
readonly LOCALE="es_AR.UTF-8 UTF-8"
readonly KEYMAP="la-latam"
readonly TIMEZONE="America/Argentina/Buenos_Aires"
readonly LANG="es_AR.UTF-8"
readonly KEYBOARD_LAYOUT="la-latam"

# Variables del sistema (modificables por usuario)
TARGET_DISK=""
HOSTNAME="arch-argentina"
USERNAME="argentino"
ROOT_PASSWORD=""
USER_PASSWORD=""
SWAP_PERCENTAGE=50  # Porcentaje de RAM para zram

# Paquetes base
readonly BASE_PACKAGES=(
    base base-devel linux linux-firmware
    btrfs-progs sudo nano vim bash-completion
    networkmanager wpa_supplicant dialog
    git curl wget openssh rsync archlinux-keyring
    man-db man-pages texinfo
)

# Paquetes KDE Plasma mínimo
readonly KDE_PACKAGES=(
    plasma-meta
    plasma-wayland-session
    kde-applications-meta
    sddm
    dolphin
    konsole
    kate
    spectacle
    gwenview
    ark
    kcalc
    print-manager
    sddm-kcm
    kde-gtk-config
    breeze-gtk
    xdg-desktop-portal-kde
    xdg-utils
    pipewire pipewire-pulse pipewire-alsa wireplumber
)

# Utilidades adicionales
readonly UTILITIES=(
    firefox
    htop
    neofetch
    gparted
    libreoffice-still
    vlc
    gimp
    cups
    hplip
    ghostscript
    gsfonts
    ttf-dejavu
    ttf-liberation
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    ttf-roboto
    papirus-icon-theme
    breeze-icons
)

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

# Funciones de logging
print_msg() {
    echo -e "${GREEN}[*]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_err() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_step() {
    echo -e "\n${BLUE}==>${NC} ${BOLD}$1${NC}"
}

print_substep() {
    echo -e "${CYAN}  ->${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_fail() {
    echo -e "${RED}[✗]${NC} $1"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ============================================================================
# FUNCIONES DE DETECCIÓN
# ============================================================================

detect_boot_mode() {
    if [[ -d /sys/firmware/efi/efivars ]]; then
        echo "uefi"
    else
        echo "bios"
    fi
}

detect_cpu() {
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        echo "intel"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        echo "amd"
    else
        echo "unknown"
    fi
}

detect_gpu() {
    if lspci | grep -qi "nvidia"; then
        echo "nvidia"
    elif lspci | grep -qi "amd" | grep -qi "radeon"; then
        echo "amd"
    elif lspci | grep -qi "intel" | grep -qi "graphics"; then
        echo "intel"
    else
        echo "unknown"
    fi
}

get_ram_size() {
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo $((mem_kb / 1024))
}

# ============================================================================
# FUNCIONES DE VALIDACIÓN
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_err "Este script debe ejecutarse como root"
        exit 1
    fi
}

check_internet() {
    print_substep "Verificando conexión a internet..."
    
    if ! ping -c 1 -W 2 archlinux.org &> /dev/null; then
        if ! ping -c 1 -W 2 google.com &> /dev/null; then
            print_err "No hay conexión a internet"
            print_msg "Por favor, conéctate a internet antes de continuar"
            
            # Intentar conexión automática
            if command -v dhcpcd &> /dev/null; then
                print_msg "Intentando conexión automática con dhcpcd..."
                dhcpcd &> /dev/null &
                sleep 5
            fi
            
            if ! ping -c 1 archlinux.org &> /dev/null; then
                exit 1
            fi
        fi
    fi
    print_success "Conexión a internet verificada"
}

validate_disk() {
    local disk=$1
    
    if [[ ! -b "$disk" ]]; then
        print_err "El disco '$disk' no existe o no es un dispositivo de bloque"
        return 1
    fi
    
    if ! lsblk "$disk" &> /dev/null; then
        print_err "No se puede leer información del disco '$disk'"
        return 1
    fi
    
    return 0
}

# ============================================================================
# FUNCIONES DE CONFIGURACIÓN
# ============================================================================

show_disks() {
    print_substep "Discos disponibles:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^(NAME|disk)"
    echo ""
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL
}

configure_mirrors() {
    print_step "Configurando mirrors para Argentina"
    
    # Backup del mirrorlist original
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    
    # Obtener mirrors de Argentina
    print_substep "Obteniendo lista de mirrors para Argentina..."
    local mirror_url="https://archlinux.org/mirrorlist/?country=AR&protocol=https&ip_version=4&use_mirror_status=on"
    
    if curl -s "$mirror_url" | sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist.ar; then
        if [[ -s /etc/pacman.d/mirrorlist.ar ]]; then
            # Ordenar mirrors por velocidad
            print_substep "Ordenando mirrors por velocidad..."
            if command -v rankmirrors &> /dev/null; then
                rankmirrors -n 5 /etc/pacman.d/mirrorlist.ar > /etc/pacman.d/mirrorlist
                print_success "Mirrors de Argentina configurados y ordenados"
            else
                mv /etc/pacman.d/mirrorlist.ar /etc/pacman.d/mirrorlist
                print_success "Mirrors de Argentina configurados"
            fi
        else
            print_warn "No se encontraron mirrors en Argentina, usando mirrors globales"
            reflector --country Argentina,Chile,Uruguay,Brazil --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        fi
    else
        print_warn "No se pudo obtener mirrors, usando lista por defecto"
        reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
    fi
    
    # Actualizar base de datos de paquetes
    print_substep "Actualizando base de datos de paquetes..."
    if pacman -Syy --noconfirm &> /dev/null; then
        print_success "Base de datos actualizada"
    else
        print_warn "No se pudo actualizar la base de datos"
    fi
}

# ============================================================================
# FUNCIONES DE PARTICIONADO
# ============================================================================

partition_uefi() {
    local disk=$1
    
    print_step "Creando particiones UEFI en $disk"
    
    # Limpiar tabla de particiones
    print_substep "Limpiando tabla de particiones..."
    wipefs -a "$disk"
    
    # Crear tabla GPT
    print_substep "Creando tabla GPT..."
    parted -s "$disk" mklabel gpt
    
    # Partición EFI (550MB)
    print_substep "Creando partición EFI (550MB)..."
    parted -s "$disk" mkpart "EFI" fat32 1MiB 551MiB
    parted -s "$disk" set 1 esp on
    
    # Partición raíz BTRFS (resto del disco)
    print_substep "Creando partición raíz BTRFS..."
    parted -s "$disk" mkpart "ROOT" btrfs 551MiB 100%
    
    # Sincronizar
    sync
    partprobe "$disk"
    
    # Formatear particiones
    print_substep "Formateando particiones..."
    
    # EFI
    if [[ -b "${disk}1" ]]; then
        mkfs.fat -F32 "${disk}1"
    elif [[ -b "${disk}p1" ]]; then
        mkfs.fat -F32 "${disk}p1"
    else
        print_err "No se pudo encontrar la partición EFI"
        return 1
    fi
    
    # Root
    if [[ -b "${disk}2" ]]; then
        mkfs.btrfs -f "${disk}2"
    elif [[ -b "${disk}p2" ]]; then
        mkfs.btrfs -f "${disk}p2"
    else
        print_err "No se pudo encontrar la partición raíz"
        return 1
    fi
    
    print_success "Particiones UEFI creadas correctamente"
    return 0
}

partition_bios() {
    local disk=$1
    
    print_step "Creando particiones BIOS en $disk"
    
    # Limpiar tabla de particiones
    print_substep "Limpiando tabla de particiones..."
    wipefs -a "$disk"
    
    # Crear tabla MBR
    print_substep "Creando tabla MBR..."
    parted -s "$disk" mklabel msdos
    
    # Partición de arranque (2GB)
    print_substep "Creando partición de arranque (2GB)..."
    parted -s "$disk" mkpart primary ext4 1MiB 2GiB
    parted -s "$disk" set 1 boot on
    
    # Partición raíz BTRFS (resto del disco)
    print_substep "Creando partición raíz BTRFS..."
    parted -s "$disk" mkpart primary btrfs 2GiB 100%
    
    # Sincronizar
    sync
    partprobe "$disk"
    
    # Formatear particiones
    print_substep "Formateando particiones..."
    
    # Boot
    if [[ -b "${disk}1" ]]; then
        mkfs.ext4 -F "${disk}1"
    elif [[ -b "${disk}p1" ]]; then
        mkfs.ext4 -F "${disk}p1"
    else
        print_err "No se pudo encontrar la partición de arranque"
        return 1
    fi
    
    # Root
    if [[ -b "${disk}2" ]]; then
        mkfs.btrfs -f "${disk}2"
    elif [[ -b "${disk}p2" ]]; then
        mkfs.btrfs -f "${disk}p2"
    else
        print_err "No se pudo encontrar la partición raíz"
        return 1
    fi
    
    print_success "Particiones BIOS creadas correctamente"
    return 0
}

create_btrfs_subvolumes() {
    local root_part=$1
    
    print_step "Creando subvolúmenes BTRFS"
    
    # Montar partición raíz temporalmente
    print_substep "Montando partición raíz..."
    mount "$root_part" /mnt
    
    # Crear subvolúmenes
    print_substep "Creando subvolúmenes..."
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@tmp
    btrfs subvolume create /mnt/@snapshots
    btrfs subvolume create /mnt/@cache
    btrfs subvolume create /mnt/@log
    
    # Desmontar
    umount /mnt
    
    # Montar subvolumen raíz con opciones optimizadas
    print_substep "Montando subvolumen raíz..."
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$root_part" /mnt
    
    # Crear directorios para otros subvolúmenes
    print_substep "Creando estructura de directorios..."
    mkdir -p /mnt/{boot,home,var,tmp,.snapshots}
    
    # Montar otros subvolúmenes
    print_substep "Montando subvolúmenes..."
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$root_part" /mnt/home
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@var "$root_part" /mnt/var
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@tmp "$root_part" /mnt/tmp
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots "$root_part" /mnt/.snapshots
    
    # Directorios especiales
    mkdir -p /mnt/var/{cache,log}
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@cache "$root_part" /mnt/var/cache
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@log "$root_part" /mnt/var/log
    
    print_success "Subvolúmenes BTRFS creados correctamente"
}

# ============================================================================
# FUNCIONES DE INSTALACIÓN
# ============================================================================

install_base_system() {
    print_step "Instalando sistema base"
    
    local boot_mode=$1
    local cpu_type=$2
    
    # Añadir microcódigo según CPU
    local microcode=""
    case "$cpu_type" in
        intel) microcode="intel-ucode" ;;
        amd) microcode="amd-ucode" ;;
    esac
    
    # Paquetes base actualizados
    local packages=("${BASE_PACKAGES[@]}")
    if [[ -n "$microcode" ]]; then
        packages+=("$microcode")
    fi
    
    # Paquetes para UEFI
    if [[ "$boot_mode" == "uefi" ]]; then
        packages+=(efibootmgr)
    fi
    
    # Instalar paquetes base
    print_substep "Instalando paquetes base (esto puede tomar varios minutos)..."
    if pacstrap /mnt "${packages[@]}" --noconfirm; then
        print_success "Sistema base instalado"
    else
        print_err "Error al instalar sistema base"
        return 1
    fi
    
    return 0
}

generate_fstab() {
    print_step "Generando fstab"
    
    # Generar fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Optimizar opciones BTRFS en fstab
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
    sed -i 's|/dev/.* / btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@|' /mnt/etc/fstab
    sed -i 's|/dev/.* /home btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@home|' /mnt/etc/fstab
    sed -i 's|/dev/.* /var btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@var|' /mnt/etc/fstab
    sed -i 's|/dev/.* /tmp btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@tmp|' /mnt/etc/fstab
    
    print_success "Fstab generado"
}

configure_system() {
    print_step "Configurando sistema"
    
    # Configurar zona horaria
    print_substep "Configurando zona horaria..."
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    # Configurar locales
    print_substep "Configurando locales..."
    sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    echo "es_AR.ISO-8859-1 ISO-8859-1" >> /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    
    # Configurar idioma del sistema
    echo "LANG=$LANG" > /mnt/etc/locale.conf
    echo "LC_COLLATE=C" >> /mnt/etc/locale.conf
    
    # Configurar teclado
    print_substep "Configurando teclado..."
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf
    echo "FONT=lat9w-16" >> /mnt/etc/vconsole.conf
    
    # Configurar hostname
    print_substep "Configurando hostname..."
    echo "$HOSTNAME" > /mnt/etc/hostname
    
    # Configurar hosts
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF
    
    # Configurar NetworkManager
    print_substep "Configurando NetworkManager..."
    arch-chroot /mnt systemctl enable NetworkManager.service
    
    # Configurar reflector para mantener mirrors actualizados
    print_substep "Configurando reflector..."
    arch-chroot /mnt pacman -S --noconfirm --needed reflector
    cat > /mnt/etc/xdg/reflector/reflector.conf << EOF
--country Argentina,Chile,Uruguay,Brazil,Paraguay
--protocol https
--latest 10
--sort rate
--save /etc/pacman.d/mirrorlist
EOF
    arch-chroot /mnt systemctl enable reflector.timer
    
    print_success "Sistema configurado"
}

setup_users() {
    print_step "Configurando usuarios"
    
    # Configurar contraseña de root
    print_substep "Configurando contraseña de root..."
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
    else
        print_warn "Se pedirá la contraseña de root manualmente"
        arch-chroot /mnt passwd
    fi
    
    # Crear usuario principal
    print_substep "Creando usuario '$USERNAME'..."
    arch-chroot /mnt useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
    
    if [[ -n "$USER_PASSWORD" ]]; then
        echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd
    else
        print_warn "Se pedirá la contraseña para '$USERNAME' manualmente"
        arch-chroot /mnt passwd "$USERNAME"
    fi
    
    # Configurar sudoers
    print_substep "Configurando sudo..."
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /mnt/etc/sudoers
    
    print_success "Usuarios configurados"
}

install_kde_plasma() {
    print_step "Instalando KDE Plasma"
    
    print_substep "Instalando KDE Plasma (esto puede tomar varios minutos)..."
    if arch-chroot /mnt pacman -S --noconfirm --needed "${KDE_PACKAGES[@]}"; then
        # Habilitar SDDM
        arch-chroot /mnt systemctl enable sddm.service
        
        # Configurar tema SDDM
        cat > /mnt/etc/sddm.conf << EOF
[Theme]
Current=breeze
EOF
        
        print_success "KDE Plasma instalado"
    else
        print_err "Error al instalar KDE Plasma"
        return 1
    fi
    
    return 0
}

install_drivers() {
    print_step "Instalando drivers"
    
    local gpu_type=$1
    
    # Drivers básicos
    print_substep "Instalando drivers básicos..."
    arch-chroot /mnt pacman -S --noconfirm --needed mesa vulkan-radeon vulkan-intel
    
    # Drivers específicos por GPU
    case "$gpu_type" in
        nvidia)
            print_substep "Instalando drivers NVIDIA..."
            arch-chroot /mnt pacman -S --noconfirm --needed nvidia nvidia-utils nvidia-settings
            echo "options nvidia-drm modeset=1" >> /mnt/etc/modprobe.d/nvidia.conf
            ;;
        amd)
            print_substep "Instalando drivers AMD..."
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-amdgpu
            ;;
        intel)
            print_substep "Instalando drivers Intel..."
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-intel
            ;;
    esac
    
    print_success "Drivers instalados"
}

setup_zram() {
    print_step "Configurando ZRAM"
    
    # Instalar zram-generator
    arch-chroot /mnt pacman -S --noconfirm --needed zram-generator
    
    # Calcular tamaño de ZRAM (porcentaje de RAM)
    local ram_mb
    ram_mb=$(get_ram_size)
    local zram_size=$((ram_mb * SWAP_PERCENTAGE / 100))
    
    # Configurar zram-generator
    cat > /mnt/etc/systemd/zram-generator.conf << EOF
[zram0]
zram-size = ${zram_size}M
compression-algorithm = zstd
swap-priority = 100
EOF
    
    print_success "ZRAM configurado (${zram_size}MB)"
}

install_bootloader() {
    print_step "Instalando gestor de arranque"
    
    local boot_mode=$1
    local cpu_type=$2
    
    if [[ "$boot_mode" == "uefi" ]]; then
        # systemd-boot para UEFI
        print_substep "Instalando systemd-boot..."
        arch-chroot /mnt bootctl install
        
        # Configurar loader
        cat > /mnt/boot/loader/loader.conf << EOF
default arch-argentina
timeout 5
console-mode max
editor no
EOF
        
        # Obtener UUID de la partición raíz
        local root_uuid
        root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2" 2>/dev/null || blkid -s UUID -o value "${TARGET_DISK}p2")
        
        # Crear entrada de arranque
        cat > /mnt/boot/loader/entries/arch-argentina.conf << EOF
title   Arch Linux (Argentina)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$root_uuid rw rootflags=subvol=@ quiet loglevel=3
EOF
        
        # Añadir microcódigo
        if [[ "$cpu_type" == "intel" ]]; then
            sed -i '/initrd/i initrd /intel-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        elif [[ "$cpu_type" == "amd" ]]; then
            sed -i '/initrd/i initrd /amd-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        fi
        
        print_success "systemd-boot instalado"
    else
        # GRUB para BIOS
        print_substep "Instalando GRUB..."
        arch-chroot /mnt pacman -S --noconfirm --needed grub
        
        # Instalar GRUB en el disco
        arch-chroot /mnt grub-install --target=i386-pc "$TARGET_DISK"
        
        # Obtener UUID de la partición raíz
        local root_uuid
        root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2" 2>/dev/null || blkid -s UUID -o value "${TARGET_DISK}p2")
        
        # Configurar GRUB
        cat >> /mnt/etc/default/grub << EOF
GRUB_DISABLE_OS_PROBER=false
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX="root=UUID=$root_uuid rootflags=subvol=@"
EOF
        
        # Generar configuración GRUB
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        
        print_success "GRUB instalado"
    fi
}

install_utilities() {
    print_step "Instalando utilidades adicionales"
    
    print_substep "Instalando utilidades..."
    if arch-chroot /mnt pacman -S --noconfirm --needed "${UTILITIES[@]}"; then
        # Habilitar servicios
        arch-chroot /mnt systemctl enable cups.service
        arch-chroot /mnt systemctl enable bluetooth.service
        
        print_success "Utilidades instaladas"
    else
        print_warn "Algunas utilidades no se pudieron instalar"
    fi
}

final_configuration() {
    print_step "Aplicando configuración final"
    
    # Actualizar initramfs
    print_substep "Actualizando initramfs..."
    arch-chroot /mnt mkinitcpio -P
    
    # Habilitar servicios importantes
    print_substep "Habilitando servicios..."
    arch-chroot /mnt systemctl enable fstrim.timer
    arch-chroot /mnt systemctl enable systemd-resolved.service
    arch-chroot /mnt systemctl enable paccache.timer
    
    # Configurar pacman optimizado
    print_substep "Optimizando pacman..."
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf
    sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf
    sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /mnt/etc/pacman.conf
    
    # Configurar journal optimizado
    print_substep "Optimizando journal..."
    sed -i 's/^#SystemMaxUse=/SystemMaxUse=500M/' /mnt/etc/systemd/journald.conf
    
    print_success "Configuración final aplicada"
}

# ============================================================================
# INTERFAZ DE USUARIO
# ============================================================================

show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}     ${BOLD}Arch Linux Installer - KDE Plasma Argentina${NC}     ${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}                 ${CYAN}Configuración automatizada${NC}                 ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_system_info() {
    local boot_mode cpu_type gpu_type ram_size
    
    boot_mode=$(detect_boot_mode)
    cpu_type=$(detect_cpu)
    gpu_type=$(detect_gpu)
    ram_size=$(get_ram_size)
    
    print_step "Información del sistema detectada:"
    echo -e "  ${DIM}•${NC} Modo de arranque: ${BOLD}${boot_mode^^}${NC}"
    echo -e "  ${DIM}•${NC} CPU: ${BOLD}${cpu_type^^}${NC}"
    echo -e "  ${DIM}•${NC} GPU: ${BOLD}${gpu_type^^}${NC}"
    echo -e "  ${DIM}•${NC} RAM: ${BOLD}${ram_size} MB${NC}"
    echo ""
}

interactive_setup() {
    show_header
    show_system_info
    
    # Mostrar discos disponibles
    print_step "Selección de disco"
    show_disks
    echo ""
    
    # Solicitar disco de instalación
    while true; do
        read -rp "Ingrese el disco para instalar (ej: /dev/sda): " TARGET_DISK
        
        if validate_disk "$TARGET_DISK"; then
            break
        else
            print_warn "Disco inválido. Intente nuevamente."
        fi
    done
    
    # Confirmar destrucción de datos
    echo ""
    print_warn "${BOLD}¡ADVERTENCIA!${NC}"
    print_warn "Todos los datos en ${BOLD}$TARGET_DISK${NC} serán ${RED}ELIMINADOS${NC}."
    echo ""
    
    read -rp "¿Continuar con la instalación? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        print_msg "Instalación cancelada por el usuario."
        exit 0
    fi
    
    # Configuración básica del sistema
    echo ""
    print_step "Configuración básica del sistema"
    
    read -rp "Nombre del host [$HOSTNAME]: " input
    [[ -n "$input" ]] && HOSTNAME="$input"
    
    read -rp "Nombre de usuario [$USERNAME]: " input
    [[ -n "$input" ]] && USERNAME="$input"
    
    # Contraseñas
    echo ""
    print_substep "Configuración de contraseñas"
    
    while true; do
        read -rsp "Contraseña para root (dejar vacío para saltar): " ROOT_PASSWORD
        echo
        if [[ -n "$ROOT_PASSWORD" ]]; then
            read -rsp "Confirmar contraseña: " confirm_pass
            echo
            if [[ "$ROOT_PASSWORD" == "$confirm_pass" ]]; then
                break
            else
                print_warn "Las contraseñas no coinciden. Intente nuevamente."
            fi
        else
            print_warn "La contraseña de root se configurará manualmente después."
            break
        fi
    done
    
    while true; do
        read -rsp "Contraseña para usuario '$USERNAME' (dejar vacío para saltar): " USER_PASSWORD
        echo
        if [[ -n "$USER_PASSWORD" ]]; then
            read -rsp "Confirmar contraseña: " confirm_pass
            echo
            if [[ "$USER_PASSWORD" == "$confirm_pass" ]]; then
                break
            else
                print_warn "Las contraseñas no coinciden. Intente nuevamente."
            fi
        else
            print_warn "La contraseña del usuario se configurará manualmente después."
            break
        fi
    done
    
    # Configuración de ZRAM
    echo ""
    print_substep "Configuración de ZRAM"
    read -rp "Porcentaje de RAM para ZRAM [$SWAP_PERCENTAGE%]: " input
    if [[ -n "$input" ]] && [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 10 ]] && [[ "$input" -le 200 ]]; then
        SWAP_PERCENTAGE="$input"
    fi
    
    print_success "Configuración completada"
    echo ""
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    # Verificaciones iniciales
    check_root
    check_internet
    
    # Configuración interactiva
    interactive_setup
    
    # Detectar hardware
    local boot_mode cpu_type gpu_type
    boot_mode=$(detect_boot_mode)
    cpu_type=$(detect_cpu)
    gpu_type=$(detect_gpu)
    
    # Configurar mirrors
    configure_mirrors
    
    # Particionado
    print_step "Iniciando particionado"
    
    if [[ "$boot_mode" == "uefi" ]]; then
        if ! partition_uefi "$TARGET_DISK"; then
            print_err "Error en el particionado UEFI"
            exit 1
        fi
        
        # Identificar particiones
        local root_part="${TARGET_DISK}2"
        [[ ! -b "$root_part" ]] && root_part="${TARGET_DISK}p2"
        
        # Montar EFI
        local efi_part="${TARGET_DISK}1"
        [[ ! -b "$efi_part" ]] && efi_part="${TARGET_DISK}p1"
        
        create_btrfs_subvolumes "$root_part"
        mkdir -p /mnt/boot/efi
        mount "$efi_part" /mnt/boot/efi
    else
        if ! partition_bios "$TARGET_DISK"; then
            print_err "Error en el particionado BIOS"
            exit 1
        fi
        
        # Identificar particiones
        local root_part="${TARGET_DISK}2"
        [[ ! -b "$root_part" ]] && root_part="${TARGET_DISK}p2"
        
        # Montar boot
        local boot_part="${TARGET_DISK}1"
        [[ ! -b "$boot_part" ]] && boot_part="${TARGET_DISK}p1"
        
        create_btrfs_subvolumes "$root_part"
        mkdir -p /mnt/boot
        mount "$boot_part" /mnt/boot
    fi
    
    # Instalación del sistema
    if ! install_base_system "$boot_mode" "$cpu_type"; then
        print_err "Error en la instalación del sistema base"
        exit 1
    fi
    
    generate_fstab
    configure_system
    setup_users
    
    # Instalación de KDE Plasma
    if ! install_kde_plasma; then
        print_warn "Continuando sin KDE Plasma"
    fi
    
    # Instalación de drivers
    install_drivers "$gpu_type"
    
    # Configuración de ZRAM
    setup_zram
    
    # Instalación del bootloader
    install_bootloader "$boot_mode" "$cpu_type"
    
    # Instalación de utilidades
    install_utilities
    
    # Configuración final
    final_configuration
    
    # Limpieza
    print_step "Limpiando caché de paquetes..."
    arch-chroot /mnt paccache -r
    
    # Finalización
    print_step "Instalación completada"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}          ${BOLD}¡INSTALACIÓN COMPLETADA EXITOSAMENTE!${NC}          ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Información del sistema instalado:${NC}                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Hostname: ${BOLD}$HOSTNAME${NC}                                ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Usuario: ${BOLD}$USERNAME${NC}                                 ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Interfaz: ${BOLD}KDE Plasma${NC}                               ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Sistema de archivos: ${BOLD}BTRFS${NC}                         ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Swap: ${BOLD}ZRAM (${SWAP_PERCENTAGE}% de RAM)${NC}                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Pasos siguientes:${NC}                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  1. Desmontar: ${DIM}umount -R /mnt${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  2. Reiniciar: ${DIM}reboot${NC}                                  ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  3. Remover medio de instalación antes de reiniciar              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Mostrar resumen de configuración
    print_step "Resumen de configuración:"
    echo -e "  ${DIM}•${NC} Locale: ${LOCALE%% *}"
    echo -e "  ${DIM}•${NC} Teclado: $KEYMAP"
    echo -e "  ${DIM}•${NC} Zona horaria: $TIMEZONE"
    echo -e "  ${DIM}•${NC} Idioma: $LANG"
    echo ""
    
    print_warn "${BOLD}¡IMPORTANTE!${NC} No olvide remover el medio de instalación antes de reiniciar."
}

# ============================================================================
# EJECUCIÓN
# ============================================================================

# Manejo de señales
trap 'print_err "Instalación interrumpida por el usuario"; exit 1' INT TERM

# Ejecutar función principal
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
