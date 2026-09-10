#!/bin/bash
source shell/custom-packages.sh
source shell/switch_repository.sh
echo "Third-party packages: $CUSTOM_PACKAGES"
# Router model PROFILE passed from YAML
echo "Building for profile: $PROFILE"
echo "Include Docker: $INCLUDE_DOCKER"
# Firmware size ROOTFS_PARTSIZE passed from YAML
echo "Building for ROOTFS_PARTSIZE: $ROOTSIZE"
if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ No third-party packages selected"
else
  # Download the run file repository
  echo "🔄 Syncing the third-party package repository. Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # Copy all run and ipk files under run/arm64 to the extra-packages directory
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/arm64/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # Extract and copy ipk files to the packages directory
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi


LUCI_VERSION="${LUCI_VERSION:-24.10.4}"  # LuCI version passed from the workflow; defaults to 24.10.4
# Select CPU_ARCH based on PROFILE
case "$PROFILE" in
  rpi-3)
    CPU_ARCH="aarch64_cortex-a53"
    ;;
  rpi-4)
    CPU_ARCH="aarch64_cortex-a72"
    ;;
  rpi-5)
    CPU_ARCH="aarch64_cortex-a76"
    ;;
  *)
    CPU_ARCH="aarch64_generic"
    ;;
esac

# Insert architecture priority
sed -i "1i\
arch aarch64_generic 10\n\
arch $CPU_ARCH 15" repositories.conf

# Modify the Raspberry Pi repositories.conf paths so generic packages use aarch64_generic, and populate LUCI_VERSION dynamically
sed -i -E "s|(src/gz immortalwrt_base .*aarch64_cortex-a[0-9]+)/base|src/gz immortalwrt_base https://downloads.immortalwrt.org/releases/$LUCI_VERSION/packages/aarch64_generic/base|" repositories.conf
sed -i -E "s|(src/gz immortalwrt_luci .*aarch64_cortex-a[0-9]+)/luci|src/gz immortalwrt_luci https://downloads.immortalwrt.org/releases/$LUCI_VERSION/packages/aarch64_generic/luci|" repositories.conf
sed -i -E "s|(src/gz immortalwrt_packages .*aarch64_cortex-a[0-9]+)/packages|src/gz immortalwrt_packages https://downloads.immortalwrt.org/releases/$LUCI_VERSION/packages/aarch64_generic/packages|" repositories.conf
sed -i -E "s|(src/gz immortalwrt_routing .*aarch64_cortex-a[0-9]+)/routing|src/gz immortalwrt_routing https://downloads.immortalwrt.org/releases/$LUCI_VERSION/packages/aarch64_generic/routing|" repositories.conf
sed -i -E "s|(src/gz immortalwrt_telephony .*aarch64_cortex-a[0-9]+)/telephony|src/gz immortalwrt_telephony https://downloads.immortalwrt.org/releases/$LUCI_VERSION/packages/aarch64_generic/telephony|" repositories.conf
echo "✅ repositories.conf updated for $PROFILE with generic fallback and LUCI_VERSION=$LUCI_VERSION"
echo "Current repositories.conf content:"
cat repositories.conf
# Output debugging information
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting build process..."


# Define the list of packages to install
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
# Services—FileBrowser username admin, password admin
PACKAGES="$PACKAGES luci-i18n-filebrowser-go-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"

#24.10
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
# ======== shell/custom-packages.sh =======
# Merge third-party plugins from outside the ImmortalWrt repository
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# Determine whether to build the Docker plugin
if [ "$INCLUDE_DOCKER" = "yes" ]; then
    PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
    echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# Add the core when building openclash
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
    echo "✅ luci-app-openclash selected; adding openclash core"
    mkdir -p files/etc/openclash/core
    # Download clash_meta
    META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz"
    wget -qO- $META_URL | tar xOvz > files/etc/openclash/core/clash_meta
    chmod +x files/etc/openclash/core/clash_meta
    # Download GeoIP and GeoSite
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -O files/etc/openclash/GeoIP.dat
    wget -q https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -O files/etc/openclash/GeoSite.dat
    # Download latest openclash Client
    URL=$(curl -s https://api.github.com/repos/vernesong/OpenClash/releases/latest \
      | grep "browser_download_url.*ipk" \
      | head -n1 \
      | cut -d '"' -f 4)
    echo "OpenClash latest ipk: $URL"
    wget "$URL" -P /home/build/immortalwrt/packages/
else
    echo "⚪️ luci-app-openclash not selected"
fi

if echo "$PACKAGES" | grep -q "luci-app-ssr-plus"; then
    echo "✅ luci-app-ssr-plus selected; adding mihomo core"
    mkdir -p files/usr/bin
    # Download mihomo
    MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-arm64-v1.19.24.gz"
    mkdir -p files/usr/bin
    wget -qO- "$MIHOMO_URL" | gzip -dc > files/usr/bin/mihomo
    chmod +x files/usr/bin/mihomo
    echo "✅ Downloaded mihomo core"
    ls -lah files/usr/bin
else
    echo "⚪️ luci-app-ssr-plus not selected"
fi



# Build the image
echo "$(date '+%Y-%m-%d %H:%M:%S') - Building image with the following packages:"
echo "$PACKAGES"

make image PROFILE=$PROFILE PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$ROOTSIZE

if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
