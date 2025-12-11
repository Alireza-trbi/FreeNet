#!/bin/ash
#
# This script installs and configures Passwall2 on OpenWRT 24.10.4.
# It follows the provided tutorial steps automatically, verifying each step.
# Optional features can be enabled via command-line arguments or user prompts.
# Skips repository key and addition if repositories exist and initial update succeeds.
#
# Usage: ./install_passwall2.sh [--ir] [--rebind]
#   --ir: Automatically add Iranian rebind domains and configurations without prompt
#   --rebind: Allow iranian vulnrable websitest to rebind to local ip addresses.
#
# Copyright (C) 2025 DARKMATTER
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

. $(pwd)/lib.sh
# Parse command-line arguments
iran_hosted_domains=0
rebind=0


# If no arguments were provided, prompt for installations
if [ $# -eq 0 ]; then
    if prompt_yes_no "Do you want to install and configure list of Iranian websites to Passwall2?"; then
        iran_hosted_domains=true
    fi

    if prompt_yes_no "Do you want to Allow Vulnrable iranian domains to rebind to local addresses? (Optional)"; then
        rebind=true
    fi
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --ir)
            iran_hosted_domains=1
            shift
            ;;
        --rebind)
            rebind=1
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Prerequisite: System information and version check
info "Gathering system information..."

# Source OpenWRT release info to get architecture and version
. /etc/openwrt_release

# Get device model and board name using ubus and jsonfilter
DEVICE_MODEL=$(ubus call system board | jsonfilter -e '@.model')
BOARD_NAME=$(ubus call system board | jsonfilter -e '@.board_name')

# Get device ID for firmware selector
# For x86 targets (x86*), use 'generic'; otherwise, use board_name or fall back to model
case "$DISTRIB_TARGET" in
    x86*)
        DEVICE_ID="generic"
        ;;
    *)
        DEVICE_ID=$(echo "$BOARD_NAME" | awk '{print tolower($0)}' | sed 's/[^a-z0-9]/_/g' | sed 's/_$//')
        if [ -z "$DEVICE_ID" ]; then
            DEVICE_ID=$(echo "$DEVICE_MODEL" | awk '{print tolower($0)}' | sed 's/[^a-z0-9]/_/g' | sed 's/_$//')
        fi
        ;;
esac

# Get total memory in bytes and convert to MB
TOTAL_MEMORY=$(ubus call system info | jsonfilter -e '@.memory.total')
TOTAL_MEMORY_MB=$((TOTAL_MEMORY / 1024 / 1024))

# Get free space on root filesystem in kB and convert to MB
FREE_SPACE=$(ubus call system info | jsonfilter -e '@.root.free')
FREE_SPACE_MB=$((FREE_SPACE / 1024))

# Print system information
info "Device Model: $DEVICE_MODEL"
info "Architecture: $DISTRIB_ARCH"
info "OpenWrt Version: $DISTRIB_RELEASE"
info "Total Memory: $TOTAL_MEMORY_MB MB"
info "Free Space: $FREE_SPACE_MB MB"

# Check if memory is less than 256MB
if [ "$TOTAL_MEMORY_MB" -lt 256 ]; then
    warning "Low memory detected! Total memory is less than 256MB."
    warning "Consider upgrading your device or optimizing system resources."
fi

# Check if architecture is x86 family and free space is less than 100MB
case "$DISTRIB_ARCH" in
    *x86* | i386 | i686)
        if [ "$FREE_SPACE_MB" -lt 100 ]; then
            warning "Low free space detected on x86 architecture! Free space is less than 100MB."
            warning "Consider freeing up space or expanding storage."
        fi
        ;;
esac

# Define recommended packages
RECOMMENDED_PACKAGES="-dnsmasq coreutils coreutils-base64 coreutils-nohup curl ip-full kmod-nft-socket kmod-nft-tproxy libc libuci-lua lua luci-compat luci-lib-jsonc luci-lua-runtime resolveip unzip v2ray-geoip v2ray-geosite v2ray-geosite-ir wget-ssl kmod-inet-diag kmod-netlink-diag kmod-tun dnsmasq-full xray-core"

# Check OpenWrt version and provide upgrade instructions
# Extract major and minor version numbers
MAJOR_VERSION=$(echo "$DISTRIB_RELEASE" | cut -d '.' -f 1)
MINOR_VERSION=$(echo "$DISTRIB_RELEASE" | cut -d '.' -f 2,3)

# Get target for firmware selector link
TARGET=$(echo "$DISTRIB_TARGET" | sed 's/\//%2F/g')

# Call version check function
        check_status "opkg install $pkg"
    fi
done
success "luci-app-passwall2 installed."

# Step 7: Install and configure Iran Hosted Domain list
if [ $iran_hosted_domains -eq 1 ]; then
    if ! is_installed "luci-app-passwall2"; then
        error "luci-app-passwall2 is not installed. Cannot configure Iran-specific settings."
    fi
    info "Installing v2ray-geosite-ir..."
    for pkg in v2ray-geosite-ir; do
        if is_installed "$pkg"; then
            warning "$pkg is already installed. Skipping."
        else
            opkg install $pkg
            check_status "opkg install $pkg"
        fi
    done
    success "v2ray-geosite-ir installed."



    info "Replacing configurations for Iran..."
    if  is_installed "luci-app-passwall2" && is_installed "v2ray-geosite-ir"; then
        hash=$(sha256sum /usr/share/passwall2/0_default_config | awk '{print $1}')
        if [ "$hash" != "b00ca3d09a63550f8a241398ae6493234914b7bf406a48c3fe42a4888e30d2ee" ]; then
            
            config_name="0_default_config_irhosted"
            [ -f "$(pwd)/resources/$config_name" ] && offline_config="$(pwd)/resources/$config_name"
            [ -f "$(pwd)/$config_name" ] && offline_config="$(pwd)/$config_name"
            if [ -f "$offline_config" ]; then
                info "offline config already exists, skipping download."
                cp $offline_config /usr/share/passwall2/0_default_config
                check_status "cp to /usr/share/passwall2/0_default_config"
            else
                wget https://github.com/iranopenwrt/auto/releases/latest/download/0_default_config_irhosted -O /usr/share/passwall2/0_default_config
                check_status "wget 0_default_config_irhosted"
            fi
            cp /usr/share/passwall2/0_default_config /etc/config/passwall2
            check_status "cp to /etc/config/passwall2"
            success "Added passwall2 IR configuration."
        else
            warning "Configuration file hash matches expected value. Skipping replacement."
        fi
    else
        warning "packages luci-app-passwall2 and v2ray-geosite-ir are not installed. Skipping configuration replacement."
    fi

fi
     # Substep: Add rebind domains
if [ $rebind -eq 1 ]; then
    info "Adding rebind domains..."
    domains="qmb.ir medu.ir tamin.ir ebanksepah.ir banksepah.ir gov.ir"
    for domain in $domains; do
        # Check if domain already exists in rebind_domain list
        if uci get dhcp.@dnsmasq[0].rebind_domain 2>/dev/null | grep -q -w "$domain"; then
            warning "Rebind domain $domain already added. Skipping."
        else
            uci add_list dhcp.@dnsmasq[0].rebind_domain="$domain"
            check_status "uci add_list for $domain"
        fi
    done
    uci commit dhcp
    check_status "uci commit dhcp"
    success "Rebind domains added."
else
    success "Skipped adding Iranian website rebind list."
fi


# Final message
success "Installation and configuration of Passwall2 completed successfully."
info "Please restart relevant services or reboot if necessary."