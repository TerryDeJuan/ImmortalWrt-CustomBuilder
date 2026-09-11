#!/bin/sh
# Configure the R4S trunk and the requested isolated Guest/IoT zones.
set -eu

[ "$(cat /tmp/sysinfo/board_name 2>/dev/null || true)" = "friendlyarm,nanopi-r4s" ] || exit 0

# The switch/AP trunk is eth1. LAN keeps the old 10.0.3.0/24 subnet on VLAN 98.
uci -q set network.lan.device='br-lan.98'
uci -q set network.lan.proto='static'
uci -q set network.lan.ipaddr='10.0.3.1'
uci -q set network.lan.netmask='255.255.255.0'

uci -q delete network.br_lan
uci -q set network.br_lan='device'
uci -q set network.br_lan.name='br-lan'
uci -q set network.br_lan.type='bridge'
uci -q delete network.br_lan.ports
uci -q add_list network.br_lan.ports='eth1'

for zone in guest iot; do
    uci -q delete "network.$zone"
done

uci -q set network.guest_dev='device'
uci -q set network.guest_dev.type='8021q'
uci -q set network.guest_dev.ifname='br-lan'
uci -q set network.guest_dev.vid='37'
uci -q set network.guest_dev.name='br-lan.37'
uci -q set network.guest='interface'
uci -q set network.guest.device='br-lan.37'
uci -q set network.guest.proto='static'
uci -q set network.guest.ipaddr='192.168.37.1'
uci -q set network.guest.netmask='255.255.255.0'
uci -q set network.guest.delegate='0'

uci -q set network.iot_dev='device'
uci -q set network.iot_dev.type='8021q'
uci -q set network.iot_dev.ifname='br-lan'
uci -q set network.iot_dev.vid='12'
uci -q set network.iot_dev.name='br-lan.12'
uci -q set network.iot='interface'
uci -q set network.iot.device='br-lan.12'
uci -q set network.iot.proto='static'
uci -q set network.iot.ipaddr='172.31.12.1'
uci -q set network.iot.netmask='255.255.255.0'
uci -q set network.iot.delegate='0'

# Preserve the existing WAN mode without placing credentials in Git. The
# builder creates this file from private workflow input at image-build time.
if [ -f /etc/config/pppoe-settings ]; then
    . /etc/config/pppoe-settings
    if [ "${enable_pppoe:-no}" = "yes" ]; then
        uci -q set network.wan.proto='pppoe'
        uci -q set network.wan.username="$pppoe_account"
        uci -q set network.wan.password="$pppoe_password"
        uci -q set network.wan.peerdns='1'
        uci -q set network.wan6.proto='none'
    fi
fi

uci -q set dhcp.guest='dhcp'
uci -q set dhcp.guest.interface='guest'
uci -q set dhcp.guest.start='100'
uci -q set dhcp.guest.limit='100'
uci -q set dhcp.guest.leasetime='12h'
uci -q set dhcp.iot='dhcp'
uci -q set dhcp.iot.interface='iot'
uci -q set dhcp.iot.start='100'
uci -q set dhcp.iot.limit='100'
uci -q set dhcp.iot.leasetime='12h'

# Guest can reach only router DHCP/DNS/NTP/ping. There is deliberately no
# guest->lan or guest->wan forwarding rule here.
uci -q delete firewall.guest
uci -q set firewall.guest='zone'
uci -q set firewall.guest.name='guest'
uci -q set firewall.guest.network='guest'
uci -q set firewall.guest.input='REJECT'
uci -q set firewall.guest.output='ACCEPT'
uci -q set firewall.guest.forward='REJECT'

for service in dns dhcp ntp; do
    section="guest_$service"
    uci -q delete "firewall.$section"
    uci -q set "firewall.$section=rule"
    uci -q set "firewall.$section.name=Guest_$service"
    uci -q set "firewall.$section.src=guest"
    uci -q set "firewall.$section.dest_port=$([ "$service" = dns ] && echo 53 || [ "$service" = dhcp ] && echo 67 || echo 123)"
    uci -q set "firewall.$section.proto=$([ "$service" = dhcp ] && echo udp || echo 'tcp udp')"
    uci -q set "firewall.$section.target=ACCEPT"
done
uci -q set firewall.guest_ping='rule'
uci -q set firewall.guest_ping.name='Guest_ping_router'
uci -q set firewall.guest_ping.src='guest'
uci -q set firewall.guest_ping.proto='icmp'
uci -q set firewall.guest_ping.icmp_type='echo-request'
uci -q set firewall.guest_ping.target='ACCEPT'

# IoT can reach the router only through DHCP/DNS/NTP/ping and can forward to
# LAN. WAN and Guest forwarding are intentionally absent. Remote private routes
# may be added later as space-separated CIDRs in IOT_REMOTE_PRIVATE_SUBNETS.
uci -q delete firewall.iot
uci -q set firewall.iot='zone'
uci -q set firewall.iot.name='iot'
uci -q set firewall.iot.network='iot'
uci -q set firewall.iot.input='REJECT'
uci -q set firewall.iot.output='ACCEPT'
uci -q set firewall.iot.forward='REJECT'
uci -q set firewall.iot_to_lan='forwarding'
uci -q set firewall.iot_to_lan.src='iot'
uci -q set firewall.iot_to_lan.dest='lan'

for service in dns dhcp ntp; do
    section="iot_$service"
    uci -q delete "firewall.$section"
    uci -q set "firewall.$section=rule"
    uci -q set "firewall.$section.name=IoT_$service"
    uci -q set "firewall.$section.src=iot"
    uci -q set "firewall.$section.dest_port=$([ "$service" = dns ] && echo 53 || [ "$service" = dhcp ] && echo 67 || echo 123)"
    uci -q set "firewall.$section.proto=$([ "$service" = dhcp ] && echo udp || echo 'tcp udp')"
    uci -q set "firewall.$section.target=ACCEPT"
done
uci -q set firewall.iot_ping='rule'
uci -q set firewall.iot_ping.name='IoT_ping_router'
uci -q set firewall.iot_ping.src='iot'
uci -q set firewall.iot_ping.proto='icmp'
uci -q set firewall.iot_ping.icmp_type='echo-request'
uci -q set firewall.iot_ping.target='ACCEPT'

# Future remote-private access is intentionally not created automatically.
# Add reviewed firewall rules for IOT_REMOTE_PRIVATE_SUBNETS later, selecting
# the actual WireGuard zone/interface for each remote network. Never add WAN.

uci -q commit network
uci -q commit dhcp
uci -q commit firewall
/etc/init.d/network reload 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true
/etc/init.d/firewall reload 2>/dev/null || true
