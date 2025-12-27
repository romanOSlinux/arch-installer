#!/bin/bash
# Arch Linux Auto Installer with KDE Plasma Minimal
# Detects BIOS/UEFI, CPU and GPU automatically

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
    CPU_VENDOR=$(grep -m1 -oP 'vendor_id\s*:\s*\K\w+' /proc/cpuinfo)
    if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        CPU_VENDOR="intel"
        log "INFO" "CPU Intel detectado"
    elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        CPU_VENDOR="amd"
        log "INFO" "CPU AMD detectado"
    else
        CPU_VENDOR="unknown"
        log "WARN" "Vendor de CPU no reconocido"
    fi
    
    # Detect GPU vendor
    if lspci | grep -i "nvidia" &> /dev/null; then
        GPU_VENDOR="nvidia"
        log "INFO" "GPU NVIDIA detectada"
    elif lspci | grep -i "amd" &> /dev/null; then
        GPU_VENDOR="amd"
        log "INFO" "GPU AMD detectada"
    elif lspci | grep -i "intel" &> /dev/null; then
        GPU_VENDOR="intel"
        log "INFO" "GPU Intel detectada"
    else
        GPU_VENDOR="unknown"
        log "WARN" "Vendor de GPU no reconocido"
    fi
    
    # Show available disks
    log "INFO" "Discos disponibles:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "^sd|^nvme|^vd"
}

# Get user input
get_user_input() {
    echo -e "${GREEN}=== Configuración de Instalación ===${NC}"
    
    # Select disk
    echo -e "\n${YELLOW}Discos disponibles:${NC}"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "disk"
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
    done
    
    # Passwords
    while [[ -z "$ROOT_PASSWORD" ]]; do
        echo -n "Contraseña para root: "
        read -s ROOT_PASSWORD
        echo
    done
    
    while [[ -z "$USER_PASSWORD" ]]; do
        echo -n "Contraseña para $USERNAME: "
        read -s USER_PASSWORD
        echo
    done
    
    # Timezone
    read -p "Zona horaria [America/Mexico_City]: " input
    TIMEZONE="${input:-America/Mexico_City}"
    
    # Swap size
    read -p "Tamaño de swap en GB [8]: " input
    SWAP_SIZE="${input:-8}"
    
    # Confirmation
    echo -e "\n${RED}ADVERTENCIA: Todos los datos en $DISK serán destruidos.${NC}"
    read -p "¿Continuar con la instalación? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[Ss]$ ]]; then
        log "INFO" "Instalación cancelada por el usuario"
        exit 0
    fi
}

# Partitioning
partition_disk() {
    log "INFO" "Creando particiones en $DISK..."
    
    # Clear existing partition table
    sgdisk -Z "$DISK"
    partprobe "$DISK"
    
    if [[ $IS_UEFI -eq 1 ]]; then
        # UEFI partitioning
        log "INFO" "Creando tabla de particiones GPT para UEFI"
        
        # Create partitions
        # 1: EFI system partition (512M)
        # 2: Swap partition
        # 3: Root partition (rest of disk)
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
        mkfs.fat -F32 "$EFI_PART"
        mkswap "$SWAP_PART"
        mkfs.ext4 "$ROOT_PART"
        
        # Mount partitions
        swapon "$SWAP_PART"
        mount "$ROOT_PART" /mnt
        mkdir -p /mnt/boot/efi
        mount "$EFI_PART" /mnt/boot/efi
    else
        # BIOS partitioning
        log "INFO" "Creando tabla de particiones MBR para BIOS"
        
        # Create partitions using fdisk
        echo -e "o\nn\np\n1\n\n+512M\nn\np\n2\n\n+${SWAP_SIZE}G\nn\np\n3\n\n\nt\n2\n82\nw" | fdisk "$DISK"
        
        # Set partition variables
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
        mkfs.ext4 "$BOOT_PART"
        mkswap "$SWAP_PART"
        mkfs.ext4 "$ROOT_PART"
        
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
    
    # Update mirrorlist
    log "INFO" "Actualizando mirrorlist..."
    reflector --country 'United States' --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
    
    # Install base packages
    pacstrap /mnt base base-devel linux linux-firmware
    
    # Generate fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    log "INFO" "Sistema base instalado"
}

# Configure system
configure_system() {
    log "INFO" "Configurando sistema..."
    
    # Create chroot script
    cat > /mnt/configure.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Variables
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

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen

# Network configuration
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME
HOSTS_EOF

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
useradd -m -G wheel,audio,video,storage -s /bin/bash "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Configure sudoers
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Install basic packages
pacman -Sy --noconfirm \
    networkmanager \
    grub \
    efibootmgr \
    dosfstools \
    mtools \
    git \
    curl \
    wget \
    nano \
    vim \
    htop \
    neofetch

# Install CPU microcode
if [[ "$CPU_VENDOR" == "intel" ]]; then
    pacman -S --noconfirm intel-ucode
elif [[ "$CPU_VENDOR" == "amd" ]]; then
    pacman -S --noconfirm amd-ucode
fi

# Install GPU drivers
case "$GPU_VENDOR" in
    "nvidia")
        pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
        ;;
    "amd")
        pacman -S --noconfirm xf86-video-amdgpu mesa vulkan-radeon
        ;;
    "intel")
        pacman -S --noconfirm xf86-video-intel mesa vulkan-intel
        ;;
    *)
        pacman -S --noconfirm mesa
        ;;
esac

# Install KDE Plasma Minimal
pacman -S --noconfirm \
    plasma-desktop \
    plasma-nm \
    plasma-pa \
    dolphin \
    konsole \
    kate \
    kdegraphics-thumbnailers \
    ffmpegthumbs \
    gwenview \
    sddm \
    sddm-kcm \
    ark \
    spectacle \
    okular \
    print-manager \
    cups \
    cups-pdf \
    system-config-printer \
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
    xdg-utils

# Enable NetworkManager
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable cups

# Install GRUB
if [[ "$IS_UEFI" -eq 1 ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK_DEVICE"
fi

# Configure GRUB
if [[ "$CPU_VENDOR" == "intel" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&intel_iommu=on /' /etc/default/grub
elif [[ "$CPU_VENDOR" == "amd" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&amd_iommu=on /' /etc/default/grub
fi

grub-mkconfig -o /boot/grub/grub.cfg

# Create user directories
sudo -u "$USERNAME" xdg-user-dirs-update

# Configure audio
echo "load-module module-switch-on-connect" >> /etc/pulse/default.pa

# Clean up
rm /configure.sh
EOF
    
    # Make script executable and run it
    chmod +x /mnt/configure.sh
    
    # Get disk device without partition number for BIOS install
    DISK_DEVICE=$(echo "$DISK" | sed 's/[0-9]*$//')
    
    # Run configuration in chroot
    arch-chroot /mnt /configure.sh \
        "$HOSTNAME" \
        "$USERNAME" \
        "$TIMEZONE" \
        "$LOCALE" \
        "$KEYMAP" \
        "$IS_UEFI" \
        "$CPU_VENDOR" \
        "$GPU_VENDOR" \
        "$ROOT_PASSWORD" \
        "$USER_PASSWORD"
    
    log "INFO" "Configuración completada"
}

# Post-installation
post_install() {
    log "INFO" "Realizando configuración post-instalación..."
    
    # Create post-install script for user
    cat > /mnt/home/$USERNAME/post_install.sh << 'EOF'
#!/bin/bash
echo "Configuración post-instalación para $USERNAME"

# Install yay (AUR helper)
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ~
rm -rf /tmp/yay

# Install additional software via yay
yay -S --noconfirm \
    visual-studio-code-bin \
    spotify \
    discord \
    latte-dock \
    plasma5-applets-virtual-desktop-bar-git

# Configure Plasma
echo "Puedes personalizar KDE Plasma desde:
1. System Settings -> Appearance
2. System Settings -> Workspace Behavior
3. System Settings -> Shortcuts"
EOF
    
    chmod +x /mnt/home/$USERNAME/post_install.sh
    chown $USERNAME:$USERNAME /mnt/home/$USERNAME/post_install.sh
    
    log "INFO" "Instalación completada exitosamente!"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Instalación completada exitosamente!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Hostname: $HOSTNAME"
    echo -e "Usuario: $USERNAME"
    echo -e "Timezone: $TIMEZONE"
    echo -e "Tipo de sistema: $([ $IS_UEFI -eq 1 ] && echo "UEFI" || echo "BIOS")"
    echo -e "CPU: $CPU_VENDOR"
    echo -e "GPU: $GPU_VENDOR"
    echo -e "\n${YELLOW}Para configuraciones adicionales, ejecuta:${NC}"
    echo -e "sudo -u $USERNAME /home/$USERNAME/post_install.sh"
    echo -e "\n${YELLOW}Reinicia el sistema:${NC}"
    echo -e "umount -R /mnt"
    echo -e "reboot"
}

# Main function
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   Arch Linux Auto Installer${NC}"
    echo -e "${BLUE}   con KDE Plasma Minimal${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    # Create log file
    > "$LOG_FILE"
    
    # Check root
    check_root
    
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
    
    # Final message
    echo -e "\n${GREEN}Log de instalación guardado en: $LOG_FILE${NC}"
}

# Run main function
main "$@"
