#!/bin/ash
set -e

LOG_FILE="/tmp/install_log.txt"
> "$LOG_FILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
info() { log "[INFO] $*"; }
warning() { log "[WARN] $*"; }
error() { log "[ERROR] $*"; }
success() { log "[OK] $*"; }

check_status() {
    if [ $? -ne 0 ]; then
        error "$1 failed!"
        exit 1
    else
        success "$1 succeeded."
    fi
}

# بارگذاری توابع کمکی AmneziaWG
if [ -f "$(pwd)/lib.sh" ]; then
    . $(pwd)/lib.sh
else
    warning "lib.sh not found, proceeding without it."
fi

# نسخه‌ها و URLها
AWG_VERSION="24.10.4"
AWG_BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${AWG_VERSION}"
PASSWALL_FEED_BASE="https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages"

# بررسی وجود /etc/openwrt_release
if [ ! -f /etc/openwrt_release ]; then
    error "/etc/openwrt_release not found. Cannot determine architecture."
    exit 1
fi
. /etc/openwrt_release

# محاسبه ARCH_SUFFIX
TARGET_MOD="${DISTRIB_TARGET//\//_}"
ARCH_SUFFIX="${DISTRIB_ARCH}_${TARGET_MOD}"
info "Detected architecture suffix: ${ARCH_SUFFIX}"

# توابع نصب
install_awg_package() {
    local pkg="$1"
    local file="${pkg}_v${AWG_VERSION}_${ARCH_SUFFIX}.ipk"
    info "Downloading ${file}..."
    wget -O /tmp/${file} "${AWG_BASE_URL}/${file}" >> "$LOG_FILE" 2>&1
    check_status "Download of ${file}"
    info "Installing ${file}..."
    opkg install /tmp/${file} >> "$LOG_FILE" 2>&1
    check_status "Installation of ${file}"
    rm -f /tmp/${file}
    success "Installed ${file}"
}

install_passwall() {
    info "Adding PassWall2 key..."
    wget -O /tmp/passwall.pub https://master.dl.sourceforge.net/project/openwrt-passwall-build/passwall.pub >> "$LOG_FILE" 2>&1
    check_status "Download of PassWall2 key"
    opkg-key add /tmp/passwall.pub >> "$LOG_FILE" 2>&1
    check_status "Add PassWall2 key"

    read release arch << EOFF
$(. /etc/openwrt_release ; echo ${DISTRIB_RELEASE%.*} $DISTRIB_ARCH)
EOFF

    for feed in passwall_packages passwall2; do
      grep -q "$feed" /etc/opkg/customfeeds.conf || \
      echo "src/gz $feed ${PASSWALL_FEED_BASE}-${release}/${arch}/$feed" >> /etc/opkg/customfeeds.conf
    done

    info "Updating package lists..."
    opkg update >> "$LOG_FILE" 2>&1
    check_status "opkg update"

    PACKAGES="sing-box hysteria luci-app-passwall2 v2ray-geosite-ir"
    for PKG in $PACKAGES; do
        if ! opkg list-installed | grep -q "^$PKG "; then
            info "Installing $PKG..."
            opkg install $PKG >> "$LOG_FILE" 2>&1
            check_status "Installation of $PKG"
        else
            warning "$PKG already installed, skipping."
        fi
    done

    info "Configuring PassWall2 for Iran..."
    sed -i "s/China/Iran/g" /etc/config/passwall2 /usr/share/passwall2/0_default_config
    sed -i "s/geoip:cn/geoip:ir/g" /etc/config/passwall2 /usr/share/passwall2/0_default_config
    sed -i "s/geosite:cn/geosite:category-ir\next:iran.dat:all/g" /etc/config/passwall2 /usr/share/passwall2/0_default_config
    success "PassWall2 configured for Iran"
}

# نصب AmneziaWG
AWG_PACKAGES="kmod-amneziawg amneziawg-tools luci-proto-amneziawg"
for PKG in $AWG_PACKAGES; do
    if ! opkg list-installed | grep -q "^$PKG "; then
        install_awg_package "$PKG"
    else
        warning "$PKG already installed, skipping."
    fi
done

# نصب PassWall2
install_passwall

success "Combined installation of AmneziaWG and PassWall2 completed."

# ریبوت اختیاری
read -p "Do you want to reboot now? [y/N]: " REBOOT_CONFIRM
case "$REBOOT_CONFIRM" in
    [yY]|[yY][eE][sS])
        info "Rebooting system..."
        reboot
        ;;
    *)
        info "Reboot skipped. Installation complete."
        ;;
esac
