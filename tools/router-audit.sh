#!/bin/sh
# Collect a read-only ImmortalWrt hardware and software inventory.
set -eu

OUT="${1:-/tmp/immortalwrt-audit-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"

run() {
    name="$1"
    shift
    {
        printf '$'
        printf ' %s' "$@"
        printf '\n'
        "$@"
    } >"$OUT/$name.txt" 2>&1 || true
}

run release sh -c 'cat /etc/openwrt_release; printf "\n--- os-release ---\n"; cat /etc/os-release 2>/dev/null || true'
run board ubus call system board
run kernel uname -a
run cpu sh -c 'cat /proc/cpuinfo; printf "\n--- nproc ---\n"; getconf _NPROCESSORS_ONLN 2>/dev/null || true'
run memory cat /proc/meminfo
run mounts sh -c 'mount; printf "\n--- df ---\n"; df -h; printf "\n--- block info ---\n"; block info 2>/dev/null || true'
run block-devices sh -c '
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -o NAME,PATH,MAJ:MIN,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,SERIAL
    else
        for dev in /sys/class/block/*; do
            name=${dev##*/}
            sectors=$(cat "$dev/size" 2>/dev/null || echo 0)
            logical=$(cat "$dev/queue/logical_block_size" 2>/dev/null || echo 512)
            bytes=$((sectors * logical))
            printf "%s sectors=%s logical_block=%s bytes=%s\n" "$name" "$sectors" "$logical" "$bytes"
        done
    fi
'
run partitions sh -c 'cat /proc/partitions; printf "\n--- mtd ---\n"; cat /proc/mtd 2>/dev/null || true'
run model sh -c 'cat /tmp/sysinfo/model 2>/dev/null || true; cat /tmp/sysinfo/board_name 2>/dev/null || true; cat /proc/device-tree/model 2>/dev/null || true; printf "\n"'
run network-links sh -c 'ip -details link show; printf "\n--- addresses ---\n"; ip address show; printf "\n--- routes ---\n"; ip route show table all; printf "\n--- IPv6 routes ---\n"; ip -6 route show table all 2>/dev/null || true'
run bridges sh -c 'bridge link show 2>/dev/null || brctl show 2>/dev/null || true; bridge vlan show 2>/dev/null || true'
run firewall sh -c 'fw4 print 2>/dev/null || nft list ruleset 2>/dev/null || iptables-save 2>/dev/null || true'
run modules sh -c 'cat /proc/modules; printf "\n--- module files ---\n"; find /etc/modules.d -maxdepth 1 -type f -print 2>/dev/null || true'
run enabled-services sh -c 'for f in /etc/rc.d/S*; do [ -e "$f" ] && basename "$f"; done'
run running-processes ps w
run listening-sockets sh -c 'ss -lntup 2>/dev/null || netstat -lntup 2>/dev/null || true'
run cron sh -c 'find /etc/crontabs -maxdepth 1 -type f -print 2>/dev/null || true'
run storage-health sh -c 'dmesg | sed -n "/mmc\|sdhci\|I\/O error\|EXT4-fs\|F2FS-fs\|BTRFS/p"'
run overlays sh -c 'df -h / /overlay 2>/dev/null || true; du -sh /overlay/upper 2>/dev/null || true'

if command -v apk >/dev/null 2>&1; then
    run packages apk list --installed
    run package-manager apk --version
elif command -v opkg >/dev/null 2>&1; then
    run packages opkg list-installed
    run changed-conffiles opkg list-changed-conffiles
    run architectures opkg print-architecture
fi

printf '%s\n' "Audit written to $OUT"
printf '%s\n' "Review it for public IPs, MAC addresses, serial numbers, and hostnames before sharing."
