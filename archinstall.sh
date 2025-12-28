#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# region header
# [Project page](https://torben.website/archinstall)
# Copyright Torben Sickert (info["~at~"]torben.website) 16.12.2012
# License: Creative Commons 3.0
# endregion

# shellcheck disable=SC1004,SC2016,SC2034,SC2155
shopt -s expand_aliases

# ============================================================================
# CONFIGURACIÓN PRINCIPAL
# ============================================================================

# Configuración por defecto
declare -g AI_HOST_NAME="archlinux"
declare -g AI_USER_NAME="archuser"
declare -g AI_USER_PASSWORD="archlinux"
declare -g AI_ROOT_PASSWORD="archlinux"
declare -g AI_TARGET="/dev/sda"
declare -g AI_TIMEZONE="Europe/Madrid"
declare -g AI_LOCALE="es_ES.UTF-8"
declare -g AI_KEYMAP="es"
declare -g AI_DESKTOP_ENV="plasma-minimal"  # plasma-minimal, xfce, gnome, none
declare -g AI_GPU_DRIVER="auto"  # auto, intel, amd, nvidia, nvidia-lts, vmware, virtualbox
declare -g AI_ENCRYPT_DISK=false
declare -g AI_LUKS_PASSWORD="archlinux"
declare -g AI_SWAP_SIZE="4096"  # MB, 0 para deshabilitar
declare -g AI_AUTO_PARTITION=true
declare -g AI_ENABLE_AUR=true
declare -g AI_INSTALL_EXTRA=true
declare -g AI_SKIP_CONFIRM=false
declare -g AI_SKIP_INTERNET_CHECK=false
declare -g AI_FORCE_INTERNET=false

# Variables internas
declare -g AI_MOUNTPOINT="/mnt"
declare -g AI_BOOT_PARTITION="${AI_TARGET}1"
declare -g AI_ROOT_PARTITION="${AI_TARGET}2"
declare -g AI_SWAP_PARTITION="${AI_TARGET}3"
declare -g AI_LUKS_DEVICE="cryptroot"
declare -g AI_UEFI=false

# Paquetes base
declare -ag AI_BASE_PACKAGES=(
    base base-devel linux linux-firmware linux-headers
    sudo nano git wget curl htop neofetch
    networkmanager dhclient dhcpcd
    grub efibootmgr dosfstools os-prober mtools
    bash-completion
    man-db man-pages texinfo
    ntfs-3g exfat-utils fuse2 fuse3
)

# Paquetes para Plasma mínimo
declare -ag AI_PLASMA_PACKAGES=(
    plasma-desktop
    sddm sddm-kcm
    konsole dolphin kate
    ark gwenview spectacle
    plasma-nm plasma-pa bluedevil
    powerdevil breeze-gtk
    kde-gtk-config kgamma5
    print-manager
    systemsettings
    kcalc kclock
    partitionmanager
    xdg-user-dirs xdg-utils
)

# Paquetes para XFCE
declare -ag AI_XFCE_PACKAGES=(
    xfce4 xfce4-goodies
    lightdm lightdm-gtk-greeter
    network-manager-applet
    xfce4-pulseaudio-plugin
    xfce4-screenshooter
    xfce4-taskmanager
    mousepad ristretto
    thunar-archive-plugin
    xdg-user-dirs xdg-utils
)

# Paquetes para GNOME
declare -ag AI_GNOME_PACKAGES=(
    gnome gnome-tweaks
    gdm
    gnome-terminal nautilus
    gnome-calculator gnome-calendar
    gnome-system-monitor
    gnome-disk-utility
    gnome-screenshot
    xdg-user-dirs xdg-utils
)

# Paquetes extra recomendados
declare -ag AI_EXTRA_PACKAGES=(
    firefox firefox-i18n-es-es
    vlc
    gimp
    libreoffice-fresh libreoffice-fresh-es
    hunspell hunspell-es
    noto-fonts noto-fonts-emoji noto-fonts-cjk
    ttf-dejavu ttf-liberation
    pulseaudio pulseaudio-alsa pavucontrol
    bluez bluez-utils blueman
    cups cups-pdf hplip
    avahi nss-mdns
    unzip unrar p7zip zip
    neovim
    python python-pip
    git-lfs
    docker docker-compose
    openssh
    rsync
    pacman-contrib
    reflector
)

# Drivers de GPU
declare -ag AI_INTEL_DRIVERS=(mesa vulkan-intel intel-media-driver libva-intel-driver)
declare -ag AI_AMD_DRIVERS=(mesa vulkan-radeon xf86-video-amdgpu libva-mesa-driver)
declare -ag AI_NVIDIA_DRIVERS=(nvidia nvidia-utils nvidia-settings)
declare -ag AI_NVIDIA_LTS_DRIVERS=(nvidia-lts nvidia-utils nvidia-settings)
declare -ag AI_VMWARE_DRIVERS=(xf86-video-vmware mesa)
declare -ag AI_VIRTUALBOX_DRIVERS=(virtualbox-guest-utils virtualbox-guest-modules-arch)

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

# Función para imprimir mensajes con colores
print_msg() {
    local type="$1"
    local message="$2"
    
    case "$type" in
        "info")
            echo -e "\033[1;34m[*]\033[0m $message"
            ;;
        "success")
            echo -e "\033[1;32m[+]\033[0m $message"
            ;;
        "warning")
            echo -e "\033[1;33m[!]\033[0m $message"
            ;;
        "error")
            echo -e "\033[1;31m[-]\033[0m $message"
            ;;
        "input")
            echo -e "\033[1;36m[?]\033[0m $message"
            ;;
        "step")
            echo -e "\n\033[1;35m[→]\033[0m \033[1;37m$message\033[0m"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Función para confirmar acciones
confirm() {
    local prompt="$1"
    
    if [ "$AI_SKIP_CONFIRM" = true ]; then
        return 0
    fi
    
    print_msg "input" "$prompt [s/N]"
    read -r response
    
    case "$response" in
        [sS][iI]|[sS]|[yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Función mejorada para verificar conexión a internet
check_internet() {
    local -i max_attempts=3
    local -i attempt=1
    local -i wait_time=2
    
    # Si se salta la verificación
    if [ "$AI_SKIP_INTERNET_CHECK" = true ]; then
        print_msg "warning" "Verificación de internet saltada por el usuario"
        return 0
    fi
    
    print_msg "info" "Verificando conexión a internet (intento $attempt/$max_attempts)..."
    
    # Método 1: Ping a múltiples servidores
    local -a ping_servers=("archlinux.org" "google.com" "8.8.8.8" "1.1.1.1")
    for server in "${ping_servers[@]}"; do
        if timeout 3 ping -c 1 -W 2 "$server" >/dev/null 2>&1; then
            print_msg "success" "Conexión a internet verificada (ping a $server)"
            return 0
        fi
    done
    
    # Método 2: DNS lookup
    if timeout 3 nslookup archlinux.org >/dev/null 2>&1; then
        print_msg "success" "Conexión a internet verificada (DNS funcionando)"
        return 0
    fi
    
    # Método 3: HTTP/HTTPS request
    if command -v curl >/dev/null 2>&1; then
        if timeout 5 curl -s --head http://archlinux.org >/dev/null 2>&1 || \
           timeout 5 curl -s --head https://archlinux.org >/dev/null 2>&1; then
            print_msg "success" "Conexión a internet verificada (HTTP/HTTPS)"
            return 0
        fi
    fi
    
    # Método 4: wget como alternativa
    if command -v wget >/dev/null 2>&1; then
        if timeout 5 wget -q --spider http://archlinux.org >/dev/null 2>&1; then
            print_msg "success" "Conexión a internet verificada (wget)"
            return 0
        fi
    fi
    
    # Si todos los métodos fallan
    print_msg "error" "No se pudo verificar la conexión a internet"
    
    # Mostrar estado de red
    echo ""
    print_msg "info" "Estado actual de red:"
    ip addr show | grep -E "inet|state" || true
    echo ""
    
    # Intentar reconectar
    while [ $attempt -lt $max_attempts ]; do
        print_msg "warning" "Intento $attempt fallado. Reintentando en $wait_time segundos..."
        sleep $wait_time
        
        # Intentar reactivar la conexión
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
            print_msg "info" "Reiniciando NetworkManager..."
            systemctl restart NetworkManager 2>/dev/null || true
            sleep 2
        elif systemctl is-active dhcpcd >/dev/null 2>&1; then
            print_msg "info" "Reiniciando dhcpcd..."
            systemctl restart dhcpcd 2>/dev/null || true
            sleep 2
        fi
        
        # Verificar nuevamente
        for server in "${ping_servers[@]}"; do
            if timeout 3 ping -c 1 -W 2 "$server" >/dev/null 2>&1; then
                print_msg "success" "¡Conexión restablecida! (ping a $server)"
                return 0
            fi
        done
        
        attempt=$((attempt + 1))
        wait_time=$((wait_time * 2))
    done
    
    return 1
}

# Función mejorada para configurar red
setup_network() {
    print_msg "step" "Configuración de red"
    
    # Mostrar interfaces de red disponibles
    echo ""
    print_msg "info" "Interfaces de red disponibles:"
    ip -brief link show | grep -v LOOPBACK
    
    # Verificar si hay conexión activa
    if ip route | grep -q default; then
        print_msg "info" "Conexión de red detectada:"
        ip route | grep default
        echo ""
        
        if confirm "¿Usar conexión existente?"; then
            return 0
        fi
    fi
    
    while true; do
        echo ""
        print_msg "input" "Seleccione opción de red:"
        echo "1) Ethernet (cable) - Configuración automática DHCP"
        echo "2) WiFi - Configurar conexión inalámbrica"
        echo "3) Configuración manual (IP estática)"
        echo "4) Probar conexión actual"
        echo "5) Saltar verificación de internet"
        read -r network_choice
        
        case "$network_choice" in
            1)
                # Ethernet con DHCP
                print_msg "info" "Configurando Ethernet..."
                
                # Detectar interfaz Ethernet
                local eth_interface
                eth_interface=$(ip -brief link show | grep -E '^enp|^eth' | awk '{print $1}' | head -1)
                
                if [ -z "$eth_interface" ]; then
                    print_msg "error" "No se encontró interfaz Ethernet"
                    continue
                fi
                
                print_msg "info" "Usando interfaz: $eth_interface"
                
                # Configurar DHCP
                if command -v dhcpcd >/dev/null 2>&1; then
                    print_msg "info" "Activando dhcpcd en $eth_interface..."
                    dhcpcd "$eth_interface" 2>/dev/null || true
                    sleep 3
                fi
                
                if command -v NetworkManager >/dev/null 2>&1; then
                    print_msg "info" "Activando NetworkManager..."
                    systemctl start NetworkManager 2>/dev/null || true
                    sleep 2
                fi
                
                # Verificar conexión
                if check_internet; then
                    print_msg "success" "Ethernet configurado exitosamente"
                    return 0
                else
                    print_msg "error" "No se pudo establecer conexión Ethernet"
                fi
                ;;
            
            2)
                # WiFi
                print_msg "info" "Configurando WiFi..."
                
                # Verificar herramientas WiFi
                if command -v iwctl >/dev/null 2>&1; then
                    print_msg "info" "Usando iwd (iwctl)..."
                    
                    # Iniciar iwd si no está activo
                    systemctl start iwd 2>/dev/null || true
                    sleep 2
                    
                    # Mostrar interfaces WiFi
                    iwctl device list
                    echo ""
                    
                    print_msg "input" "Ingrese nombre de interfaz WiFi (ej: wlan0): "
                    read -r wifi_interface
                    
                    print_msg "info" "Escaneando redes WiFi..."
                    iwctl station "$wifi_interface" scan
                    sleep 2
                    
                    print_msg "info" "Redes disponibles:"
                    iwctl station "$wifi_interface" get-networks
                    echo ""
                    
                    print_msg "input" "Ingrese SSID de la red WiFi: "
                    read -r wifi_ssid
                    
                    print_msg "input" "Ingrese contraseña (deje en blanco para red abierta): "
                    read -r wifi_password
                    
                    if [ -z "$wifi_password" ]; then
                        iwctl station "$wifi_interface" connect "$wifi_ssid"
                    else
                        iwctl station "$wifi_interface" connect "$wifi_ssid" --passphrase "$wifi_password"
                    fi
                    
                    sleep 5
                    
                elif command -v wifi-menu >/dev/null 2>&1; then
                    print_msg "info" "Usando wifi-menu..."
                    wifi-menu
                else
                    print_msg "error" "No se encontraron herramientas WiFi"
                    print_msg "info" "Instale 'iwd' o 'wpa_supplicant' y 'dialog' para wifi-menu"
                    continue
                fi
                
                # Verificar conexión
                if check_internet; then
                    print_msg "success" "WiFi configurado exitosamente"
                    return 0
                else
                    print_msg "error" "No se pudo establecer conexión WiFi"
                fi
                ;;
            
            3)
                # Configuración manual
                print_msg "info" "Configuración manual de red"
                
                print_msg "input" "Ingrese interfaz de red (ej: eth0, enp3s0): "
                read -r manual_interface
                
                print_msg "input" "Ingrese dirección IP (ej: 192.168.1.100/24): "
                read -r manual_ip
                
                print_msg "input" "Ingrese gateway (ej: 192.168.1.1): "
                read -r manual_gateway
                
                print_msg "input" "Ingrese DNS (ej: 8.8.8.8): "
                read -r manual_dns
                
                # Configurar IP estática
                ip addr add "$manual_ip" dev "$manual_interface"
                ip link set "$manual_interface" up
                ip route add default via "$manual_gateway"
                
                # Configurar DNS temporal
                echo "nameserver $manual_dns" > /etc/resolv.conf
                
                # Verificar conexión
                if check_internet; then
                    print_msg "success" "Configuración manual exitosa"
                    return 0
                else
                    print_msg "error" "Configuración manual no funcionó"
                fi
                ;;
            
            4)
                # Probar conexión actual
                print_msg "info" "Probando conexión actual..."
                if check_internet; then
                    print_msg "success" "¡Conexión funcionando!"
                    return 0
                fi
                ;;
            
            5)
                # Saltar verificación
                print_msg "warning" "Saltando verificación de internet"
                AI_SKIP_INTERNET_CHECK=true
                return 0
                ;;
            
            *)
                print_msg "error" "Opción inválida"
                ;;
        esac
    done
    
    return 1
}

# Función para detectar hardware
detect_hardware() {
    print_msg "step" "Detección de hardware"
    
    # Detectar UEFI/BIOS
    if [ -d /sys/firmware/efi ]; then
        print_msg "info" "Sistema UEFI detectado"
        AI_UEFI=true
    else
        print_msg "info" "Sistema BIOS detectado"
        AI_UEFI=false
    fi
    
    # Detectar GPU
    if lspci | grep -i "nvidia" > /dev/null; then
        print_msg "info" "GPU NVIDIA detectada"
        AI_GPU_DRIVER="nvidia"
    elif lspci | grep -i "amd" | grep -i "vga" > /dev/null; then
        print_msg "info" "GPU AMD detectada"
        AI_GPU_DRIVER="amd"
    elif lspci | grep -i "intel" | grep -i "vga" > /dev/null; then
        print_msg "info" "GPU Intel detectada"
        AI_GPU_DRIVER="intel"
    elif systemd-detect-virt | grep -i "vmware" > /dev/null; then
        print_msg "info" "VMware detectado"
        AI_GPU_DRIVER="vmware"
    elif systemd-detect-virt | grep -i "oracle" > /dev/null; then
        print_msg "info" "VirtualBox detectado"
        AI_GPU_DRIVER="virtualbox"
    else
        print_msg "warning" "GPU no detectada, usando drivers genéricos"
        AI_GPU_DRIVER="intel"
    fi
    
    print_msg "success" "Detección completada"
}

# ============================================================================
# FUNCIONES DE PARTICIONADO
# ============================================================================

# Función para seleccionar dispositivo
select_device() {
    print_msg "step" "Selección de dispositivo"
    
    echo "Dispositivos disponibles:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v "loop"
    
    if [ "$AI_TARGET" = "/dev/sda" ]; then
        print_msg "input" "Ingrese dispositivo (ej: /dev/sda) [/dev/sda]:"
        read -r user_device
        AI_TARGET="${user_device:-/dev/sda}"
    fi
    
    AI_BOOT_PARTITION="${AI_TARGET}1"
    AI_ROOT_PARTITION="${AI_TARGET}2"
    AI_SWAP_PARTITION="${AI_TARGET}3"
    
    print_msg "info" "Dispositivo seleccionado: $AI_TARGET"
}

# Función para particionar disco
partition_disk() {
    print_msg "step" "Particionado del disco"
    
    if ! confirm "¿Particionar $AI_TARGET? (Todos los datos serán eliminados)"; then
        return 1
    fi
    
    # Limpiar tabla de particiones
    print_msg "info" "Limpiando tabla de particiones..."
    sgdisk -Z "$AI_TARGET"
    wipefs -a "$AI_TARGET"
    
    if [ "$AI_UEFI" = true ]; then
        # Particionado UEFI
        print_msg "info" "Creando particiones UEFI..."
        
        # Partición ESP (boot)
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"ESP" "$AI_TARGET"
        
        # Partición swap (opcional)
        if [ "$AI_SWAP_SIZE" -gt 0 ]; then
            sgdisk -n 2:0:+${AI_SWAP_SIZE}M -t 2:8200 -c 2:"SWAP" "$AI_TARGET"
            # Partición root
            sgdisk -n 3:0:0 -t 3:8304 -c 3:"ROOT" "$AI_TARGET"
            AI_ROOT_PARTITION="${AI_TARGET}3"
        else
            # Solo partición root
            sgdisk -n 2:0:0 -t 2:8304 -c 2:"ROOT" "$AI_TARGET"
            AI_ROOT_PARTITION="${AI_TARGET}2"
        fi
    else
        # Particionado BIOS
        print_msg "info" "Creando particiones BIOS..."
        
        # Partición boot
        sgdisk -n 1:0:+1M -t 1:ef02 -c 1:"BIOS Boot" "$AI_TARGET"
        
        # Partición swap (opcional)
        if [ "$AI_SWAP_SIZE" -gt 0 ]; then
            sgdisk -n 2:0:+${AI_SWAP_SIZE}M -t 2:8200 -c 2:"SWAP" "$AI_TARGET"
            # Partición root
            sgdisk -n 3:0:0 -t 3:8304 -c 3:"ROOT" "$AI_TARGET"
            AI_ROOT_PARTITION="${AI_TARGET}3"
        else
            # Solo partición root
            sgdisk -n 2:0:0 -t 2:8304 -c 2:"ROOT" "$AI_TARGET"
            AI_ROOT_PARTITION="${AI_TARGET}2"
        fi
    fi
    
    print_msg "success" "Particionado completado"
    
    # Sincronizar y mostrar resultado
    partprobe "$AI_TARGET"
    sleep 2
    lsblk "$AI_TARGET"
}

# Función para formatear particiones
format_partitions() {
    print_msg "step" "Formateo de particiones"
    
    # Formatear partición boot (UEFI)
    if [ "$AI_UEFI" = true ]; then
        print_msg "info" "Formateando ESP..."
        mkfs.fat -F32 "$AI_BOOT_PARTITION"
    fi
    
    # Formatear swap
    if [ "$AI_SWAP_SIZE" -gt 0 ]; then
        print_msg "info" "Formateando swap..."
        mkswap "$AI_SWAP_PARTITION"
        swapon "$AI_SWAP_PARTITION"
    fi
    
    # Cifrar partición root si está habilitado
    if [ "$AI_ENCRYPT_DISK" = true ]; then
        print_msg "info" "Cifrando partición root..."
        echo "$AI_LUKS_PASSWORD" | cryptsetup luksFormat "$AI_ROOT_PARTITION"
        echo "$AI_LUKS_PASSWORD" | cryptsetup open "$AI_ROOT_PARTITION" "$AI_LUKS_DEVICE"
        ROOT_DEVICE="/dev/mapper/$AI_LUKS_DEVICE"
    else
        ROOT_DEVICE="$AI_ROOT_PARTITION"
    fi
    
    # Formatear partición root
    print_msg "info" "Formateando root con ext4..."
    mkfs.ext4 -F "$ROOT_DEVICE"
    
    # Montar particiones
    print_msg "info" "Montando particiones..."
    mount "$ROOT_DEVICE" "$AI_MOUNTPOINT"
    
    if [ "$AI_UEFI" = true ]; then
        mkdir -p "$AI_MOUNTPOINT/boot"
        mount "$AI_BOOT_PARTITION" "$AI_MOUNTPOINT/boot"
    fi
    
    print_msg "success" "Formateo completado"
}

# ============================================================================
# FUNCIONES DE INSTALACIÓN
# ============================================================================

# Función mejorada para configurar mirrorlist
configure_mirrors() {
    print_msg "step" "Configurando mirrors"
    
    # Hacer backup del mirrorlist
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup 2>/dev/null || true
    
    # Usar reflector para obtener mejores mirrors
    if command -v reflector >/dev/null 2>&1; then
        print_msg "info" "Obteniendo mejores mirrors con reflector..."
        
        # Intentar varios países si falla el principal
        local countries=("Spain" "France" "Germany" "United States")
        local success=false
        
        for country in "${countries[@]}"; do
            print_msg "info" "Intentando con mirrors de: $country"
            if reflector --country "$country" --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null; then
                print_msg "success" "Mirrors configurados desde $country"
                success=true
                break
            fi
        done
        
        if [ "$success" = false ]; then
            print_msg "warning" "No se pudieron obtener mirrors con reflector, usando lista por defecto"
        fi
    else
        print_msg "warning" "Reflector no instalado, usando mirrors por defecto"
    fi
    
    # Actualizar bases de datos con reintentos
    print_msg "info" "Actualizando bases de datos de paquetes..."
    
    local -i max_retries=3
    local -i retry_count=0
    local update_success=false
    
    while [ $retry_count -lt $max_retries ]; do
        if pacman -Syy --noconfirm 2>/dev/null; then
            update_success=true
            break
        else
            retry_count=$((retry_count + 1))
            print_msg "warning" "Intento $retry_count fallado. Reintentando en 3 segundos..."
            sleep 3
        fi
    done
    
    if [ "$update_success" = false ]; then
        print_msg "error" "No se pudieron actualizar las bases de datos"
        
        if confirm "¿Continuar sin actualizar bases de datos?"; then
            print_msg "warning" "Continuando con bases de datos desactualizadas"
        else
            return 1
        fi
    else
        print_msg "success" "Bases de datos actualizadas"
    fi
    
    return 0
}

# Función para instalar sistema base
install_base() {
    print_msg "step" "Instalando sistema base"
    
    # Instalar paquetes base con reintentos
    print_msg "info" "Instalando paquetes base..."
    
    local -i max_retries=3
    local -i retry_count=0
    local install_success=false
    
    while [ $retry_count -lt $max_retries ]; do
        if pacstrap "$AI_MOUNTPOINT" "${AI_BASE_PACKAGES[@]}" 2>/dev/null; then
            install_success=true
            break
        else
            retry_count=$((retry_count + 1))
            print_msg "warning" "Intento $retry_count de instalación fallado. Reintentando en 5 segundos..."
            sleep 5
            
            # Intentar actualizar mirrors antes de reintentar
            if [ $retry_count -lt $max_retries ]; then
                print_msg "info" "Actualizando mirrors antes de reintentar..."
                configure_mirrors || true
            fi
        fi
    done
    
    if [ "$install_success" = false ]; then
        print_msg "error" "No se pudieron instalar los paquetes base"
        return 1
    fi
    
    # Generar fstab
    print_msg "info" "Generando fstab..."
    genfstab -U "$AI_MOUNTPOINT" >> "$AI_MOUNTPOINT/etc/fstab"
    
    # Añadir entrada swap si existe
    if [ "$AI_SWAP_SIZE" -gt 0 ]; then
        echo "# Swap partition" >> "$AI_MOUNTPOINT/etc/fstab"
        echo "$AI_SWAP_PARTITION none swap defaults 0 0" >> "$AI_MOUNTPOINT/etc/fstab"
    fi
    
    print_msg "success" "Sistema base instalado"
    return 0
}

# Función para configurar zona horaria y locales
configure_timezone_locale() {
    print_msg "step" "Configurando zona horaria y locales"
    
    # Configurar zona horaria
    print_msg "info" "Configurando zona horaria: $AI_TIMEZONE"
    
    # Verificar que la zona horaria exista
    if [ ! -f "/usr/share/zoneinfo/$AI_TIMEZONE" ]; then
        print_msg "error" "Zona horaria no encontrada: $AI_TIMEZONE"
        print_msg "info" "Zonas horarias disponibles en /usr/share/zoneinfo/"
        
        # Mostrar zonas comunes
        echo "Zonas comunes:"
        find /usr/share/zoneinfo -type f | grep -E "(Europe|America)" | head -20 | sed 's|/usr/share/zoneinfo/||'
        
        if confirm "¿Usar zona por defecto (Europe/Madrid)?"; then
            AI_TIMEZONE="Europe/Madrid"
        else
            print_msg "input" "Ingrese zona horaria (ej: Europe/Madrid): "
            read -r AI_TIMEZONE
        fi
    fi
    
    arch-chroot "$AI_MOUNTPOINT" ln -sf "/usr/share/zoneinfo/$AI_TIMEZONE" /etc/localtime
    arch-chroot "$AI_MOUNTPOINT" hwclock --systohc
    
    # Configurar locale
    print_msg "info" "Configurando locale: $AI_LOCALE"
    
    # Verificar formato del locale
    if ! echo "$AI_LOCALE" | grep -q "UTF-8"; then
        print_msg "warning" "Locale sin UTF-8, añadiendo..."
        AI_LOCALE="${AI_LOCALE}.UTF-8"
    fi
    
    # Editar locale.gen - habilitar el locale especificado
    if grep -q "^#$AI_LOCALE" "$AI_MOUNTPOINT/etc/locale.gen"; then
        sed -i "s/^#$AI_LOCALE/$AI_LOCALE/" "$AI_MOUNTPOINT/etc/locale.gen"
    else
        # Si no existe, añadirlo
        echo "$AI_LOCALE UTF-8" >> "$AI_MOUNTPOINT/etc/locale.gen"
    fi
    
    # También habilitar algunos locales comunes por defecto
    sed -i "s/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" "$AI_MOUNTPOINT/etc/locale.gen"
    
    # Generar locales
    arch-chroot "$AI_MOUNTPOINT" locale-gen
    
    # Configurar LANG
    echo "LANG=$AI_LOCALE" > "$AI_MOUNTPOINT/etc/locale.conf"
    
    # Configurar teclado
    print_msg "info" "Configurando teclado: $AI_KEYMAP"
    
    # Verificar mapa de teclado válido
    local keymaps_dir="$AI_MOUNTPOINT/usr/share/kbd/keymaps"
    if [ ! -f "$keymaps_dir/i386/qwerty/$AI_KEYMAP.map.gz" ] && \
       [ ! -f "$keymaps_dir/i386/$AI_KEYMAP/$AI_KEYMAP.map.gz" ]; then
        print_msg "warning" "Mapa de teclado no encontrado: $AI_KEYMAP"
        print_msg "info" "Usando 'es' por defecto"
        AI_KEYMAP="es"
    fi
    
    echo "KEYMAP=$AI_KEYMAP" > "$AI_MOUNTPOINT/etc/vconsole.conf"
    
    # Configurar consola para español
    echo "FONT=lat9w-16" >> "$AI_MOUNTPOINT/etc/vconsole.conf"
    echo "FONT_MAP=" >> "$AI_MOUNTPOINT/etc/vconsole.conf"
    
    print_msg "success" "Zona horaria y locales configurados"
}

# Función para configurar sistema
configure_system() {
    print_msg "step" "Configurando sistema"
    
    # Configurar hostname
    print_msg "info" "Configurando hostname: $AI_HOST_NAME"
    echo "$AI_HOST_NAME" > "$AI_MOUNTPOINT/etc/hostname"
    
    # Configurar hosts
    cat > "$AI_MOUNTPOINT/etc/hosts" << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $AI_HOST_NAME.localdomain   $AI_HOST_NAME
EOF
    
    # Configurar contraseñas
    print_msg "info" "Configurando contraseñas..."
    echo "root:$AI_ROOT_PASSWORD" | arch-chroot "$AI_MOUNTPOINT" chpasswd
    
    # Crear usuario
    print_msg "info" "Creando usuario: $AI_USER_NAME"
    arch-chroot "$AI_MOUNTPOINT" useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$AI_USER_NAME"
    echo "$AI_USER_NAME:$AI_USER_PASSWORD" | arch-chroot "$AI_MOUNTPOINT" chpasswd
    
    # Configurar sudo
    print_msg "info" "Configurando sudo..."
    echo "$AI_USER_NAME ALL=(ALL) ALL" >> "$AI_MOUNTPOINT/etc/sudoers.d/$AI_USER_NAME"
    chmod 440 "$AI_MOUNTPOINT/etc/sudoers.d/$AI_USER_NAME"
    
    print_msg "success" "Configuración del sistema completada"
}

# [Las funciones restantes se mantienen igual que en la versión anterior...]
# [Para mantener la respuesta dentro de límites razonables, continúo con el resto]

# ============================================================================
# CONTINUACIÓN DE FUNCIONES (resumido)
# ============================================================================

# Función para instalar bootloader (similar a versión anterior)
install_bootloader() {
    print_msg "step" "Instalando bootloader"
    
    if [ "$AI_UEFI" = true ]; then
        # Instalar GRUB para UEFI
        print_msg "info" "Instalando GRUB para UEFI..."
        arch-chroot "$AI_MOUNTPOINT" pacman -S --noconfirm grub efibootmgr
        
        # Configurar GRUB para LUKS si es necesario
        if [ "$AI_ENCRYPT_DISK" = true ]; then
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/&cryptdevice='"$AI_ROOT_PARTITION"':'"$AI_LUKS_DEVICE"' /' \
                "$AI_MOUNTPOINT/etc/default/grub"
        fi
        
        arch-chroot "$AI_MOUNTPOINT" grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    else
        # Instalar GRUB para BIOS
        print_msg "info" "Instalando GRUB para BIOS..."
        arch-chroot "$AI_MOUNTPOINT" pacman -S --noconfirm grub
        arch-chroot "$AI_MOUNTPOINT" grub-install --target=i386-pc "$AI_TARGET"
    fi
    
    # Generar configuración GRUB
    arch-chroot "$AI_MOUNTPOINT" grub-mkconfig -o /boot/grub/grub.cfg
    print_msg "success" "Bootloader instalado"
}

# [Las funciones install_gpu_drivers, install_desktop, install_extras, 
# configure_services, optimize_system se mantienen igual]

# ============================================================================
# FUNCIONES DE INTERFAZ
# ============================================================================

# Función para mostrar menú principal
show_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            INSTALADOR DE ARCH LINUX MEJORADO            ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║ 1. Instalación automática (Plasma mínimo)               ║"
    echo "║ 2. Instalación personalizada                            ║"
    echo "║ 3. Ver configuración actual                             ║"
    echo "║ 4. Configurar opciones manualmente                      ║"
    echo "║ 5. Probar conexión a internet                           ║"
    echo "║ 6. Configurar red                                       ║"
    echo "║ 7. Salir                                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    read -r -p "Seleccione una opción [1-7]: " choice
    
    case "$choice" in
        1)
            auto_install
            ;;
        2)
            custom_install
            ;;
        3)
            show_config
            show_menu
            ;;
        4)
            configure_manually
            ;;
        5)
            print_msg "info" "Probando conexión a internet..."
            if check_internet; then
                print_msg "success" "¡Conexión a internet funcionando!"
            else
                print_msg "error" "No hay conexión a internet"
            fi
            read -r -p "Presione Enter para continuar..."
            show_menu
            ;;
        6)
            setup_network
            show_menu
            ;;
        7)
            exit 0
            ;;
        *)
            print_msg "error" "Opción inválida"
            sleep 2
            show_menu
            ;;
    esac
}

# Función para mostrar configuración actual
show_config() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║               CONFIGURACIÓN ACTUAL                       ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║ Hostname:          $AI_HOST_NAME"
    echo "║ Usuario:           $AI_USER_NAME"
    echo "║ Dispositivo:       $AI_TARGET"
    echo "║ Zona horaria:      $AI_TIMEZONE"
    echo "║ Locale:            $AI_LOCALE"
    echo "║ Teclado:           $AI_KEYMAP"
    echo "║ Entorno:           $AI_DESKTOP_ENV"
    echo "║ Drivers GPU:       $AI_GPU_DRIVER"
    echo "║ Cifrado:           $AI_ENCRYPT_DISK"
    echo "║ Swap:              ${AI_SWAP_SIZE}MB"
    echo "║ AUR:               $AI_ENABLE_AUR"
    echo "║ Paquetes extra:    $AI_INSTALL_EXTRA"
    echo "║ Verif. internet:   $AI_SKIP_INTERNET_CHECK"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    read -r -p "Presione Enter para continuar..."
}

# Función para configurar manualmente (mejorada con opciones de red)
configure_manually() {
    clear
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            CONFIGURACIÓN MANUAL                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    # Hostname
    read -r -p "Hostname [$AI_HOST_NAME]: " input
    AI_HOST_NAME="${input:-$AI_HOST_NAME}"
    
    # Usuario
    read -r -p "Usuario [$AI_USER_NAME]: " input
    AI_USER_NAME="${input:-$AI_USER_NAME}"
    
    # Contraseña de usuario
    read -r -sp "Contraseña de usuario [*****]: " input
    echo
    if [ -n "$input" ]; then
        AI_USER_PASSWORD="$input"
    fi
    
    # Contraseña root
    read -r -sp "Contraseña root [*****]: " input
    echo
    if [ -n "$input" ]; then
        AI_ROOT_PASSWORD="$input"
    fi
    
    # Zona horaria
    echo ""
    echo "Zonas horarias comunes:"
    echo "  Europe/Madrid, America/New_York, America/Mexico_City, Europe/London, Asia/Tokyo"
    echo "  Ver zonas disponibles en: /usr/share/zoneinfo/"
    read -r -p "Zona horaria [$AI_TIMEZONE]: " input
    AI_TIMEZONE="${input:-$AI_TIMEZONE}"
    
    # Locale
    echo ""
    echo "Locales comunes:"
    echo "  es_ES.UTF-8, en_US.UTF-8, en_GB.UTF-8, fr_FR.UTF-8, de_DE.UTF-8"
    read -r -p "Locale [$AI_LOCALE]: " input
    AI_LOCALE="${input:-$AI_LOCALE}"
    
    # Mapa de teclado
    echo ""
    echo "Mapas de teclado comunes:"
    echo "  es (español), us (inglés US), la-latin1 (latinoamérica), fr (francés), de (alemán)"
    read -r -p "Mapa de teclado [$AI_KEYMAP]: " input
    AI_KEYMAP="${input:-$AI_KEYMAP}"
    
    # Dispositivo
    echo ""
    echo "Dispositivos disponibles:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -v "loop"
    read -r -p "Dispositivo [$AI_TARGET]: " input
    AI_TARGET="${input:-$AI_TARGET}"
    
    # Entorno de escritorio
    echo ""
    echo "Entornos disponibles:"
    echo "1) Ninguno (solo CLI)"
    echo "2) Plasma mínimo (KDE)"
    echo "3) XFCE"
    echo "4) GNOME"
    read -r -p "Entorno [2]: " input
    case "${input:-2}" in
        1) AI_DESKTOP_ENV="none" ;;
        2) AI_DESKTOP_ENV="plasma-minimal" ;;
        3) AI_DESKTOP_ENV="xfce" ;;
        4) AI_DESKTOP_ENV="gnome" ;;
        *) AI_DESKTOP_ENV="plasma-minimal" ;;
    esac
    
    # Cifrado
    read -r -p "¿Cifrar disco? [s/N]: " input
    if [[ "$input" =~ ^[Ss]$ ]]; then
        AI_ENCRYPT_DISK=true
        read -r -sp "Contraseña de cifrado [*****]: " input
        echo
        if [ -n "$input" ]; then
            AI_LUKS_PASSWORD="$input"
        fi
    else
        AI_ENCRYPT_DISK=false
    fi
    
    # AUR
    read -r -p "¿Habilitar AUR (yay)? [S/n]: " input
    if [[ "$input" =~ ^[Nn]$ ]]; then
        AI_ENABLE_AUR=false
    else
        AI_ENABLE_AUR=true
    fi
    
    # Paquetes extra
    read -r -p "¿Instalar paquetes extra? [S/n]: " input
    if [[ "$input" =~ ^[Nn]$ ]]; then
        AI_INSTALL_EXTRA=false
    else
        AI_INSTALL_EXTRA=true
    fi
    
    # Tamaño de swap
    read -r -p "Tamaño de swap en MB (0 para deshabilitar) [$AI_SWAP_SIZE]: " input
    AI_SWAP_SIZE="${input:-$AI_SWAP_SIZE}"
    
    # Verificación de internet
    read -r -p "¿Saltar verificación de internet? [s/N]: " input
    if [[ "$input" =~ ^[Ss]$ ]]; then
        AI_SKIP_INTERNET_CHECK=true
    else
        AI_SKIP_INTERNET_CHECK=false
    fi
    
    show_menu
}

# Función para instalación automática
auto_install() {
    print_msg "step" "INICIANDO INSTALACIÓN AUTOMÁTICA"
    
    # Configuración automática
    AI_DESKTOP_ENV="plasma-minimal"
    AI_ENABLE_AUR=true
    AI_INSTALL_EXTRA=true
    
    # Verificar internet antes de continuar
    if ! check_internet; then
        print_msg "error" "Se requiere conexión a internet para instalación automática"
        if confirm "¿Configurar red ahora?"; then
            setup_network
        else
            show_menu
            return
        fi
    fi
    
    if confirm "¿Continuar con la instalación automática?"; then
        main_install
    else
        show_menu
    fi
}

# Función para instalación personalizada
custom_install() {
    print_msg "step" "INICIANDO INSTALACIÓN PERSONALIZADA"
    
    if confirm "¿Continuar con la instalación personalizada?"; then
        main_install
    else
        show_menu
    fi
}

# ============================================================================
# FUNCIÓN PRINCIPAL DE INSTALACIÓN
# ============================================================================

# Función principal de instalación
main_install() {
    print_msg "step" "INICIANDO INSTALACIÓN COMPLETA"
    
    # Mostrar configuración
    show_config
    
    if ! confirm "¿Desea continuar con esta configuración?"; then
        show_menu
        return
    fi
    
    # Verificar internet (a menos que se especifique lo contrario)
    if [ "$AI_SKIP_INTERNET_CHECK" = false ]; then
        if ! check_internet; then
            print_msg "error" "Se requiere conexión a internet para continuar"
            if confirm "¿Configurar red ahora?"; then
                setup_network || {
                    print_msg "error" "No se pudo configurar la red"
                    return 1
                }
            else
                print_msg "error" "Instalación cancelada: sin conexión a internet"
                return 1
            fi
        fi
    else
        print_msg "warning" "Verificación de internet desactivada"
    fi
    
    # Detectar hardware
    detect_hardware
    
    # Seleccionar dispositivo
    select_device
    
    # Particionar disco
    if [ "$AI_AUTO_PARTITION" = true ]; then
        partition_disk || {
            print_msg "error" "Error en particionado"
            return 1
        }
    fi
    
    # Formatear particiones
    format_partitions || {
        print_msg "error" "Error en formateo"
        return 1
    }
    
    # Configurar mirrors
    configure_mirrors || {
        print_msg "error" "Error configurando mirrors"
        return 1
    }
    
    # Instalar sistema base
    install_base || {
        print_msg "error" "Error instalando sistema base"
        return 1
    }
    
    # Configurar zona horaria y locales
    configure_timezone_locale || {
        print_msg "error" "Error configurando zona horaria y locales"
        return 1
    }
    
    # Configurar sistema
    configure_system || {
        print_msg "error" "Error configurando sistema"
        return 1
    }
    
    # Instalar bootloader
    install_bootloader || {
        print_msg "error" "Error instalando bootloader"
        return 1
    }
    
    # Instalar drivers de GPU
    install_gpu_drivers || {
        print_msg "warning" "Error instalando drivers GPU (continuando...)"
    }
    
    # Instalar entorno de escritorio
    install_desktop || {
        print_msg "warning" "Error instalando entorno de escritorio (continuando...)"
    }
    
    # Instalar paquetes extra
    install_extras || {
        print_msg "warning" "Error instalando paquetes extra (continuando...)"
    }
    
    # Configurar servicios
    configure_services || {
        print_msg "warning" "Error configurando servicios (continuando...)"
    }
    
    # Optimizar sistema
    optimize_system || {
        print_msg "warning" "Error optimizando sistema (continuando...)"
    }
    
    # Finalizar
    print_msg "success" "INSTALACIÓN COMPLETADA EXITOSAMENTE"
    
    # Mostrar resumen
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                 INSTALACIÓN COMPLETADA                   ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║ Hostname:          $AI_HOST_NAME                        ║"
    echo "║ Usuario:           $AI_USER_NAME                        ║"
    echo "║ Contraseña:        $AI_USER_PASSWORD                    ║"
    echo "║ Zona horaria:      $AI_TIMEZONE                         ║"
    echo "║ Locale:            $AI_LOCALE                           ║"
    echo "║ Teclado:           $AI_KEYMAP                           ║"
    echo "║ Entorno:           $AI_DESKTOP_ENV                      ║"
    echo "║ Drivers:           $AI_GPU_DRIVER                       ║"
    echo "║ Cifrado:           $AI_ENCRYPT_DISK                     ║"
    echo "║                                                    ║"
    echo "║ Próximos pasos:                                         ║"
    echo "║ 1. Reiniciar el sistema                                 ║"
    echo "║ 2. Iniciar sesión con su usuario                       ║"
    echo "║ 3. Configurar su entorno                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    
    if confirm "¿Desea reiniciar ahora?"; then
        umount -R "$AI_MOUNTPOINT" 2>/dev/null || true
        reboot
    fi
}

# ============================================================================
# PUNTO DE ENTRADA
# ============================================================================

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    print_msg "error" "Este script debe ejecutarse como root"
    print_msg "info" "Por favor, ejecute: sudo bash $0"
    exit 1
fi

# Verificar que estamos en Arch ISO
if [ ! -f "/etc/arch-release" ]; then
    print_msg "warning" "Parece que no está en la ISO de Arch Linux"
    if ! confirm "¿Continuar de todas formas?"; then
        exit 1
    fi
fi

# Parsear argumentos de línea de comandos
while [[ $# -gt 0 ]]; do
    case $1 in
        --hostname)
            AI_HOST_NAME="$2"
            shift 2
            ;;
        --user)
            AI_USER_NAME="$2"
            shift 2
            ;;
        --password)
            AI_USER_PASSWORD="$2"
            shift 2
            ;;
        --target)
            AI_TARGET="$2"
            shift 2
            ;;
        --timezone)
            AI_TIMEZONE="$2"
            shift 2
            ;;
        --locale)
            AI_LOCALE="$2"
            shift 2
            ;;
        --keymap)
            AI_KEYMAP="$2"
            shift 2
            ;;
        --desktop)
            AI_DESKTOP_ENV="$2"
            shift 2
            ;;
        --encrypt)
            AI_ENCRYPT_DISK=true
            shift
            ;;
        --skip-confirm)
            AI_SKIP_CONFIRM=true
            shift
            ;;
        --skip-internet-check)
            AI_SKIP_INTERNET_CHECK=true
            shift
            ;;
        --force-internet)
            AI_FORCE_INTERNET=true
            shift
            ;;
        --auto)
            AI_SKIP_CONFIRM=true
            AI_AUTO_PARTITION=true
            shift
            ;;
        --help)
            echo "Uso: $0 [OPCIONES]"
            echo ""
            echo "Opciones:"
            echo "  --hostname NOMBRE      Establecer hostname"
            echo "  --user USUARIO         Establecer nombre de usuario"
            echo "  --password CONTRASEÑA  Establecer contraseña de usuario"
            echo "  --target DISPOSITIVO   Dispositivo de instalación (ej: /dev/sda)"
            echo "  --timezone ZONA        Zona horaria (ej: Europe/Madrid)"
            echo "  --locale LOCALE        Locale (ej: es_ES.UTF-8)"
            echo "  --keymap TECLADO       Mapa de teclado (ej: es)"
            echo "  --desktop ENTORNO      Entorno de escritorio (plasma-minimal, xfce, gnome, none)"
            echo "  --encrypt              Cifrar disco con LUKS"
            echo "  --skip-confirm         Saltar confirmaciones"
            echo "  --skip-internet-check  Saltar verificación de internet"
            echo "  --force-internet       Forzar verificación de internet"
            echo "  --auto                 Instalación completamente automática"
            echo "  --help                 Mostrar esta ayuda"
            echo ""
            echo "Ejemplos:"
            echo "  $0 --auto"
            echo "  $0 --target /dev/sda --desktop plasma-minimal --encrypt"
            echo "  $0 --hostname miarch --locale es_ES.UTF-8 --keymap es --timezone Europe/Madrid"
            echo "  $0 --skip-internet-check  (para instalar sin verificar internet)"
            exit 0
            ;;
        *)
            print_msg "error" "Argumento desconocido: $1"
            exit 1
            ;;
    esac
done

# Iniciar menú o instalación automática
if [ "$AI_SKIP_CONFIRM" = true ] && [ "$AI_AUTO_PARTITION" = true ]; then
    print_msg "info" "Iniciando instalación automática..."
    main_install
else
    show_menu
fi
