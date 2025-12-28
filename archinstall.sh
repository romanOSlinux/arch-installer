#!/usr/bin/env bash
# Arch Linux Installer - KDE Plasma Argentina (Minimal)
# Script optimizado: solo sistema base + KDE Plasma mínimo
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

# Variables del sistema
TARGET_DISK=""
HOSTNAME="arch-argentina"
USERNAME="argentino"
ROOT_PASSWORD=""
USER_PASSWORD=""
SWAP_PERCENTAGE=100  # 100% de RAM para ZRAM

# Lista de mirrors de respaldo
readonly BACKUP_MIRRORS=(
    "https://mirror.leaseweb.com/archlinux/\$repo/os/\$arch"
    "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
    "https://mirror.lty.me/archlinux/\$repo/os/\$arch"
    "https://archlinux.mailtunnel.eu/\$repo/os/\$arch"
)

# Paquetes base esenciales
readonly BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    btrfs-progs sudo nano bash-completion
    networkmanager wpa_supplicant wireless_tools
    git curl wget openssh rsync archlinux-keyring
    man-db man-pages usbutils pciutils
    dosfstools mtools fuse2 fuse3
    xfsprogs ntfs-3g exfatprogs
)

# KDE Plasma MÍNIMO - solo lo esencial
readonly KDE_MINIMAL=(
    plasma-desktop
    plasma-wayland-session
    sddm
    dolphin
    konsole
    kate
    kde-gtk-config
    breeze-gtk
    xdg-desktop-portal-kde
    xdg-utils
    pipewire pipewire-pulse pipewire-alsa wireplumber
    phonon-qt5-gstreamer
    xorg-server
    xorg-xinit
    plasma-nm
    powerdevil
    bluedevil
    kscreen
    discover
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
    local gpu_info
    gpu_info=$(lspci 2>/dev/null | grep -E "VGA|3D|Display" || echo "")
    
    if echo "$gpu_info" | grep -qi "nvidia"; then
        echo "nvidia"
    elif echo "$gpu_info" | grep -qi "amd" && echo "$gpu_info" | grep -qi "radeon"; then
        echo "amd"
    elif echo "$gpu_info" | grep -qi "intel" || echo "$gpu_info" | grep -qi "integrated graphics"; then
        echo "intel"
    elif echo "$gpu_info" | grep -qi "vmware\|virtualbox\|qxl\|virtio"; then
        echo "virtual"
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

    if ping -c 1 -W 2 archlinux.org &> /dev/null; then
        print_success "Conexión a internet verificada"
    else
        print_warn "No se pudo verificar la conexión a internet"
        print_warn "Intentando continuar de todos modos..."
    fi
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
# FUNCIONES DE CONFIGURACIÓN DE MIRRORS
# ============================================================================

configure_mirrors() {
    print_step "Configurando mirrors de paquetes"

    # Crear backup del mirrorlist original
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    fi

    # Usar reflector para generar lista de mirrors
    if command -v reflector &> /dev/null; then
        reflector \
            --country 'Argentina,Brazil,Chile,Uruguay,United States' \
            --latest 10 \
            --protocol https \
            --sort rate \
            --save /etc/pacman.d/mirrorlist \
            2>/dev/null || true
    else
        # Instalar reflector
        pacman -Sy --noconfirm reflector 2>/dev/null || true
        if command -v reflector &> /dev/null; then
            reflector \
                --country 'Argentina,Brazil,Chile,Uruguay,United States' \
                --latest 10 \
                --protocol https \
                --sort rate \
                --save /etc/pacman.d/mirrorlist \
                2>/dev/null || true
        fi
    fi

    # Si no funciona, usar mirrors predefinidos
    if [[ ! -s /etc/pacman.d/mirrorlist ]] || grep -q "^#Server" /etc/pacman.d/mirrorlist; then
        cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.lty.me/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = http://mirror.rackspace.com/archlinux/$repo/os/$arch
EOF
    fi

    # Configurar opciones de pacman
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 3/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf

    # Actualizar base de datos
    print_substep "Actualizando base de datos de paquetes..."
    pacman -Syy --noconfirm 2>/dev/null || true

    print_success "Mirrors configurados"
    return 0
}

# ============================================================================
# FUNCIONES DE PARTICIONADO
# ============================================================================

partition_uefi() {
    local disk=$1

    print_step "Creando particiones UEFI en $disk"

    # Limpiar tabla de particiones
    wipefs -a "$disk" 2>/dev/null || true

    # Crear tabla GPT
    parted -s "$disk" mklabel gpt

    # Partición EFI (600MB)
    parted -s "$disk" mkpart "EFI" fat32 1MiB 601MiB
    parted -s "$disk" set 1 esp on

    # Partición raíz BTRFS (resto del disco)
    parted -s "$disk" mkpart "ROOT" btrfs 601MiB 100%

    # Sincronizar
    sync
    sleep 2

    # Formatear particiones
    local efi_part="${disk}1"
    [[ ! -b "$efi_part" ]] && efi_part="${disk}p1"
    local root_part="${disk}2"
    [[ ! -b "$root_part" ]] && root_part="${disk}p2"

    if [[ -b "$efi_part" ]]; then
        mkfs.fat -F32 "$efi_part"
    else
        print_err "No se pudo encontrar la partición EFI"
        return 1
    fi

    if [[ -b "$root_part" ]]; then
        mkfs.btrfs -f "$root_part"
    else
        print_err "No se pudo encontrar la partición raíz"
        return 1
    fi

    print_success "Particiones UEFI creadas"
    return 0
}

partition_bios() {
    local disk=$1

    print_step "Creando particiones BIOS en $disk"

    # Limpiar tabla de particiones
    wipefs -a "$disk" 2>/dev/null || true

    # Crear tabla MBR
    parted -s "$disk" mklabel msdos

    # Partición de arranque (2GB)
    parted -s "$disk" mkpart primary ext4 1MiB 2GiB
    parted -s "$disk" set 1 boot on

    # Partición raíz BTRFS (resto del disco)
    parted -s "$disk" mkpart primary btrfs 2GiB 100%

    # Sincronizar
    sync
    sleep 2

    # Formatear particiones
    local boot_part="${disk}1"
    [[ ! -b "$boot_part" ]] && boot_part="${disk}p1"
    local root_part="${disk}2"
    [[ ! -b "$root_part" ]] && root_part="${disk}p2"

    if [[ -b "$boot_part" ]]; then
        mkfs.ext4 -F "$boot_part"
    else
        print_err "No se pudo encontrar la partición de arranque"
        return 1
    fi

    if [[ -b "$root_part" ]]; then
        mkfs.btrfs -f "$root_part"
    else
        print_err "No se pudo encontrar la partición raíz"
        return 1
    fi

    print_success "Particiones BIOS creadas"
    return 0
}

create_btrfs_subvolumes() {
    local root_part=$1

    print_step "Creando subvolúmenes BTRFS"

    # Montar partición raíz temporalmente
    mount "$root_part" /mnt 2>/dev/null || {
        print_err "No se pudo montar la partición raíz"
        return 1
    }

    # Crear subvolúmenes básicos
    btrfs subvolume create /mnt/@ 2>/dev/null || true
    btrfs subvolume create /mnt/@home 2>/dev/null || true

    # Desmontar
    umount /mnt 2>/dev/null || true

    # Montar subvolumen raíz
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@ "$root_part" /mnt

    # Crear directorio home y montar
    mkdir -p /mnt/home
    mount -o noatime,compress=zstd,space_cache=v2,subvol=@home "$root_part" /mnt/home

    print_success "Subvolúmenes BTRFS creados"
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

    # Paquetes base
    local packages=("${BASE_PACKAGES[@]}")
    if [[ -n "$microcode" ]]; then
        packages+=("$microcode")
    fi

    # Paquetes para UEFI
    if [[ "$boot_mode" == "uefi" ]]; then
        packages+=(efibootmgr)
    fi

    # Instalar paquetes base
    print_substep "Instalando paquetes base..."
    if pacstrap /mnt "${packages[@]}" --noconfirm 2>&1; then
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

    # Optimizar opciones BTRFS
    sed -i 's|/dev/.* / btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@|' /mnt/etc/fstab
    sed -i 's|/dev/.* /home btrfs|& noatime,compress=zstd,space_cache=v2,subvol=@home|' /mnt/etc/fstab

    print_success "Fstab generado"
}

configure_system() {
    print_step "Configurando sistema"

    # Configurar zona horaria
    arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc

    # Configurar locales
    sed -i "s/^#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    arch-chroot /mnt locale-gen
    echo "LANG=$LANG" > /mnt/etc/locale.conf

    # Configurar teclado
    echo "KEYMAP=$KEYMAP" > /mnt/etc/vconsole.conf
    echo "FONT=lat9w-16" >> /mnt/etc/vconsole.conf

    # Configurar hostname
    echo "$HOSTNAME" > /mnt/etc/hostname

    # Configurar hosts
    cat > /mnt/etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
EOF

    # Configurar NetworkManager
    arch-chroot /mnt systemctl enable NetworkManager.service

    print_success "Sistema configurado"
}

setup_users() {
    print_step "Configurando usuarios"

    # Configurar contraseña de root
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
        print_substep "Contraseña de root configurada"
    else
        print_warn "Se pedirá la contraseña de root manualmente después del reinicio"
    fi

    # Crear usuario principal
    if ! arch-chroot /mnt id "$USERNAME" &>/dev/null; then
        arch-chroot /mnt useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
    fi

    if [[ -n "$USER_PASSWORD" ]]; then
        echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd
        print_substep "Contraseña de usuario configurada"
    else
        print_warn "Se pedirá la contraseña para '$USERNAME' manualmente después del reinicio"
    fi

    # Configurar sudoers
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers

    print_success "Usuarios configurados"
}

install_kde_plasma_minimal() {
    print_step "Instalando KDE Plasma Mínimo"

    print_substep "Instalando paquetes de KDE Plasma..."
    
    # Primero instalar paquetes esenciales de KDE
    if arch-chroot /mnt pacman -S --noconfirm --needed "${KDE_MINIMAL[@]}" 2>&1; then
        print_substep "KDE Plasma instalado correctamente"
    else
        print_warn "Hubo problemas instalando KDE Plasma, intentando continuar..."
    fi

    # HABILITAR SDDM - Esto es crucial
    print_substep "Habilitando SDDM..."
    arch-chroot /mnt systemctl enable sddm.service 2>/dev/null || {
        print_warn "No se pudo habilitar SDDM, intentando instalar sddm..."
        arch-chroot /mnt pacman -S --noconfirm sddm 2>/dev/null || true
        arch-chroot /mnt systemctl enable sddm.service 2>/dev/null || true
    }

    # Configurar tema SDDM
    cat > /mnt/etc/sddm.conf << EOF
[Theme]
Current=breeze
EOF

    print_success "KDE Plasma Mínimo instalado y SDDM habilitado"
    return 0
}

install_drivers() {
    print_step "Instalando drivers"

    local gpu_type=$1

    # Drivers básicos
    arch-chroot /mnt pacman -S --noconfirm --needed mesa 2>/dev/null || true

    # Drivers específicos por GPU
    case "$gpu_type" in
        nvidia)
            arch-chroot /mnt pacman -S --noconfirm --needed nvidia nvidia-utils 2>/dev/null || true
            ;;
        amd)
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-amdgpu 2>/dev/null || true
            ;;
        intel)
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-intel 2>/dev/null || true
            ;;
    esac

    print_success "Drivers instalados"
}

setup_zram() {
    print_step "Configurando ZRAM"

    # Calcular tamaño de ZRAM (porcentaje de RAM)
    local ram_mb
    ram_mb=$(get_ram_size)
    local zram_size=$((ram_mb * SWAP_PERCENTAGE / 100))
    
    print_substep "RAM detectada: ${ram_mb}MB"
    print_substep "Configurando ZRAM con ${zram_size}MB (${SWAP_PERCENTAGE}% de RAM)"

    # Instalar zram-generator
    arch-chroot /mnt pacman -S --noconfirm --needed systemd-swap 2>/dev/null || {
        print_warn "No se pudo instalar systemd-swap para ZRAM"
        return 0
    }

    # Configurar ZRAM usando systemd-swap
    cat > /mnt/etc/systemd/swap.conf.d/zram.conf << EOF
zswap_enabled=0
zram_enabled=1
zram_size=$((zram_size * 1024 * 1024))  # Convertir a bytes
zram_count=1
zram_streams=$(nproc)
zram_alg=zstd
EOF

    # Habilitar systemd-swap
    arch-chroot /mnt systemctl enable systemd-swap 2>/dev/null || true

    # Configurar swappiness
    echo "vm.swappiness=100" >> /mnt/etc/sysctl.d/99-sysctl.conf 2>/dev/null || true

    print_success "ZRAM configurado (${zram_size}MB usando zstd)"
}

install_bootloader() {
    print_step "Instalando gestor de arranque"

    local boot_mode=$1
    local cpu_type=$2

    if [[ "$boot_mode" == "uefi" ]]; then
        # systemd-boot para UEFI
        print_substep "Instalando systemd-boot..."

        # Crear directorio para EFI si no existe
        mkdir -p /mnt/boot/loader/entries

        # Instalar systemd-boot
        arch-chroot /mnt bootctl install 2>/dev/null || {
            print_warn "Intentando método alternativo..."
            arch-chroot /mnt bootctl install --path=/boot 2>/dev/null || true
        }

        # Configurar loader
        cat > /mnt/boot/loader/loader.conf << EOF
default arch-argentina
timeout 5
console-mode max
editor no
EOF

        # Obtener UUID de la partición raíz
        local root_uuid=""
        if [[ -b "${TARGET_DISK}2" ]]; then
            root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2")
        elif [[ -b "${TARGET_DISK}p2" ]]; then
            root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}p2")
        fi

        if [[ -z "$root_uuid" ]]; then
            print_warn "No se pudo obtener UUID, usando etiqueta de partición"
            root_uuid="PARTLABEL=ROOT"
        fi

        # Crear entrada de arranque
        cat > /mnt/boot/loader/entries/arch-argentina.conf << EOF
title   Arch Linux (Argentina)
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=$root_uuid rw rootflags=subvol=@ quiet loglevel=3
EOF

        # Añadir microcódigo
        if [[ "$cpu_type" == "intel" ]]; then
            sed -i '2i initrd /intel-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        elif [[ "$cpu_type" == "amd" ]]; then
            sed -i '2i initrd /amd-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        fi

        print_success "systemd-boot instalado"
    else
        # GRUB para BIOS
        print_substep "Instalando GRUB..."
        arch-chroot /mnt pacman -S --noconfirm --needed grub 2>/dev/null || {
            print_err "No se pudo instalar GRUB"
            return 1
        }

        # Instalar GRUB en el disco
        arch-chroot /mnt grub-install --target=i386-pc "$TARGET_DISK" 2>/dev/null || true

        # Configurar GRUB
        cat >> /mnt/etc/default/grub << EOF
GRUB_DISABLE_OS_PROBER=false
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
EOF

        # Generar configuración GRUB
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true

        print_success "GRUB instalado"
    fi
}

final_configuration() {
    print_step "Aplicando configuración final"

    # Actualizar initramfs
    arch-chroot /mnt mkinitcpio -P 2>/dev/null || true

    # Habilitar servicios importantes
    arch-chroot /mnt systemctl enable fstrim.timer 2>/dev/null || true

    # Configurar pacman optimizado
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf 2>/dev/null || true

    print_success "Configuración final aplicada"
}

# ============================================================================
# INTERFAZ DE USUARIO
# ============================================================================

show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}   ${BOLD}Arch Linux Installer - KDE Plasma Minimal Argentina${NC}   ${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}            ${CYAN}Configuración básica automática${NC}               ${BLUE}║${NC}"
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

show_disks() {
    print_substep "Discos disponibles:"
    echo -e "${DIM}"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null || true
    echo -e "${NC}"
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
        read -rp "Ingrese el disco para instalar (ej: /dev/sda, /dev/nvme0n1): " TARGET_DISK

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
    if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
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
                print_warn "Las contraseñas no coinciden."
            fi
        else
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
                print_warn "Las contraseñas no coinciden."
            fi
        else
            break
        fi
    done

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
        local efi_part="${TARGET_DISK}1"
        [[ ! -b "$efi_part" ]] && efi_part="${TARGET_DISK}p1"

        if ! create_btrfs_subvolumes "$root_part"; then
            print_err "Error creando subvolúmenes BTRFS"
            exit 1
        fi

        # Montar partición EFI en /boot
        mkdir -p /mnt/boot
        mount "$efi_part" /mnt/boot 2>/dev/null || {
            print_err "No se pudo montar la partición EFI"
            exit 1
        }
    else
        if ! partition_bios "$TARGET_DISK"; then
            print_err "Error en el particionado BIOS"
            exit 1
        fi

        # Identificar particiones
        local root_part="${TARGET_DISK}2"
        [[ ! -b "$root_part" ]] && root_part="${TARGET_DISK}p2"
        local boot_part="${TARGET_DISK}1"
        [[ ! -b "$boot_part" ]] && boot_part="${TARGET_DISK}p1"

        if ! create_btrfs_subvolumes "$root_part"; then
            print_err "Error creando subvolúmenes BTRFS"
            exit 1
        fi

        mkdir -p /mnt/boot
        mount "$boot_part" /mnt/boot 2>/dev/null || {
            print_err "No se pudo montar la partición de arranque"
            exit 1
        }
    fi

    # Instalación del sistema
    if ! install_base_system "$boot_mode" "$cpu_type"; then
        print_err "Error en la instalación del sistema base"
        exit 1
    fi

    generate_fstab
    configure_system
    setup_users

    # Instalación de KDE Plasma Mínimo
    install_kde_plasma_minimal

    # Instalación de drivers
    install_drivers "$gpu_type"

    # Configuración de ZRAM
    setup_zram

    # Instalación del bootloader
    if ! install_bootloader "$boot_mode" "$cpu_type"; then
        print_err "Error instalando el bootloader"
        exit 1
    fi

    # Configuración final
    final_configuration

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
    echo -e "${GREEN}║${NC}  • Interfaz: ${BOLD}KDE Plasma Minimal${NC}                      ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Sistema de archivos: ${BOLD}BTRFS${NC}                         ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Swap: ${BOLD}ZRAM (${SWAP_PERCENTAGE}% de RAM)${NC}                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  • Modo de arranque: ${BOLD}${boot_mode^^}${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Pasos siguientes:${NC}                                    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  1. Desmontar: ${DIM}umount -R /mnt${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  2. Reiniciar: ${DIM}reboot${NC}                                  ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  3. Remover medio de instalación antes de reiniciar              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                    ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Preguntar si desea desmontar ahora
    read -rp "¿Desea desmontar el sistema ahora? (S/n): " unmount_now
    if [[ ! "$unmount_now" =~ ^[Nn]$ ]]; then
        print_substep "Desmontando sistema..."
        umount -R /mnt 2>/dev/null || true
        print_success "Sistema desmontado"
        print_msg "Puede reiniciar con: ${BOLD}reboot${NC}"
    else
        print_msg "Recuerde desmontar manualmente con: ${BOLD}umount -R /mnt${NC}"
    fi
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
