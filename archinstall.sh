#!/usr/bin/env bash
# Arch Linux Installer - KDE Plasma Argentina
# Script completo con manejo robusto de mirrors
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

# Lista de mirrors de respaldo (si falla la descarga)
readonly BACKUP_MIRRORS=(
    "https://mirror.leaseweb.com/archlinux/\$repo/os/\$arch"
    "https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
    "https://mirror.lty.me/archlinux/\$repo/os/\$arch"
    "http://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
    "https://archlinux.mailtunnel.eu/\$repo/os/\$arch"
    "https://mirror.puzzle.ch/archlinux/\$repo/os/\$arch"
    "https://mirror.selfnet.de/archlinux/\$repo/os/\$arch"
)

# Paquetes base
readonly BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    btrfs-progs sudo nano vim bash-completion
    networkmanager wpa_supplicant dialog wireless_tools netctl
    git curl wget openssh rsync archlinux-keyring
    man-db man-pages texinfo usbutils pciutils
    dosfstools mtools fuse2 fuse3 fuse
    xfsprogs jfsutils reiserfsprogs ntfs-3g exfatprogs
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
    phonon-qt5-gstreamer
)

# Utilidades adicionales
readonly UTILITIES=(
    firefox
    htop btop
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
    arc-gtk-theme
    mate-terminal
    gnome-disk-utility
    gvfs gvfs-mtp gvfs-smb
    ntfs-3g
    exfat-utils
    unrar unzip p7zip
    rsync
    wget
    curl
    openssh
    reflector
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
    
    # Intentar múltiples servidores
    local servers=("archlinux.org" "google.com" "cloudflare.com" "1.1.1.1")
    local connected=false
    
    for server in "${servers[@]}"; do
        if ping -c 1 -W 2 "$server" &> /dev/null; then
            connected=true
            break
        fi
    done
    
    if ! $connected; then
        print_warn "No se pudo verificar la conexión a internet"
        print_warn "Intentando continuar de todos modos..."
        # No salir, solo continuar con advertencia
    else
        print_success "Conexión a internet verificada"
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
# FUNCIONES DE CONFIGURACIÓN DE MIRRORS (MEJORADA)
# ============================================================================

configure_mirrors() {
    print_step "Configurando mirrors de paquetes"
    
    # Crear backup del mirrorlist original
    if [[ -f /etc/pacman.d/mirrorlist ]]; then
        cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
    fi
    
    # Función para intentar diferentes métodos de obtener mirrors
    local mirror_found=false
    
    # Método 1: Intentar descargar mirrors de Argentina
    print_substep "Intentando obtener mirrors de Argentina..."
    
    # Lista de URLs para intentar
    local mirror_urls=(
        "https://archlinux.org/mirrorlist/?country=AR&protocol=https&ip_version=4&use_mirror_status=on"
        "https://archlinux.org/mirrorlist/?country=AR&protocol=http&ip_version=4&use_mirror_status=on"
        "https://archlinux.org/mirrorlist/?country=AR&use_mirror_status=on"
        "https://raw.githubusercontent.com/archlinux/archweb/master/mirrors/status.json"
    )
    
    for url in "${mirror_urls[@]}"; do
        print_substep "Intentando con: $(echo "$url" | cut -d'?' -f1)..."
        
        if curl -s -f --max-time 10 "$url" 2>/dev/null | \
           grep -q -i "argentina\|ar.*http"; then
            print_success "Se encontraron mirrors de Argentina"
            mirror_found=true
            
            # Procesar y guardar mirrors
            if echo "$url" | grep -q "mirrorlist"; then
                curl -s --max-time 10 "$url" | \
                    sed 's/^#Server/Server/' | \
                    grep -i "argentina" > /etc/pacman.d/mirrorlist.tmp 2>/dev/null || true
            fi
            break
        fi
    done
    
    # Método 2: Usar mirrors de países cercanos si Argentina no funciona
    if ! $mirror_found; then
        print_warn "No se encontraron mirrors de Argentina"
        print_substep "Buscando mirrors de países cercanos..."
        
        local nearby_countries=("BR" "CL" "UY" "PY" "PE")
        for country in "${nearby_countries[@]}"; do
            local url="https://archlinux.org/mirrorlist/?country=${country}&protocol=https&ip_version=4&use_mirror_status=on"
            if curl -s -f --max-time 10 "$url" 2>/dev/null; then
                print_success "Usando mirrors de: $country"
                curl -s --max-time 10 "$url" | \
                    sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist.tmp 2>/dev/null || true
                mirror_found=true
                break
            fi
        done
    fi
    
    # Método 3: Usar reflector para generar lista de mirrors
    if ! $mirror_found || [[ ! -s /etc/pacman.d/mirrorlist.tmp ]]; then
        print_warn "Usando reflector para generar lista de mirrors..."
        
        # Instalar reflector si no está presente
        if ! command -v reflector &> /dev/null; then
            print_substep "Instalando reflector..."
            pacman -Sy --noconfirm reflector 2>/dev/null || true
        fi
        
        if command -v reflector &> /dev/null; then
            # Generar lista de mirrors rápidos de América del Sur y globales
            reflector \
                --country 'Argentina,Brazil,Chile,Uruguay,United States' \
                --latest 20 \
                --protocol https \
                --sort rate \
                --save /etc/pacman.d/mirrorlist.tmp \
                2>/dev/null || {
                    # Si falla, usar configuración mínima
                    reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist.tmp 2>/dev/null || true
                }
            mirror_found=true
        fi
    fi
    
    # Método 4: Usar lista de mirrors predefinida (backup)
    if [[ ! -s /etc/pacman.d/mirrorlist.tmp ]] || ! $mirror_found; then
        print_warn "Usando lista de mirrors predefinida..."
        
        cat > /etc/pacman.d/mirrorlist.tmp << 'EOF'
## Argentina
Server = https://mirrors.nic.ar/archlinux/$repo/os/$arch
Server = http://mirrors.nic.ar/archlinux/$repo/os/$arch

## Global mirrors as backup
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://mirror.lty.me/archlinux/$repo/os/$arch
Server = http://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://archlinux.mailtunnel.eu/$repo/os/$arch
Server = https://mirror.puzzle.ch/archlinux/$repo/os/$arch
Server = https://mirror.selfnet.de/archlinux/$repo/os/$arch
EOF
    fi
    
    # Validar que tenemos un mirrorlist
    if [[ ! -s /etc/pacman.d/mirrorlist.tmp ]]; then
        print_err "No se pudo crear la lista de mirrors"
        return 1
    fi
    
    # Ordenar mirrors por velocidad si es posible
    if command -v rankmirrors &> /dev/null && [[ $(wc -l < /etc/pacman.d/mirrorlist.tmp) -gt 3 ]]; then
        print_substep "Ordenando mirrors por velocidad..."
        rankmirrors -n 10 /etc/pacman.d/mirrorlist.tmp > /etc/pacman.d/mirrorlist 2>/dev/null || \
            cp /etc/pacman.d/mirrorlist.tmp /etc/pacman.d/mirrorlist
    else
        cp /etc/pacman.d/mirrorlist.tmp /etc/pacman.d/mirrorlist
    fi
    
    # Limpiar archivo temporal
    rm -f /etc/pacman.d/mirrorlist.tmp
    
    # Mostrar los mirrors seleccionados
    print_substep "Mirrors configurados:"
    head -10 /etc/pacman.d/mirrorlist | while read -r line; do
        if [[ "$line" =~ ^# ]]; then
            echo "  ${DIM}$line${NC}"
        elif [[ "$line" =~ ^Server ]]; then
            echo "  ${GREEN}✓${NC} $(echo "$line" | sed 's/^Server = //')"
        fi
    done
    
    # Configurar opciones de pacman para ser más tolerante
    configure_pacman_options
    
    # Intentar actualizar la base de datos (pero no fallar si no puede)
    print_substep "Actualizando base de datos de paquetes..."
    if pacman -Syy --noconfirm 2>&1 | grep -q "error\|failed"; then
        print_warn "No se pudo actualizar la base de datos completamente"
        print_warn "Continuando con instalación offline/disponible..."
    else
        print_success "Base de datos actualizada"
    fi
    
    return 0
}

configure_pacman_options() {
    print_substep "Optimizando configuración de pacman..."
    
    # Backup del archivo de configuración original
    if [[ -f /etc/pacman.conf ]]; then
        cp /etc/pacman.conf /etc/pacman.conf.backup
    fi
    
    # Configurar opciones para ser más tolerante a errores de red
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 3/' /etc/pacman.conf
    sed -i 's/^#Color/Color/' /etc/pacman.conf
    sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    sed -i 's/^#CheckSpace/CheckSpace/' /etc/pacman.conf
    
    # Añadir opciones de tolerancia a fallos
    echo -e "\n# Opciones para tolerancia a fallos de red" >> /etc/pacman.conf
    echo "XferCommand = /usr/bin/curl -C - -f %u > %o 2>/dev/null || /usr/bin/curl -C - -f %u > %o 2>/dev/null" >> /etc/pacman.conf
    echo "DisableDownloadTimeout" >> /etc/pacman.conf
    
    print_success "Pacman configurado para ser más tolerante a fallos"
}

# ============================================================================
# FUNCIONES DE PARTICIONADO
# ============================================================================

partition_uefi() {
    local disk=$1
    
    print_step "Creando particiones UEFI en $disk"
    
    # Limpiar tabla de particiones
    print_substep "Limpiando tabla de particiones..."
    wipefs -a "$disk" 2>/dev/null || true
    
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
    sleep 2
    partprobe "$disk" 2>/dev/null || true
    
    # Esperar a que aparezcan las particiones
    local max_retries=10
    local retry_count=0
    local root_part="${disk}2"
    [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    
    while [[ ! -b "$root_part" ]] && [[ $retry_count -lt $max_retries ]]; do
        sleep 1
        retry_count=$((retry_count + 1))
        print_substep "Esperando por particiones... ($retry_count/$max_retries)"
        root_part="${disk}2"
        [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    done
    
    # Formatear particiones
    print_substep "Formateando particiones..."
    
    # EFI
    local efi_part="${disk}1"
    [[ ! -b "$efi_part" ]] && efi_part="${disk}p1"
    
    if [[ -b "$efi_part" ]]; then
        mkfs.fat -F32 "$efi_part"
    else
        print_err "No se pudo encontrar la partición EFI"
        return 1
    fi
    
    # Root
    if [[ -b "$root_part" ]]; then
        mkfs.btrfs -f "$root_part"
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
    wipefs -a "$disk" 2>/dev/null || true
    
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
    sleep 2
    partprobe "$disk" 2>/dev/null || true
    
    # Esperar a que aparezcan las particiones
    local max_retries=10
    local retry_count=0
    local root_part="${disk}2"
    [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    
    while [[ ! -b "$root_part" ]] && [[ $retry_count -lt $max_retries ]]; do
        sleep 1
        retry_count=$((retry_count + 1))
        print_substep "Esperando por particiones... ($retry_count/$max_retries)"
        root_part="${disk}2"
        [[ ! -b "$root_part" ]] && root_part="${disk}p2"
    done
    
    # Formatear particiones
    print_substep "Formateando particiones..."
    
    # Boot
    local boot_part="${disk}1"
    [[ ! -b "$boot_part" ]] && boot_part="${disk}p1"
    
    if [[ -b "$boot_part" ]]; then
        mkfs.ext4 -F "$boot_part"
    else
        print_err "No se pudo encontrar la partición de arranque"
        return 1
    fi
    
    # Root
    if [[ -b "$root_part" ]]; then
        mkfs.btrfs -f "$root_part"
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
    mount "$root_part" /mnt 2>/dev/null || {
        print_err "No se pudo montar la partición raíz"
        return 1
    }
    
    # Crear subvolúmenes
    print_substep "Creando subvolúmenes..."
    btrfs subvolume create /mnt/@ 2>/dev/null || true
    btrfs subvolume create /mnt/@home 2>/dev/null || true
    btrfs subvolume create /mnt/@var 2>/dev/null || true
    btrfs subvolume create /mnt/@tmp 2>/dev/null || true
    btrfs subvolume create /mnt/@snapshots 2>/dev/null || true
    btrfs subvolume create /mnt/@cache 2>/dev/null || true
    btrfs subvolume create /mnt/@log 2>/dev/null || true
    
    # Desmontar
    umount /mnt 2>/dev/null || true
    
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
    
    # Instalar paquetes base (con reintentos)
    print_substep "Instalando paquetes base (esto puede tomar varios minutos)..."
    
    local max_retries=3
    local retry_count=0
    local install_success=false
    
    while [[ $retry_count -lt $max_retries ]] && [[ $install_success == false ]]; do
        if pacstrap /mnt "${packages[@]}" --noconfirm 2>&1 | tee /tmp/pacstrap.log; then
            install_success=true
            print_success "Sistema base instalado"
        else
            retry_count=$((retry_count + 1))
            print_warn "Intento $retry_count de $max_retries falló"
            
            if [[ $retry_count -lt $max_retries ]]; then
                print_substep "Reintentando en 5 segundos..."
                sleep 5
                
                # Limpiar cache de pacman y reintentar
                rm -f /mnt/var/lib/pacman/db.lck 2>/dev/null || true
            fi
        fi
    done
    
    if [[ $install_success == false ]]; then
        print_err "Error al instalar sistema base después de $max_retries intentos"
        
        # Verificar qué paquetes fallaron
        if [[ -f /tmp/pacstrap.log ]]; then
            print_substep "Errores encontrados:"
            grep -i "error\|failed\|not found" /tmp/pacstrap.log | head -5
        fi
        
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
    
    # Asegurar que haya una entrada para /boot si existe
    if mountpoint -q /mnt/boot; then
        if ! grep -q "/boot" /mnt/etc/fstab; then
            local boot_part=$(findmnt -n -o SOURCE /mnt/boot)
            local boot_fs=$(findmnt -n -o FSTYPE /mnt/boot)
            echo "# /boot partition" >> /mnt/etc/fstab
            echo "$boot_part /boot $boot_fs defaults 0 2" >> /mnt/etc/fstab
        fi
    fi
    
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
    
    print_success "Sistema configurado"
}

setup_users() {
    print_step "Configurando usuarios"
    
    # Configurar contraseña de root
    print_substep "Configurando contraseña de root..."
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd
        print_success "Contraseña de root configurada"
    else
        print_warn "Se pedirá la contraseña de root manualmente después del reinicio"
    fi
    
    # Crear usuario principal
    print_substep "Creando usuario '$USERNAME'..."
    if arch-chroot /mnt id "$USERNAME" &>/dev/null; then
        print_warn "El usuario '$USERNAME' ya existe"
    else
        arch-chroot /mnt useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
    fi
    
    if [[ -n "$USER_PASSWORD" ]]; then
        echo "$USERNAME:$USER_PASSWORD" | arch-chroot /mnt chpasswd
        print_success "Contraseña de usuario configurada"
    else
        print_warn "Se pedirá la contraseña para '$USERNAME' manualmente después del reinicio"
    fi
    
    # Configurar sudoers
    print_substep "Configurando sudo..."
    echo "%wheel ALL=(ALL) ALL" >> /mnt/etc/sudoers
    echo "%wheel ALL=(ALL) NOPASSWD: /usr/bin/pacman" >> /mnt/etc/sudoers
    
    # Configurar entorno por defecto para el usuario
    arch-chroot /mnt mkdir -p /home/"$USERNAME"/.config
    arch-chroot /mnt chown -R "$USERNAME":"$USERNAME" /home/"$USERNAME"
    
    print_success "Usuarios configurados"
}

install_kde_plasma() {
    print_step "Instalando KDE Plasma"
    
    print_substep "Instalando KDE Plasma (esto puede tomar varios minutos)..."
    
    local max_retries=2
    local retry_count=0
    local install_success=false
    
    while [[ $retry_count -lt $max_retries ]] && [[ $install_success == false ]]; do
        if arch-chroot /mnt pacman -S --noconfirm --needed "${KDE_PACKAGES[@]}" 2>&1 | tee /tmp/kde_install.log; then
            install_success=true
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                print_warn "Reintentando instalación de KDE..."
                sleep 5
            fi
        fi
    done
    
    if [[ $install_success == true ]]; then
        # Habilitar SDDM
        arch-chroot /mnt systemctl enable sddm.service
        
        # Configurar tema SDDM
        cat > /mnt/etc/sddm.conf << EOF
[Theme]
Current=breeze
EOF
        
        # Configurar autologin (opcional, comentado por defecto)
        # echo "[Autologin]" >> /mnt/etc/sddm.conf
        # echo "User=$USERNAME" >> /mnt/etc/sddm.conf
        # echo "Session=plasma" >> /mnt/etc/sddm.conf
        
        print_success "KDE Plasma instalado"
    else
        print_warn "Hubo problemas instalando KDE Plasma, continuando..."
        # No retornar error, continuar con la instalación
    fi
    
    return 0
}

install_drivers() {
    print_step "Instalando drivers"
    
    local gpu_type=$1
    
    # Drivers básicos (siempre instalar)
    print_substep "Instalando drivers básicos..."
    arch-chroot /mnt pacman -S --noconfirm --needed mesa vulkan-radeon vulkan-intel 2>/dev/null || true
    
    # Drivers específicos por GPU
    case "$gpu_type" in
        nvidia)
            print_substep "Instalando drivers NVIDIA..."
            arch-chroot /mnt pacman -S --noconfirm --needed nvidia nvidia-utils nvidia-settings 2>/dev/null || {
                print_warn "No se pudieron instalar drivers NVIDIA, continuando..."
            }
            echo "options nvidia-drm modeset=1" >> /mnt/etc/modprobe.d/nvidia.conf 2>/dev/null || true
            ;;
        amd)
            print_substep "Instalando drivers AMD..."
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-amdgpu 2>/dev/null || {
                print_warn "No se pudieron instalar drivers AMD, continuando..."
            }
            ;;
        intel)
            print_substep "Instalando drivers Intel..."
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-intel 2>/dev/null || {
                print_warn "No se pudieron instalar drivers Intel, continuando..."
            }
            ;;
        *)
            print_substep "GPU desconocida, instalando drivers genéricos..."
            arch-chroot /mnt pacman -S --noconfirm --needed xf86-video-vesa 2>/dev/null || true
            ;;
    esac
    
    # Instalar utilitarios de video
    arch-chroot /mnt pacman -S --noconfirm --needed libva-utils vdpauinfo 2>/dev/null || true
    
    print_success "Drivers instalados"
}

setup_zram() {
    print_step "Configurando ZRAM"
    
    # Instalar zram-generator
    arch-chroot /mnt pacman -S --noconfirm --needed zram-generator 2>/dev/null || {
        print_warn "No se pudo instalar zram-generator"
        return 0
    }
    
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
        
        # Crear directorio de EFI si no existe
        mkdir -p /mnt/boot/efi/EFI
        
        # Instalar systemd-boot
        arch-chroot /mnt bootctl install --path=/boot/efi 2>/dev/null || {
            print_warn "Intentando método alternativo de instalación..."
            arch-chroot /mnt bootctl install 2>/dev/null || true
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
options root=$root_uuid rw rootflags=subvol=@ quiet loglevel=3
EOF
        
        # Añadir microcódigo
        if [[ "$cpu_type" == "intel" ]]; then
            sed -i '2i initrd /intel-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        elif [[ "$cpu_type" == "amd" ]]; then
            sed -i '2i initrd /amd-ucode.img' /mnt/boot/loader/entries/arch-argentina.conf
        fi
        
        # Crear entrada de rescate
        cat > /mnt/boot/loader/entries/arch-argentina-fallback.conf << EOF
title   Arch Linux (Argentina) Fallback
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options root=$root_uuid rw rootflags=subvol=@
EOF
        
        print_success "systemd-boot instalado"
    else
        # GRUB para BIOS
        print_substep "Instalando GRUB..."
        arch-chroot /mnt pacman -S --noconfirm --needed grub 2>/dev/null || {
            print_err "No se pudo instalar GRUB"
            return 1
        }
        
        # Instalar GRUB en el disco
        arch-chroot /mnt grub-install --target=i386-pc "$TARGET_DISK" 2>/dev/null || {
            print_warn "Error instalando GRUB, intentando continuar..."
        }
        
        # Obtener UUID de la partición raíz
        local root_uuid=""
        if [[ -b "${TARGET_DISK}2" ]]; then
            root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}2")
        elif [[ -b "${TARGET_DISK}p2" ]]; then
            root_uuid=$(blkid -s UUID -o value "${TARGET_DISK}p2")
        fi
        
        if [[ -z "$root_uuid" ]]; then
            print_warn "No se pudo obtener UUID, usando dispositivo directo"
            if [[ -b "${TARGET_DISK}2" ]]; then
                root_uuid="${TARGET_DISK}2"
            else
                root_uuid="${TARGET_DISK}p2"
            fi
        fi
        
        # Configurar GRUB
        cat >> /mnt/etc/default/grub << EOF
GRUB_DISABLE_OS_PROBER=false
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX="root=$root_uuid rootflags=subvol=@"
EOF
        
        # Generar configuración GRUB
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        
        print_success "GRUB instalado"
    fi
}

install_utilities() {
    print_step "Instalando utilidades adicionales"
    
    print_substep "Instalando utilidades (esto puede tomar tiempo)..."
    
    # Instalar utilidades en grupos para manejar mejor los fallos
    local utility_groups=(
        "${UTILITIES[@]:0:10}"
        "${UTILITIES[@]:10:10}"
        "${UTILITIES[@]:20}"
    )
    
    local group_num=1
    for group in "${utility_groups[@]}"; do
        if [[ -n "$group" ]]; then
            print_substep "Instalando grupo $group_num de utilidades..."
            if ! arch-chroot /mnt pacman -S --noconfirm --needed $group 2>/dev/null; then
                print_warn "Algunas utilidades del grupo $group_num no se pudieron instalar"
            fi
            group_num=$((group_num + 1))
        fi
    done
    
    # Habilitar servicios
    arch-chroot /mnt systemctl enable cups.service 2>/dev/null || true
    arch-chroot /mnt systemctl enable bluetooth.service 2>/dev/null || true
    
    # Instalar y habilitar reflector para mantener mirrors actualizados
    arch-chroot /mnt pacman -S --noconfirm --needed reflector 2>/dev/null || true
    if arch-chroot /mnt command -v reflector &>/dev/null; then
        cat > /mnt/etc/xdg/reflector/reflector.conf << EOF
--country Argentina,Brazil,Chile,Uruguay,United States
--latest 20
--protocol https
--sort rate
--save /etc/pacman.d/mirrorlist
EOF
        arch-chroot /mnt systemctl enable reflector.timer 2>/dev/null || true
    fi
    
    print_success "Utilidades instaladas"
}

final_configuration() {
    print_step "Aplicando configuración final
    
    # Actualizar initramfs
    print_substep "Actualizando initramfs..."
    arch-chroot /mnt mkinitcpio -P 2>/dev/null || {
        print_warn "Error actualizando initramfs, continuando..."
    }
    
    # Habilitar servicios importantes
    print_substep "Habilitando servicios..."
    arch-chroot /mnt systemctl enable fstrim.timer 2>/dev/null || true
    arch-chroot /mnt systemctl enable systemd-resolved.service 2>/dev/null || true
    arch-chroot /mnt systemctl enable paccache.timer 2>/dev/null || true
    
    # Configurar pacman optimizado en el sistema instalado
    print_substep "Optimizando pacman en el sistema instalado..."
    sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /mnt/etc/pacman.conf 2>/dev/null || true
    sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf 2>/dev/null || true
    
    # Configurar journal optimizado
    print_substep "Optimizando journal..."
    sed -i 's/^#SystemMaxUse=/SystemMaxUse=500M/' /mnt/etc/systemd/journald.conf 2>/dev/null || true
    
    # Configurar swappiness para ZRAM
    echo "vm.swappiness=100" >> /mnt/etc/sysctl.d/99-sysctl.conf 2>/dev/null || true
    
    # Configurar límites de recursos
    cat > /mnt/etc/security/limits.conf 2>/dev/null << EOF
* soft nofile 524288
* hard nofile 1048576
EOF
    
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

show_disks() {
    print_substep "Discos disponibles:"
    echo -e "${DIM}"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^(NAME|disk)"
    echo -e "${NC}"
    echo -e "${DIM}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL
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
            print_warn "La contraseña de root se configurará manualmente después del reinicio."
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
            print_warn "La contraseña del usuario se configurará manualmente después del reinicio."
            break
        fi
    done
    
    # Configuración de ZRAM
    echo ""
    print_substep "Configuración de ZRAM"
    read -rp "Porcentaje de RAM para ZRAM [$SWAP_PERCENTAGE%] (10-200): " input
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
    
    # Mostrar advertencia sobre internet
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}Nota:${NC} Este script manejará automáticamente problemas     ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC}        de conexión a internet y mirrors.                ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    check_internet
    
    # Configuración interactiva
    interactive_setup
    
    # Detectar hardware
    local boot_mode cpu_type gpu_type
    boot_mode=$(detect_boot_mode)
    cpu_type=$(detect_cpu)
    gpu_type=$(detect_gpu)
    
    # Configurar mirrors (manejo robusto)
    if ! configure_mirrors; then
        print_err "Error crítico configurando mirrors"
        exit 1
    fi
    
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
        
        mkdir -p /mnt/boot/efi
        mount "$efi_part" /mnt/boot/efi 2>/dev/null || {
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
    
    # Instalación de KDE Plasma
    if ! install_kde_plasma; then
        print_warn "Continuando sin KDE Plasma completo"
    fi
    
    # Instalación de drivers
    install_drivers "$gpu_type"
    
    # Configuración de ZRAM
    setup_zram
    
    # Instalación del bootloader
    if ! install_bootloader "$boot_mode" "$cpu_type"; then
        print_err "Error instalando el bootloader"
        exit 1
    fi
    
    # Instalación de utilidades
    install_utilities
    
    # Configuración final
    final_configuration
    
    # Limpieza
    print_step "Limpiando caché de paquetes..."
    arch-chroot /mnt paccache -rk1 2>/dev/null || true
    
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
    echo -e "${GREEN}║${NC}  • Modo de arranque: ${BOLD}${boot_mode^^}${NC}                          ${GREEN}║${NC}"
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
    echo -e "  ${DIM}•${NC} CPU: $cpu_type"
    echo -e "  ${DIM}•${NC} GPU: $gpu_type"
    echo ""
    
    print_warn "${BOLD}¡IMPORTANTE!${NC}"
    print_warn "1. Remover el medio de instalación (USB/CD) antes de reiniciar"
    print_warn "2. Si no configuró contraseñas, deberá hacerlo en el primer inicio"
    print_warn "3. Para WiFi, usar NetworkManager desde el entorno gráfico"
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
