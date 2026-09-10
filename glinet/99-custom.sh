#!/bin/sh
# This script runs as /etc/uci-defaults/99-custom.sh on the first boot of ImmortalWrt; it disappears from the router after reboot and runs only once
# Set the default firewall rule so virtual machines can access the WebUI on first use
LOGFILE="/etc/config/uci-defaults-log.txt"
uci set firewall.@zone[1].input='ACCEPT'

# Set a hostname mapping to fix connectivity issues on stock Android TV
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# Check whether the configuration file exists
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # Read PPPoE information (written by build.sh)
   . "$SETTINGS_FILE"
fi
# Set the subnet mask
uci set network.lan.netmask='255.255.255.0'
# Set the router management address
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
if [ -f "$IP_VALUE_FILE" ]; then
    CUSTOM_IP=$(cat "$IP_VALUE_FILE")
    # Set the router management address
    uci set network.lan.ipaddr=$CUSTOM_IP
    echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
fi


# Determine whether PPPoE is enabled
echo "print enable_pppoe value=== $enable_pppoe" >> $LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE is enabled at $(date)" >> $LOGFILE
    # Set dial-up information
    uci set network.wan.proto='pppoe'                
    uci set network.wan.username=$pppoe_account     
    uci set network.wan.password=$pppoe_password     
    uci set network.wan.peerdns='1'                  
    uci set network.wan.auto='1' 
    echo "PPPoE configuration completed successfully." >> $LOGFILE
else
    echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
fi

# Configure Docker firewall rules if dockerd is installed
# Expand the subnet range covered by Docker to '172.16.0.0/12'
# Allow ports from various Docker containers to pass through the firewall
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
    # Append the new zone and forwarding configuration
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

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

# Allow web-terminal access on all interfaces
uci delete ttyd.@ttyd[0].interface

# Allow SSH connections on all interfaces
uci set dropbear.@dropbear[0].Interface=''
uci commit

# Set build author information
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

exit 0
