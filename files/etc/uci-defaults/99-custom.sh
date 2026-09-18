#!/bin/sh
# 99-custom.sh runs on the first boot of ImmortalWrt firmware and is located at /etc/uci-defaults/99-custom.sh in the firmware
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

# Set the firmware identity and initial administrative credentials.
# Change the password immediately after first boot over the trusted LAN.
uci set system.@system[0].hostname='peachwrt'
uci commit system
if command -v chpasswd >/dev/null 2>&1; then
    printf '%s\n' 'root:changeme' | chpasswd
else
    echo "chpasswd is unavailable; root password was not changed" >>$LOGFILE
fi

# Set build author information
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="PeachWRT"
if [ -f "$FILE_PATH" ]; then
    sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
fi

# Set the default firewall rule so single-interface virtual machines can access the WebUI on first use
# In this project, single-interface mode uses DHCP, allowing immediate internet and web access without requiring users to change the static IP in /etc/config/network
# After flashing and completing setup, you can disable inbound WAN firewall traffic from the web interface
# To do so, go to Network -> Firewall, select Reject for WAN inbound traffic, then save and apply
if [ "$(cat /tmp/sysinfo/board_name 2>/dev/null || true)" = "friendlyarm,nanopi-r4s" ]; then
    # The R4S VLAN initializer owns its network and firewall policy.
    exit 0
fi
uci set firewall.@zone[1].input='ACCEPT'

# Set a hostname mapping to fix connectivity issues on stock Android TV.
# Not required for PeachWRT, so this optional workaround remains disabled.
# uci add dhcp domain
# uci set "dhcp.@domain[-1].name=time.android.com"
# uci set "dhcp.@domain[-1].ip=203.107.6.88"

# Check whether pppoe-settings exists; build.sh generates this file dynamically
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # Read PPPoE information ($enable_pppoe, $pppoe_account, $pppoe_password)
    . "$SETTINGS_FILE"
fi

# 1. First obtain the list of all physical interfaces
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. Map WAN and LAN interfaces based on the board model
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# Handle interface ordering for specific development boards here
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *)
        # Use the first interface as WAN and the rest as LAN by default
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
esac

# 3. Configure the network
if [ "$count" -eq 1 ]; then
    # Single-interface device in DHCP mode
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # Multi-interface device configuration
    # Configure WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # Configure WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # Find the br-lan device section
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # Delete the existing ports
        uci -q delete "network.$section.ports"
        # Add LAN interface ports
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # Set a static IP on LAN
    uci set network.lan.proto='static'
    # Multi-interface devices support a custom management address entered in the GitHub Actions UI
    uci set network.lan.netmask='255.255.255.0'
    # Set the router management address
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # Router management address set by the user in the UI
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

    # PPPoE settings
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network
fi

# Allow web-terminal access on all interfaces
uci delete ttyd.@ttyd[0].interface

# Allow SSH connections on all interfaces
uci set dropbear.@dropbear[0].Interface=''
uci commit

# If luci-app-advancedplus (Advanced Settings) is installed, remove zsh calls to prevent the /usb/bin/zsh: not found message
if [ -f /usr/lib/lua/luci/controller/advancedplus.lua ]; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
    echo "fix ttyd show msg: /usb/bin/zsh: not found" >>$LOGFILE
fi

# Run only when luci-app-quickfile is installed
if [ -f /usr/bin/quickfile ]; then
    uci set nginx.global.uci_enable='true'
    uci del nginx._lan 2>/dev/null
    uci del nginx._redirect2ssl 2>/dev/null

    uci add nginx server
    uci rename nginx.@server[-1]='_lan'

    uci set nginx._lan.server_name='_lan'
    uci add_list nginx._lan.listen='80 default_server'
    uci add_list nginx._lan.listen='[::]:80 default_server'
    uci add_list nginx._lan.include='conf.d/*.locations'
    uci set nginx._lan.access_log='off; # logd openwrt'

    uci commit nginx
    echo "fix quickfile nginx config" >>$LOGFILE
fi

# Configure Docker firewall rules if dockerd is installed. The dockerd package
# owns the docker0 network/interface; do not match a broad private address range
# because it can overlap the R4S IoT subnet 172.31.12.0/24.
if command -v dockerd >/dev/null 2>&1; then
    echo "Docker detected; configuring firewall rules..."
    FW_FILE="/etc/config/firewall"

    # Delete all zones named docker
    uci delete firewall.docker

    # Obtain all forwarding indexes first, then delete them in reverse order
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # Commit the deletions
    uci commit firewall

# Append the new zone and forwarding configuration. Bind it to the named
# Docker network rather than a broad source subnet.
cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list network 'docker'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "Docker was not detected; skipping firewall configuration."
fi

exit 0
