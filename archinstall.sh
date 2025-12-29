#!/usr/bin/env bash
# Arch Linux Installer - KDE Plasma Minimal (Argentina)
# Sin ZRAM. Corrección para asegurar arranque gráfico.
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
# ZRAM eliminado por solicitud del usuario

# Lista de mirrors de respaldo
readonly BACKUP_MIRRORS=(
    "https://mirror.leaseweb.com/archlinux/\$repo/os/\$arch"
    "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
    "https://geo.mirror.pkgbuild.com/\$repo/os/\$arch"
)

# Paquetes base esenciales
readonly BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    btrfs-progs sudo nano vim bash-completion
    networkmanager wpa_supplicant dialog wireless_tools
    git curl wget openssh rsync archlinux-keyring
    man-db man-pages texinfo usbutils pciutils
    dosfstools mtools fuse2 fuse3 fuse
    ntfs-3g exfatprogs
)

# Paquetes KDE Plasma MINIMO (Sin bloat)
readonly KDE_PACKAGES=(
    plasma-meta               # Entorno de escritorio base
    plasma-wayland-session    # Sesión Wayland
    sddm sddm-kcm             # Gestor de login
    dolphin                   # Gestor de archivos
    konsole                   # Terminal
    kate                      # Editor de texto
    ark                       # Gestor de compresión
    spectacle                 # Capturas de pantalla
    gwenview                  # Visor de imágenes
    kcalc                     # Calculadora
    kde-gtk-config            # Integración apps GTK
    breeze-gtk                # Tema GTK
    xdg-desktop-portal-kde    # Portales para Wayland
    xdg-utils
    pipewire pipewire-pulse pipewire-alsa wireplumber # Audio moderno
    phonon-qt6-gstreamer      # Backend audio Qt6
    xorg-server xorg-xinit    # Soporte XWayland
)

# Utilidades básicas y necesarias
readonly UTILITIES=(
    firefox                   # Navegador web
    htop btop neofetch        # Monitorización
    gparted                   # Particiones
    vlc                       # Reproductor multimedia
    cups                      # Sistema de impresión
    bluez bluez-utils         # Bluetooth
    gvfs gvfs-mtp gvfs-smb    # Soporte USB/Red
    unzip p7zip               # Descompresión
    reflector                 # Gestión mirrors
    ttf-dejavu ttf-liberation noto-fonts noto-fonts-emoji # Fuentes esenciales
)

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'

print_msg() { echo -e "${GREEN}[*]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
print_err() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_step() { echo -e "\n${BLUE}==>${NC} ${BOLD}$1${NC}"; }
print_substep() { echo -e "${CYAN}  ->${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_fail() { echo -e "${RED}[✗]${NC} $1"; }

# ============================================================================
# FUNCIONES DE DETECCIÓN
# ============================================================================

detect_boot_mode() {
    [[ -d /sys/firmware/efi/efivars ]] && echo "uefi" || echo "bios"
}

detect_cpu() {
    if grep -q "GenuineIntel" /proc/cpuinfo; then echo "intel"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then echo "amd"
    else echo "unknown"; fi
}

detect_gpu() {
    if lspci | grep -qi "nvidia"; then echo "nvidia"
    elif lspci | grep -qi "amd" | grep -qi "radeon"; then echo "amd"
    elif lspci | grep -qi "intel" | grep -qi "graphics"; then echo "intel"
    else echo "unknown"; fi
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
    if ping -c 1 -W 2 archlinux.org &> /dev/null; then
        print_success "Conexión a internet verificada"
    else
        print_warn "No se pudo verificar la conexión a internet, intentando continuar..."
    fi
}

validate_disk() {
    [[ -b "$1" ]] && lsblk "$1" &> /dev/null
}

# ============================================================================
# FUNCIONES DE CONFIGURACIÓN DE MIRRORS
# ============================================================================

configure_mirrors() {
    print_step "Configurando mirrors de paquetes"
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    fi

    # Intentar usar reflector o backup
    if command -v reflector &> /dev/null; then
        print_substep "Optimizando mirrors con reflector..."
        reflector --country 'Argentina,Brazil,Chile,United States' --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || \
        reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    fi

    # Fallback a backup si está vacío
    if ! grep -q "Server" /etc/pacman.d/mirrorlist; then
        print_warn "Usando mirrors de respaldo..."
        cat > /etc/pacman.d/mirrorlist << EOF
Server = https://mirrors.nic.ar/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF
    fi

    # Configurar pacman
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf

    pacman -Syy --noconfirm
    print_success "Mirrors configurados"
}

# ============================================================================
# FUNCIONES DE PARTICIONADO
# ============================================================================

partition_uefi() {
    local disk=$1
    print_step "Creando particiones UEFI en $disk"
    wipefs -a "$disk" 2>/dev/null || true
    parted -s "$disk" mklabel gpt
    parted -s "$disk" mkpart "EFI" fat32 1MiB 601MiB
    parted -s "$disk" set 1 esp on
    parted -s "$disk" mkpart "ROOT" btrfs 601MiB 100%
    sync; sleep 2; partprobe "$disk" 2>/dev/null || true

    local root_part="${disk}2"; [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    local efi_part="${disk}1"; [[ ! -b "$efi_part" ]] && efi_part="${disk}p1"

    [[ -b "$efi_part" ]] && mkfs.fat -F32 "$efi_part" || return 1
    [[ -b "$root_part" ]] && mkfs.btrfs -f "$root_part" || return 1
    
    print_success "Particiones UEFI creadas"
    echo "$root_part|$efi_part"
}

partition_bios() {
    local disk=$1
    print_step "Creando particiones BIOS en $disk"
    wipefs -a "$disk" 2>/dev/null || true
    parted -s "$disk" mklabel msdos
    parted -s "$disk" mkpart primary ext4 1MiB 2GiB
    parted -s "$disk" set 1 boot on
    parted -s "$disk" mkpart primary btrfs 2GiB 100%
    sync; sleep 2; partprobe "$disk" 2>/dev/null || true

    local root_part="${disk}2"; [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    local boot_part="${disk}1"; [[ ! -b "$boot_part" ]] && boot_part="${disk}p1"

    [[ -b "$boot_part" ]] && mkfs.ext4 -F "$boot_part" || return 1
    [[ -b "$root_part" ]] && mkfs.btrfs -f "$root_part" || return 1

    print_success "Particiones BIOS creadas"
    echo "$root_part|$boot_part"
}

create_btrfs_subvolumes() {
    local root_part=$1
    print_step "Creando subvolúmenes BTRFS"
    mount "$root_part" /mnt
    btrfs subvolume create /mnt/@
    btrfs subvolume create /mnt/@home
    btrfs subvolume create /mnt/@var
    btrfs subvolume create /mnt/@snapshots
    umount /mnt

    mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$root_part" /mnt
    mkdir -p /mnt/{home,var,.snapshots}
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$root_part" /mnt/home
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@var "$root_part" /mnt/var
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots "$root_part" /mnt/.snapshots
    
    print_success "Subvolúmenes creados"
}

# ============================================================================
# INSTALACIÓN Y CONFIGURACIÓN
# ============================================================================

install_system() {
    print_step "Instalando sistema base y entorno"
    local boot_mode=$1 cpu_type=$2
    local packages=("${BASE_PACKAGES[@]}")

    [[ "$cpu_type" == "intel" ]] && packages+=("intel-ucode")
    [[ "$cpu_type" == "amd" ]] && packages+=("amd-ucode")
    [[ "$boot_mode" == "uefi" ]] && packages+=("efibootmgr")

    pacstrap /mnt "${packages[@]}" --noconfirm
    print_success "Sistema base instalado"
}

generate_fstab() {
    print_step "Generando fstab"
    genfstab -U /mnt >> /mnt/etc/fstab
    # Optimización BTRFS compatible con UUID
    sed -i 's/subvolid=[0-9]*,//g' /mnt/etc/fstab
    sed -i 's|\(.*[[:space:]]\/[[:space:]]btrfs.*\)|\1 noatime,compress=zstd,space_cache=v2,subvol=@|' /mnt/etc/fstab
    sed -i 's|\(.*[[:space:]]\/home[[:space:]]btrfs.*\)|\1 noatime,compress=zstd,space_cache=v2,subvol=@home|' /mnt/etc/fstab
    sed -i 's|\(.*[[:space:]]\/var[[:space:]]btrfs.*\)|\1 noatime,compress=zstd,space_cache=v2,subvol=@var|' /mnt/etc/fstab
    sed -i 's|\(.*[[:space:]]\/\.snapshots[[:space:]]btrfs.*\)|\1 noatime,compress=zstd,space_cache=v2,subvol=@snapshots|' /mnt/etc/fstab
    print_success "Fstab generado"
}

configure_chroot() {
    print_step "Configurando sistema base"
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    
    sed -i "s/^#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$LANG" > /mnt/etc/locale.conf
    
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf
    echo "$HOSTNAME" > /mnt/etc/hostname
    
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF
    
    arch-chroot /mnt systemctl enable NetworkManager.service
    print_success "Sistema configurado"
}

setup_users() {
    print_step "Configurando usuarios"
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
    fi
    
    arch-chroot /mnt useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
    if [[ -n "$USER_PASSWORD" ]]; then
        echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd
    fi
    
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /mnt/etc/sudoers
    print_success "Usuarios configurados"
}

install_gui() {
    print_step "Instalando Plasma y utilidades"
    
    # Instalar Plasma
    if ! arch-chroot /mnt pacman -S --noconfirm --needed "${KDE_PACKAGES[@]}"; then
        print_err "Error crítico instalando KDE Plasma."
        return 1
    fi

    # Verificar que SDDM se instaló antes de habilitar
    if ! arch-chroot /mnt command -v sddm &>/dev/null; then
        print_err "SDDM no está instalado. El arranque gráfico fallará."
        return 1
    fi

    # Habilitar SDDM y Target Gráfico
    arch-chroot /mnt systemctl enable sddm.service
    arch-chroot /mnt systemctl set-default graphical.target
    
    print_success "SDDM habilitado y Target Gráfico configurado"
    
    # Instalar Utilidades (no es crítico si fallan, pero lo intentamos)
    print_substep "Instalando utilidades..."
    arch-chroot /mnt pacman -S --noconfirm --needed "${UTILITIES[@]}" || print_warn "Algunas utilidades no se instalaron"
    
    # Habilitar servicios periféricos
    arch-chroot /mnt systemctl enable cups.service || true
    arch-chroot /mnt systemctl enable bluetooth.service || true
    
    # Reflector timer
    if command -v reflector &>/dev/null; then
        cat > /mnt/etc/xdg/reflector/reflector.conf << EOF
--country Argentina,Brazil,Chile,United States
--latest 10
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
EOF
        arch-chroot /mnt systemctl enable reflector.timer || true
    fi
    
    print_success "Plasma y utilidades instaladas"
}

install_drivers() {
    local gpu=$1
    print_step "Instalando drivers de video"
    arch-chroot /mnt pacman -S --noconfirm --needed mesa vulkan-radeon vulkan-intel
    
    case "$gpu" in
        nvidia) arch-chroot /mnt pacman -S --noconfirm --needed nvidia nvidia-utils ;;
        amd) arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-amdgpu ;;
        intel) arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-intel ;;
    esac
}

install_bootloader() {
    print_step "Instalando gestor de arranque"
    local boot_mode=$1 cpu_type=$2
    
    if [[ "$boot_mode" == "uefi" ]]; then
        arch-chroot /mnt bootctl install
        cat > /mnt/boot/loader/loader.conf << EOF
default arch
timeout 3
editor no
EOF

        local root_uuid=""
        if [[ -b "${TARGET_DISK}2" ]]; then root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2}")
        elif [[ -b "${TARGET_DISK}p2" ]]; then root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}p2"})
        fi

        local ucode=""
        [[ "$cpu_type" == "intel" ]] && ucode="initrd /intel-ucode.img"
        
        cat > /mnt/boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
$ucode
initrd  /initramfs-linux.img
options root=UUID=$root_uuid rw rootflags=subvol=@ quiet
EOF
    else
        arch-chroot /mnt pacman -S --noconfirm grub
        arch-chroot /mnt grub-install --target=i386-pc "$TARGET_DISK"
        
        local root_uuid=""
        if [[ -b "${TARGET_DISK}2" ]]; then root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2"})
        elif [[ -b "${TARGET_DISK}p2" ]]; then root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}p2"})
        fi
        
        sed -i "s|^GRUB_CMDLINE_LINUX=\"\"|GRUB_CMDLINE_LINUX=\"root=UUID=$root_uuid rootflags=subvol=@\"|" /mnt/etc/default/grub
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    fi
    print_success "Bootloader instalado"
}

# ============================================================================
# INTERFAZ DE USUARIO
# ============================================================================

show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${BOLD}Arch Linux Minimal - KDE Plasma (Argentina)${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
}

interactive_setup() {
    show_header
    lsblk -d -o NAME,SIZE,MODEL | grep disk
    echo ""
    while true; do
        read -rp "Ingrese el disco destino (ej: /dev/sda): " TARGET_DISK
        validate_disk "$TARGET_DISK" && break
        print_warn "Disco inválido."
    done
    
    echo ""
    read -rp "Nombre de host [$HOSTNAME]: " input
    [[ -n "$input" ]] && HOSTNAME="$input"
    
    read -rp "Nombre de usuario [$USERNAME]: " input
    [[ -n "$input" ]] && USERNAME="$input"

    echo ""
    read -rsp "Contraseña para usuario $USERNAME: " USER_PASSWORD
    echo
    read -rsp "Contraseña para root: " ROOT_PASSWORD
    echo

    read -rp "¿Confirmar instalación en $TARGET_DISK? (s/N): " confirm
    [[ ! "$confirm" =~ ^[Ss]$ ]] && exit 0
}

main() {
    check_root
    check_internet
    interactive_setup
    
    local boot_mode=$(detect_boot_mode)
    local cpu_type=$(detect_cpu)
    local gpu_type=$(detect_gpu)
    
    configure_mirrors
    
    local parts
    if [[ "$boot_mode" == "uefi" ]]; then
        parts=$(partition_uefi "$TARGET_DISK")
    else
        parts=$(partition_bios "$TARGET_DISK")
    fi
    
    local root_part=$(echo "$parts" | cut -d'|' -f1)
    local boot_part=$(echo "$parts" | cut -d'|' -f2)
    
    create_btrfs_subvolumes "$root_part"
    
    mkdir -p /mnt/boot
    mount "$boot_part" /mnt/boot
    
    install_system "$boot_mode" "$cpu_type"
    generate_fstab
    configure_chroot
    setup_users
    install_drivers "$gpu_type"
    install_gui
    install_bootloader "$boot_mode" "$cpu_type"
    
    # Configuración final
    arch-chroot /mnt mkinitcpio -P
    
    # Ajustes de rendimiento (sin ZRAM)
    # Opcional: Ajustar swappiness para usar swap en disco más tarde si es necesario
    echo "vm.swappiness=10" >> /mnt/etc/sysctl.d/99-sysctl.conf
    
    print_step "Instalación completada"
    echo -e "${GREEN}Sistema instalado en $TARGET_DISK${NC}"
    echo "Reinicia y retira el medio de instalación."
    
    read -rp "¿Desmontar ahora? (S/n): " unmount
    [[ ! "$unmount" =~ ^[Nn]$ ]] && umount -R /mnt
}

main "$@"
```
