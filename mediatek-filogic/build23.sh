#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh
# This file is the build.sh used inside the ImageBuilder container

if [ -n "$CUSTOM_PACKAGES" ]; then
  echo "✅ You selected third-party packages: $CUSTOM_PACKAGES"
  if [ "$PROFILE" = "glinet_gl-mt3000" ]; then
    echo "❌ Third-party packages were detected, but this is not supported because the mt3000 has limited flash space"
    echo "✅ The system will automatically disable the plugins from shell/custom-packages.sh; models with larger flash, such as mt2500/mt6000, currently support third-party plugin integration"
    CUSTOM_PACKAGES=""
  else
    # Download the run file repository
    echo "🔄 Syncing third-party package repository; cloning run file repo..."
    git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

    # Copy all run and ipk files under run/arm64 to the extra-packages directory
    mkdir -p /home/build/immortalwrt/extra-packages
    cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

    echo "✅ Run files copied to extra-packages:"
    ls -lh /home/build/immortalwrt/extra-packages/*.run
    # Extract and copy ipk files to the packages directory
    sh shell/prepare-packages.sh
    ls -lah /home/build/immortalwrt/packages/
    # Add architecture priority information
    sed -i '1i\
    arch aarch64_generic 10\n\
    arch aarch64_cortex-a53 15' repositories.conf
  fi
else
  echo "⚪️ No third-party packages were selected"
fi
# Router model PROFILE passed from yml
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"
echo "Create pppoe-settings"
mkdir -p  /home/build/immortalwrt/files/etc/config

# Create the PPPoE configuration file: PPPoE variables passed from yml -> pppoe-settings file
cat << EOF > /home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

# Output debugging information
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."


# Define the list of packages to install; you can remove any of the following plugins
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filebrowser-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
#23.05
PACKAGES="$PACKAGES luci-i18n-opkg-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
# Add several required components to make it easier to install iStore
PACKAGES="$PACKAGES fdisk"
PACKAGES="$PACKAGES script-utils"
# Merge third-party packages
# ======== shell/custom-packages.sh =======
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# Determine whether to build the Docker plugin
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# Add the core when building OpenClash
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ Selected luci-app-openclash; adding the OpenClash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
else
    echo "⚪️ luci-app-openclash was not selected"
fi


# Build the image
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files"

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
