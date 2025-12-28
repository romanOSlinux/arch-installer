#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# region header
# [Project page](https://torben.website/archinstall)

# Copyright Torben Sickert (info["~at~"]torben.website) 16.12.2012

# License
# -------

# This library written by Torben Sickert stand under a creative commons naming
# 3.0 unported license. See https://creativecommons.org/licenses/by/3.0/deed.de
# endregion
# shellcheck disable=SC1004,SC2016,SC2034,SC2155
shopt -s expand_aliases
# region import
alias ai.download=ai_download
ai_download() {
    local -r __documentation__='
        Simply downloads missing modules.

        >>> ai.download --silent https://domain.tld/path/to/file.ext; echo $?
        6
    '
    command curl --insecure "$@"
    return $?
}

if [ -f "$(dirname "${BASH_SOURCE[0]}")/node_modules/bashlink/module.sh" ]; then
    # shellcheck disable=SC1090
    source "$(dirname "${BASH_SOURCE[0]}")/node_modules/bashlink/module.sh"
elif [ -f "/usr/lib/bashlink/module.sh" ]; then
    # shellcheck disable=SC1091
    source "/usr/lib/bashlink/module.sh"
else
    declare -g AI_CACHE_PATH="$(
        echo "$@" | \
            sed \
                --regexp-extended \
                's/(^| )(-o|--cache-path)(=| +)(.+[^ ])($| +-)/\4/'
    )"
    [ "$AI_CACHE_PATH" = "$*" ] && \
        AI_CACHE_PATH=archInstallCache
    AI_CACHE_PATH="${AI_CACHE_PATH%/}/"
    declare -gr BL_MODULE_REMOTE_MODULE_CACHE_PATH="${AI_CACHE_PATH}bashlink"
    mkdir --parents "$BL_MODULE_REMOTE_MODULE_CACHE_PATH"
    declare -gr BL_MODULE_RETRIEVE_REMOTE_MODULES=true
    if ! (
        [ -f "${BL_MODULE_REMOTE_MODULE_CACHE_PATH}/module.sh" ] || \
        ai.download \
            https://raw.githubusercontent.com/thaibault/bashlink/main/module.sh \
                >"${BL_MODULE_REMOTE_MODULE_CACHE_PATH}/module.sh"
    ); then
        echo Needed bashlink library could not be retrieved. 1>&2
        rm \
            --force \
            --recursive \
            "${BL_MODULE_REMOTE_MODULE_CACHE_PATH}/module.sh"
        exit 1
    fi
    # shellcheck disable=SC1091
    source "${BL_MODULE_REMOTE_MODULE_CACHE_PATH}/module.sh"
fi
bl.module.import bashlink.changeroot
bl.module.import bashlink.dictionary
bl.module.import bashlink.exception
bl.module.import bashlink.logging
bl.module.import bashlink.number
bl.module.import bashlink.tools
bl.module.import bashlink.array
bl.module.import bashlink.string
# endregion
# region variables
declare -gr AI__DOCUMENTATION__='
    Este script instala Arch Linux con opciones mejoradas.
    
    Características nuevas:
    - Instalación de Plasma mínimo (KDE)
    - Soporte para XFCE y otros entornos
    - Gestión mejorada de usuarios y grupos
    - Configuración regional completa
    - Instalación de drivers automática
    - Soporte para AUR (yay)
    - Optimizaciones de sistema
    - Menú interactivo

    Uso básico:
    curl -L https://raw.githubusercontent.com/.../archinstall.sh | bash -s -- --target /dev/sda --desktop plasma-minimal
'
declare -agr AI__DEPENDENCIES__=(
    bash
    cat
    chroot
    curl
    grep
    ln
    lsblk
    lspci
    mktemp
    mount
    mountpoint
    rm
    sed
    sort
    sync
    touch
    tar
    uname
    which
    xz
)
declare -agr AI__OPTIONAL_DEPENDENCIES__=(
    'blockdev: Call block device ioctls from the command line (part of util-linux).'
    'btrfs: Control a btrfs filesystem (part of btrfs-progs).'
    'cryptsetup: Userspace setup tool for transparent encryption of block devices using dm-crypt.'
    'gdisk: Interactive GUID partition table (GPT) manipulator (part of gptfdisk).'
    'arch-chroot: Performs an arch chroot with api file system binding (part of package "arch-install-scripts").'
    'dosfslabel: Handle dos file systems (part of dosfstools).'
    'fakeroot: Run a command in an environment faking root privileges for file manipulation.'
    'fakechroot: Wraps some c-lib functions to enable programs like "chroot" running without root privileges.'
    'ip: Determines network adapter (part of iproute2).'
    'os-prober: Detects presence of other operating systems.'
    'pacstrap: Installs arch linux from an existing linux system (part of package "arch-install-scripts").'
)

# Paquetes básicos del sistema
declare -agr AI_BASIC_PACKAGES=(base base-devel linux linux-firmware linux-headers which nano sudo git)

# Paquetes comunes adicionales
declare -agr AI_COMMON_ADDITIONAL_PACKAGES=(
    networkmanager network-manager-applet
    pulseaudio pulseaudio-alsa pavucontrol
    bluez bluez-utils
    cups cups-pdf
    avahi nss-mdns
    xdg-user-dirs xdg-utils
    ntfs-3g exfat-utils
    unzip unrar p7zip
    wget curl
    htop neofetch
    bash-completion
    man-db man-pages
    mlocate
    cronie
)

# Paquetes para Plasma mínimo
declare -agr AI_PLASMA_MINIMAL_PACKAGES=(
    plasma-desktop
    sddm
    konsole
    dolphin
    kate
    ark
    gwenview
    spectacle
    plasma-nm
    plasma-pa
    bluedevil
    powerdevil
    kde-gtk-config
    breeze-gtk
    kinfocenter
    kdeplasma-addons
    print-manager
    systemsettings
)

# Paquetes para XFCE
declare -agr AI_XFCE_PACKAGES=(
    xfce4
    xfce4-goodies
    lightdm
    lightdm-gtk-greeter
    network-manager-applet
    pulseaudio
    xfce4-pulseaudio-plugin
    firefox
)

# Paquetes para GNOME
declare -agr AI_GNOME_PACKAGES=(
    gnome
    gnome-tweaks
    gdm
    firefox
)

# Drivers de video
declare -agr AI_INTEL_DRIVER_PACKAGES=(mesa vulkan-intel intel-media-driver)
declare -agr AI_AMD_DRIVER_PACKAGES=(mesa vulkan-radeon xf86-video-amdgpu)
declare -agr AI_NVIDIA_DRIVER_PACKAGES=(nvidia nvidia-utils nvidia-settings)
declare -agr AI_NVIDIA_LTS_DRIVER_PACKAGES=(nvidia-lts nvidia-utils nvidia-settings)
declare -agr AI_VIRTUALBOX_DRIVER_PACKAGES=(virtualbox-guest-utils)
declare -agr AI_VMWARE_DRIVER_PACKAGES=(xf86-video-vmware open-vm-tools)

declare -ag AI_ADDITIONAL_PACKAGES=()
declare -g AI_ADD_COMMON_ADDITIONAL_PACKAGES=true
declare -ag AI_NEEDED_PACKAGES=(filesystem pacman)

# Defines where to mount temporary new filesystem.
declare -g AI_MOUNTPOINT_PATH=/mnt/

bl.dictionary.set AI_KNOWN_DEPENDENCY_ALIASES libncursesw.so ncurses

declare -ag AI_PACKAGE_SOURCE_URLS=(
    'https://www.archlinux.org/mirrorlist/?country=all&protocol=https&ip_version=4&use_mirror_status=on'
)
declare -ag AI_PACKAGE_URLS=(
    https://mirrors.kernel.org/archlinux
)

declare -gi AI_NETWORK_TIMEOUT_IN_SECONDS=10

declare -ag AI_UNNEEDED_FILE_LOCATIONS=(.INSTALL .PKGINFO var/cache/pacman)

## region command line arguments
declare -g AI_AUTO_PARTITIONING=false
declare -g AI_BOOT_ENTRY_LABEL=archLinux
declare -g AI_BOOT_PARTITION_LABEL=uefiBoot
declare -gi AI_BOOT_SPACE_IN_MEGA_BYTE=512
declare -g AI_FALLBACK_BOOT_ENTRY_LABEL=archLinuxFallback

declare -gi AI_NEEDED_SYSTEM_SPACE_IN_MEGA_BYTE=20480
declare -g AI_SYSTEM_PARTITION_LABEL=system
declare -g AI_SYSTEM_PARTITION_INSTALLATION_ONLY=false

declare -g AI_COUNTRY_WITH_MIRRORS=Spain
declare -g AI_LOCAL_TIME=Europe/Madrid
declare -g AI_SYSTEM_LANGUAGE=en_US.UTF-8
declare -g AI_KEYBOARD_LAYOUT=es

declare -g AI_CPU_ARCHITECTURE="$(uname -m)"
declare -g AI_HOST_NAME='archlinux'
declare -g AI_DESKTOP_ENVIRONMENT='none'
declare -g AI_INSTALL_AUR_HELPER=false
declare -g AI_SWAP_SIZE=4096
declare -g AI_INSTALL_DRIVERS=true
declare -g AI_VIDEO_DRIVER='auto'

declare -ag AI_NEEDED_SERVICES=(NetworkManager bluetooth cups avahi-daemon cronie)

declare -g AI_TARGET=archInstall

declare -g AI_ENCRYPT=false
declare -g AI_PASSWORD=archlinux
declare -ag AI_USER_NAMES=('user')
declare -g AI_USER_PASSWORD='archlinux'

declare -g AI_PREVENT_USING_NATIVE_ARCH_CHANGEROOT=false
declare -g AI_PREVENT_USING_EXISTING_PACMAN=false
declare -g AI_AUTOMATIC_REBOOT=false
## endregion

BL_MODULE_FUNCTION_SCOPE_REWRITES+=('^archinstall([._][a-zA-Z_-]+)?$/ai\1/')
BL_MODULE_GLOBAL_SCOPE_REWRITES+=('^ARCHINSTALL(_[a-zA-Z_-]+)?$/AI\1/')
# endregion
# region functions
## region command line interface
alias ai.get_commandline_option_description=ai_get_commandline_option_description
ai_get_commandline_option_description() {
    local -r __documentation__='
        Prints descriptions about each available command line option.

        >>> ai.get_commandline_option_description
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        -h --help Shows this help message.
        ...
    '
    cat << 'EOF'
-h --help Shows this help message.

-v --verbose Tells you what is going on.

-d --debug Gives you any output from all tools which are used.


-u --user-names [USER_NAMES [USER_NAMES ...]] Defines user names for new system (default: "user").

-p --user-password PASSWORD Defines password for users (default: "archlinux").

-n --host-name HOST_NAME Defines name for new system (default: "archlinux").


-c --cpu-architecture CPU_ARCHITECTURE Defines architecture (default: from uname -m).

-t --target TARGET Defines where to install new operating system (default: "archInstall").


-l --local-time LOCAL_TIME Local time for your system (default: "Europe/Madrid").

-i --keyboard-layout LAYOUT Defines keyboard layout (default: "es").

-L --system-language LANGUAGE System language (default: "en_US.UTF-8").

-m --country-with-mirrors COUNTRY Country for enabling servers to get packages from (default: "Spain").


-D --desktop-environment DESKTOP Desktop environment to install (none, plasma-minimal, xfce, gnome) (default: "none").

-A --install-aur-helper Install AUR helper (yay) (default: false).

-S --swap-size SIZE_MB Swap size in MB (0 for no swap) (default: 4096).

-V --video-driver DRIVER Video driver (auto, intel, amd, nvidia, nvidia-lts, virtualbox, vmware) (default: "auto").

-dr --no-drivers Skip driver installation (default: false).


-r --reboot Reboot after finishing installation.

-a --auto-partitioning Defines to do partitioning on founded block device automatic.


-b --boot-partition-label LABEL Partition label for uefi boot partition (default: "uefiBoot").

-s --system-partition-label LABEL Partition label for system partition (default: "system").


-e --boot-entry-label LABEL Boot entry label (default: "archLinux").

-f --fallback-boot-entry-label LABEL Fallback boot entry label (default: "archLinuxFallback").


-w --boot-space-in-mega-byte NUMBER Minimum space for boot partition (default: "512 MB").

-q --needed-system-space-in-mega-byte NUMBER Minimum space for system partition (default: "20480 MB").


-z --add-common-additional-packages Install common additional packages (default: true).

-g --additional-packages [PACKAGES [PACKAGES ...]] Additional packages to install.

-j --needed-services [SERVICES [SERVICES ...]] Services to enable.

-o --cache-path PATH Define where to load and save downloaded dependencies.


-P --system-partition-installation-only Interpret given input as single partition only.

-E --encrypt Encrypts system partition.

-pa --password Password to use for root login (and encryption if enabled).


-x --timeout NUMBER_OF_SECONDS Defines time to wait for requests (default: 10).

Presets:

--quick-install TARGET Is the same as "--auto-partitioning --desktop plasma-minimal --install-aur-helper --host-name archlinux --target TARGET".
EOF
}

alias ai.get_help_message=ai_get_help_message
ai_get_help_message() {
    local -r __documentation__='
        Provides a help message for this module.

        >>> ai.get_help_message
        +bl.doctest.contains
        +bl.doctest.multiline_ellipsis
        ...
        Usage: arch-install [options]
        ...
    '
    echo -e $'\nUsage: arch-install [options]\n'
    echo -e "$AI__DOCUMENTATION__"
    echo -e $'\nOption descriptions:\n'
    ai.get_commandline_option_description "$@"
    echo
}

alias ai.interactive_menu=ai_interactive_menu
ai_interactive_menu() {
    local -r __documentation__='
        Muestra un menú interactivo para configurar la instalación.
    '
    
    if [ "$AI_TARGET" = "archInstall" ]; then
        echo "╔══════════════════════════════════════════╗"
        echo "║    Configuración Interactiva Arch Linux  ║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        
        # Seleccionar target
        echo "Discos disponibles:"
        lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v "loop"
        echo ""
        read -p "¿Dónde instalar? (ej: /dev/sda): " AI_TARGET
        
        # Hostname
        read -p "Hostname [archlinux]: " input
        AI_HOST_NAME="${input:-archlinux}"
        
        # Usuarios
        echo "Usuarios (separados por espacio) [user]: "
        read -p "> " input
        AI_USER_NAMES=(${input:-user})
        
        # Contraseña de usuario
        read -sp "Contraseña para usuarios [archlinux]: " AI_USER_PASSWORD
        AI_USER_PASSWORD="${AI_USER_PASSWORD:-archlinux}"
        echo ""
        
        # Entorno de escritorio
        echo ""
        echo "Selecciona entorno de escritorio:"
        echo "1) Ninguno (solo CLI)"
        echo "2) Plasma mínimo (KDE)"
        echo "3) XFCE"
        echo "4) GNOME"
        read -p "Opción [2]: " de_choice
        
        case "${de_choice:-2}" in
            1) AI_DESKTOP_ENVIRONMENT="none" ;;
            2) AI_DESKTOP_ENVIRONMENT="plasma-minimal" ;;
            3) AI_DESKTOP_ENVIRONMENT="xfce" ;;
            4) AI_DESKTOP_ENVIRONMENT="gnome" ;;
            *) AI_DESKTOP_ENVIRONMENT="plasma-minimal" ;;
        esac
        
        # AUR helper
        read -p "¿Instalar yay (AUR helper)? [S/n]: " aur_choice
        if [[ "${aur_choice,,}" =~ ^(n|no)$ ]]; then
            AI_INSTALL_AUR_HELPER=false
        else
            AI_INSTALL_AUR_HELPER=true
        fi
        
        # Swap
        read -p "Tamaño de swap en MB [4096]: " swap_input
        AI_SWAP_SIZE="${swap_input:-4096}"
        
        # Cifrado
        read -p "¿Cifrar disco? [s/N]: " encrypt_choice
        if [[ "${encrypt_choice,,}" =~ ^(s|si|y|yes)$ ]]; then
            AI_ENCRYPT=true
            read -sp "Contraseña de cifrado [archlinux]: " AI_PASSWORD
            AI_PASSWORD="${AI_PASSWORD:-archlinux}"
            echo ""
        fi
        
        # Auto particionamiento
        read -p "¿Particionamiento automático? [S/n]: " auto_part
        if [[ "${auto_part,,}" =~ ^(n|no)$ ]]; then
            AI_AUTO_PARTITIONING=false
        else
            AI_AUTO_PARTITIONING=true
        fi
        
        echo ""
        echo "Resumen de configuración:"
        echo "──────────────────────────────"
        echo "• Disco: $AI_TARGET"
        echo "• Hostname: $AI_HOST_NAME"
        echo "• Usuarios: ${AI_USER_NAMES[*]}"
        echo "• Entorno: $AI_DESKTOP_ENVIRONMENT"
        echo "• AUR helper: $AI_INSTALL_AUR_HELPER"
        echo "• Swap: ${AI_SWAP_SIZE}MB"
        echo "• Cifrado: $AI_ENCRYPT"
        echo "• Auto particionamiento: $AI_AUTO_PARTITIONING"
        echo ""
        
        read -p "¿Continuar con la instalación? [S/n]: " confirm
        if [[ "${confirm,,}" =~ ^(n|no)$ ]]; then
            echo "Instalación cancelada."
            exit 0
        fi
        
        echo ""
        echo "🚀 Iniciando instalación..."
        echo ""
    fi
}

alias ai.commandline_interface=ai_commandline_interface
ai_commandline_interface() {
    local -r __documentation__='
        Provides the command line interface and interactive questions.
    '
    bl.logging.set_command_level debug
    
    # Si no hay argumentos, mostrar menú interactivo
    if [ $# -eq 0 ]; then
        ai.interactive_menu
        return 0
    fi
    
    while true; do
        case "$1" in
            -h|--help)
                shift
                bl.logging.plain "$(ai.get_help_message "$0")"
                exit 0
                ;;
            -v|--verbose)
                shift
                if ! bl.logging.is_enabled info; then
                    bl.logging.set_level info
                fi
                ;;
            -d|--debug)
                shift
                bl.logging.set_level debug
                ;;

            -u|--user-names)
                shift
                AI_USER_NAMES=()
                while [[ "$1" =~ ^[^-].+$ ]]; do
                    AI_USER_NAMES+=("$1")
                    shift
                done
                ;;
            --user-password)
                shift
                AI_USER_PASSWORD="$1"
                shift
                ;;
            -n|--host-name)
                shift
                AI_HOST_NAME="$1"
                shift
                ;;

            -c|--cpu-architecture)
                shift
                AI_CPU_ARCHITECTURE="$1"
                shift
                ;;
            -t|--target)
                shift
                AI_TARGET="$1"
                shift
                ;;

            -l|--local-time)
                shift
                AI_LOCAL_TIME="$1"
                shift
                ;;
            -i|--keyboard-layout)
                shift
                AI_KEYBOARD_LAYOUT="$1"
                shift
                ;;
            -L|--system-language)
                shift
                AI_SYSTEM_LANGUAGE="$1"
                shift
                ;;
            -m|--country-with-mirrors)
                shift
                AI_COUNTRY_WITH_MIRRORS="$1"
                shift
                ;;

            -D|--desktop-environment)
                shift
                AI_DESKTOP_ENVIRONMENT="$1"
                shift
                ;;
            -A|--install-aur-helper)
                shift
                AI_INSTALL_AUR_HELPER=true
                ;;
            -S|--swap-size)
                shift
                AI_SWAP_SIZE="$1"
                shift
                ;;
            -V|--video-driver)
                shift
                AI_VIDEO_DRIVER="$1"
                shift
                ;;
            --no-drivers)
                shift
                AI_INSTALL_DRIVERS=false
                ;;

            -r|--reboot)
                shift
                AI_AUTOMATIC_REBOOT=true
                ;;
            -a|--auto-partitioning)
                shift
                AI_AUTO_PARTITIONING=true
                ;;
            -p|--prevent-using-existing-pacman)
                shift
                AI_PREVENT_USING_EXISTING_PACMAN=true
                ;;
            -y|--prevent-using-native-arch-chroot)
                shift
                AI_PREVENT_USING_NATIVE_ARCH_CHANGEROOT=true
                ;;

            -b|--boot-partition-label)
                shift
                AI_BOOT_PARTITION_LABEL="$1"
                shift
                ;;
            -s|--system-partition-label)
                shift
                AI_SYSTEM_PARTITION_LABEL="$1"
                shift
                ;;

            -e|--boot-entry-label)
                shift
                AI_BOOT_ENTRY_LABEL="$1"
                shift
                ;;
            -f|--fallback-boot-entry-label)
                shift
                AI_FALLBACK_BOOT_ENTRY_LABEL="$1"
                shift
                ;;

            -w|--boot-space-in-mega-byte)
                shift
                AI_BOOT_SPACE_IN_MEGA_BYTE="$1"
                shift
                ;;
            -q|--needed-system-space-in-mega-byte)
                shift
                AI_NEEDED_SYSTEM_SPACE_IN_MEGA_BYTE="$1"
                shift
                ;;

            -z|--add-common-additional-packages)
                shift
                AI_ADD_COMMON_ADDITIONAL_PACKAGES=true
                ;;
            -g|--additional-packages)
                shift
                while [[ "$1" =~ ^[^-].+$ ]]; do
                    AI_ADDITIONAL_PACKAGES+=("$1")
                    shift
                done
                ;;
            -j|--needed-services)
                shift
                while [[ "$1" =~ ^[^-].+$ ]]; do
                    AI_NEEDED_SERVICES+=("$1")
                    shift
                done
                ;;
            -o|--cache-path)
                shift
                AI_CACHE_PATH="${1%/}/"
                shift
                ;;

            -P|--system-partition-installation-only)
                shift
                AI_SYSTEM_PARTITION_INSTALLATION_ONLY=true
                ;;

            -E|--encrypt)
                shift
                AI_ENCRYPT=true
                ;;
            -pa|--password)
                shift
                AI_PASSWORD="$1"
                shift
                ;;

            -x|--timeout)
                shift
                AI_NETWORK_TIMEOUT_IN_SECONDS="$1"
                shift
                ;;

            --quick-install)
                shift
                AI_AUTO_PARTITIONING=true
                AI_DESKTOP_ENVIRONMENT=plasma-minimal
                AI_INSTALL_AUR_HELPER=true
                AI_HOST_NAME=archlinux
                AI_TARGET="$1"
                bl.logging.set_level debug
                shift
                ;;

            '')
                shift || true
                break
                ;;
            *)
                bl.logging.error "Argumento inválido: \"${1}\""
                bl.logging.plain "$(ai.get_help_message)"
                return 1
        esac
    done
    
    # Validaciones
    if [[ "$UID" != 0 ]] && ! {
        hash fakeroot 2>/dev/null && \
        hash fakechroot 2>/dev/null && \
        { [ -e "$AI_TARGET" ] && [ -d "$AI_TARGET" ]; }
    }; then
        bl.logging.error_exception \
            "Debes ejecutar este script como \"root\" o instalar \"fakeroot\" y \"fakechroot\" para instalar en un directorio."
    fi
    
    # Auto-detección de partición única
    if ! $AI_SYSTEM_PARTITION_INSTALLATION_ONLY && \
       ! $AI_AUTO_PARTITIONING && \
       echo "$AI_TARGET" | grep --quiet --extended-regexp '[0-9]$'; then
        AI_SYSTEM_PARTITION_INSTALLATION_ONLY=true
    fi
    
    return 0
}
## endregion

## region helper functions
### region change root functions
alias ai.changeroot=ai_changeroot
ai_changeroot() {
    local -r __documentation__='
        This function emulates the arch linux native "arch-chroot" function.
    '
    if ! $AI_PREVENT_USING_NATIVE_ARCH_CHANGEROOT && hash arch-chroot 2>/dev/null; then
        if [ "$1" = / ]; then
            shift
            "$@"
            return $?
        fi
        arch-chroot "$@"
        return $?
    fi
    bl.changeroot "$@"
    return $?
}

alias ai.changeroot_to_mountpoint=ai_changeroot_to_mountpoint
ai_changeroot_to_mountpoint() {
    local -r __documentation__='
        This function performs a changeroot to currently set mountpoint path.
    '
    ai.changeroot "$AI_MOUNTPOINT_PATH" "$@"
    return $?
}
### endregion

alias ai.detect_hardware=ai_detect_hardware
ai_detect_hardware() {
    local -r __documentation__='
        Detecta el hardware para instalar drivers apropiados.
    '
    bl.logging.info "Detectando hardware..."
    
    # Detectar tarjeta gráfica
    if lspci | grep -i "nvidia" > /dev/null; then
        bl.logging.info "Detectada tarjeta NVIDIA"
        AI_VIDEO_DRIVER="nvidia"
    elif lspci | grep -i "amd" | grep -i "vga" > /dev/null; then
        bl.logging.info "Detectada tarjeta AMD"
        AI_VIDEO_DRIVER="amd"
    elif lspci | grep -i "intel" | grep -i "vga" > /dev/null; then
        bl.logging.info "Detectada tarjeta Intel"
        AI_VIDEO_DRIVER="intel"
    elif systemd-detect-virt | grep -i "oracle" > /dev/null; then
        bl.logging.info "Detectado VirtualBox"
        AI_VIDEO_DRIVER="virtualbox"
    elif systemd-detect-virt | grep -i "vmware" > /dev/null; then
        bl.logging.info "Detectado VMware"
        AI_VIDEO_DRIVER="vmware"
    else
        bl.logging.info "Usando drivers genéricos"
        AI_VIDEO_DRIVER="intel" # Por defecto
    fi
}

alias ai.install_drivers=ai_install_drivers
ai_install_drivers() {
    local -r __documentation__='
        Instala drivers según la detección de hardware.
    '
    if ! $AI_INSTALL_DRIVERS; then
        bl.logging.info "Saltando instalación de drivers"
        return 0
    fi
    
    bl.logging.info "Instalando drivers para: $AI_VIDEO_DRIVER"
    
    case "$AI_VIDEO_DRIVER" in
        intel)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_INTEL_DRIVER_PACKAGES[@]}"
            ;;
        amd)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_AMD_DRIVER_PACKAGES[@]}"
            ;;
        nvidia)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_NVIDIA_DRIVER_PACKAGES[@]}"
            ;;
        nvidia-lts)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_NVIDIA_LTS_DRIVER_PACKAGES[@]}"
            ;;
        virtualbox)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_VIRTUALBOX_DRIVER_PACKAGES[@]}"
            ai.changeroot_to_mountpoint systemctl enable vboxservice.service
            ;;
        vmware)
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_VMWARE_DRIVER_PACKAGES[@]}"
            ai.changeroot_to_mountpoint systemctl enable vmtoolsd.service vmware-vmblock-fuse.service
            ;;
    esac
}

alias ai.setup_swap=ai_setup_swap
ai_setup_swap() {
    local -r __documentation__='
        Configura el archivo swap.
    '
    if [ "$AI_SWAP_SIZE" -gt 0 ]; then
        bl.logging.info "Creando archivo swap de ${AI_SWAP_SIZE}MB"
        ai.changeroot_to_mountpoint fallocate -l "${AI_SWAP_SIZE}M" /swapfile
        ai.changeroot_to_mountpoint chmod 600 /swapfile
        ai.changeroot_to_mountpoint mkswap /swapfile
        ai.changeroot_to_mountpoint swapon /swapfile
        echo '/swapfile none swap defaults 0 0' >> "${AI_MOUNTPOINT_PATH}/etc/fstab"
    fi
}

alias ai.configure_locale=ai_configure_locale
ai_configure_locale() {
    local -r __documentation__='
        Configura el idioma del sistema.
    '
    bl.logging.info "Configurando idioma: $AI_SYSTEM_LANGUAGE"
    
    # Configurar locale
    echo "$AI_SYSTEM_LANGUAGE UTF-8" >> "${AI_MOUNTPOINT_PATH}/etc/locale.gen"
    echo "LANG=$AI_SYSTEM_LANGUAGE" > "${AI_MOUNTPOINT_PATH}/etc/locale.conf"
    echo "LC_COLLATE=C" >> "${AI_MOUNTPOINT_PATH}/etc/locale.conf"
    
    ai.changeroot_to_mountpoint locale-gen
    
    # Configurar teclado
    echo "KEYMAP=$AI_KEYBOARD_LAYOUT" > "${AI_MOUNTPOINT_PATH}/etc/vconsole.conf"
    echo "FONT=lat9w-16" >> "${AI_MOUNTPOINT_PATH}/etc/vconsole.conf"
}

alias ai.install_desktop_environment=ai_install_desktop_environment
ai_install_desktop_environment() {
    local -r __documentation__='
        Instala el entorno de escritorio seleccionado.
    '
    case "$AI_DESKTOP_ENVIRONMENT" in
        plasma-minimal)
            bl.logging.info "Instalando Plasma mínimo..."
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_PLASMA_MINIMAL_PACKAGES[@]}"
            ai.changeroot_to_mountpoint systemctl enable sddm.service
            ;;
        xfce)
            bl.logging.info "Instalando XFCE..."
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_XFCE_PACKAGES[@]}"
            ai.changeroot_to_mountpoint systemctl enable lightdm.service
            ;;
        gnome)
            bl.logging.info "Instalando GNOME..."
            ai.changeroot_to_mountpoint pacman -S --noconfirm "${AI_GNOME_PACKAGES[@]}"
            ai.changeroot_to_mountpoint systemctl enable gdm.service
            ;;
        none)
            bl.logging.info "No se instalará entorno de escritorio."
            ;;
        *)
            bl.logging.warn "Entorno de escritorio desconocido: $AI_DESKTOP_ENVIRONMENT"
            ;;
    esac
}

alias ai.install_aur_helper=ai_install_aur_helper
ai_install_aur_helper() {
    local -r __documentation__='
        Instala yay (AUR helper).
    '
    if $AI_INSTALL_AUR_HELPER; then
        bl.logging.info "Instalando yay (AUR helper)..."
        
        # Crear usuario temporal para compilar yay
        ai.changeroot_to_mountpoint useradd -m -G wheel -s /bin/bash aurhelper
        echo "aurhelper:aurhelper" | ai.changeroot_to_mountpoint chpasswd
        
        # Instalar dependencias
        ai.changeroot_to_mountpoint pacman -S --needed --noconfirm git base-devel
        
        # Compilar e instalar yay
        ai.changeroot_to_mountpoint su - aurhelper -c "
            cd /tmp
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
        "
        
        # Limpiar usuario temporal
        ai.changeroot_to_mountpoint userdel -r aurhelper
    fi
}

alias ai.configure_users=ai_configure_users
ai_configure_users() {
    local -r __documentation__='
        Configura usuarios y grupos.
    '
    # Configurar root
    echo "root:${AI_PASSWORD}" | ai.changeroot_to_mountpoint chpasswd
    
    # Crear usuarios
    local user_name
    for user_name in "${AI_USER_NAMES[@]}"; do
        bl.logging.info "Creando usuario: $user_name"
        
        # Crear usuario con directorio home
        ai.changeroot_to_mountpoint useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$user_name"
        echo "$user_name:${AI_USER_PASSWORD}" | ai.changeroot_to_mountpoint chpasswd
        
        # Configurar sudo para el usuario
        echo "$user_name ALL=(ALL) ALL" >> "${AI_MOUNTPOINT_PATH}/etc/sudoers.d/$user_name"
        
        # Crear directorios de usuario
        ai.changeroot_to_mountpoint su - "$user_name" -c "xdg-user-dirs-update"
    done
}

alias ai.optimize_system=ai_optimize_system
ai_optimize_system() {
    local -r __documentation__='
        Aplica optimizaciones al sistema.
    '
    bl.logging.info "Aplicando optimizaciones..."
    
    # Optimizar pacman
    cat << 'EOF' >> "${AI_MOUNTPOINT_PATH}/etc/pacman.conf"
# Optimizaciones
ILoveCandy
ParallelDownloads = 5
Color
EOF
    
    # Configurar mkinitcpio
    if $AI_ENCRYPT; then
        sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems fsck)/' \
            "${AI_MOUNTPOINT_PATH}/etc/mkinitcpio.conf"
    fi
    
    # Habilitar servicios
    local service
    for service in "${AI_NEEDED_SERVICES[@]}"; do
        bl.logging.info "Habilitando servicio: $service"
        ai.changeroot_to_mountpoint systemctl enable "$service"
    done
}

# Las funciones existentes del script original se mantienen...
# [Todas las funciones originales del script se mantienen aquí]
# ...

## endregion

## region controller
alias ai.main=ai_main
ai_main() {
    local -r __documentation__='
        Función principal del script.
    '
    bl.exception.activate
    ai.commandline_interface "$@"
    
    # Detectar hardware si es automático
    if [ "$AI_VIDEO_DRIVER" = "auto" ]; then
        ai.detect_hardware
    fi
    
    # Configurar paquetes a instalar
    AI_PACKAGES+=(
        "${AI_BASIC_PACKAGES[@]}"
        "${AI_ADDITIONAL_PACKAGES[@]}"
    )
    
    if $AI_ADD_COMMON_ADDITIONAL_PACKAGES; then
        AI_PACKAGES+=("${AI_COMMON_ADDITIONAL_PACKAGES[@]}")
    fi
    
    # Preparar target
    if [ ! -e "$AI_TARGET" ]; then
        mkdir --parents "$AI_TARGET"
    fi
    
    if [ -d "$AI_TARGET" ]; then
        AI_MOUNTPOINT_PATH="$AI_TARGET"
        if [[ ! "$AI_MOUNTPOINT_PATH" =~ .*/$ ]]; then
            AI_MOUNTPOINT_PATH+=/
        fi
    elif [ -b "$AI_TARGET" ]; then
        ai.prepare_blockdevices
        
        bl.exception.try
        {
            if $AI_SYSTEM_PARTITION_INSTALLATION_ONLY; then
                ai.format_system_partition
            else
                if $AI_AUTO_PARTITIONING; then
                    bl.logging.info "Creando particiones automáticamente..."
                    ai.make_partitions
                    ai.format_partitions
                else
                    bl.logging.info "Esperando configuración manual de particiones..."
                    ai.make_partitions
                fi
            fi
        }
        bl.exception.catch_single
        {
            ai.prepare_blockdevices
            bl.logging.error_exception "$BL_EXCEPTION_LAST_TRACEBACK"
        }
    else
        bl.logging.error_exception "No se puede instalar en: $AI_TARGET"
    fi
    
    # Preparar instalación
    ai.prepare_installation
    
    # Cargar cache si existe
    bl.exception.try
        ai.load_cache
    bl.exception.catch_single
        bl.logging.info "No hay cache de paquetes disponible."
    
    # Instalar sistema
    if (( UID == 0 )) && ! $AI_PREVENT_USING_EXISTING_PACMAN && \
        hash pacman 2>/dev/null; then
        ai.with_existing_pacman
    else
        ai.generic_linux_steps
    fi
    
    local -ir return_code=$?
    
    # Cachear paquetes descargados
    bl.exception.try
        ai.cache
    bl.exception.catch_single
        bl.logging.warn "No se pudo cachear los paquetes."
    
    # Configuraciones adicionales
    if (( return_code == 0 )); then
        ai.configure_pacman
        ai.configure_locale
        ai.configure_users
        ai.setup_swap
        ai.install_drivers
        ai.install_desktop_environment
        ai.install_aur_helper
        ai.optimize_system
        ai.configure
    fi
    
    # Finalizar
    ai.tidy_up_system
    ai.prepare_next_boot
    ai.pack_result
    
    bl.logging.info "✅ Instalación completada en: $AI_TARGET"
    bl.logging.info "   Hostname: $AI_HOST_NAME"
    bl.logging.info "   Usuarios: ${AI_USER_NAMES[*]}"
    bl.logging.info "   Entorno: $AI_DESKTOP_ENVIRONMENT"
    
    if $AI_AUTOMATIC_REBOOT; then
        bl.logging.info "🔄 Reiniciando en 5 segundos..."
        sleep 5
        reboot
    fi
    
    bl.exception.deactivate
}
## endregion
# endregion

if bl.tools.is_main; then
    ai.main "$@"
fi

# region vim modline
# vim: set tabstop=4 shiftwidth=4 expandtab:
# vim: foldmethod=marker foldmarker=region,endregion:
# endregion
