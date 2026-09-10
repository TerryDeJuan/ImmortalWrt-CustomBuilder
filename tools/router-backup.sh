#!/bin/sh
# Create configuration, package, service, and selected data backups.
set -eu

OUT="${1:-/tmp/immortalwrt-backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
umask 077

# Native sysupgrade archive: safest source for selective restoration.
if command -v sysupgrade >/dev/null 2>&1; then
    sysupgrade -b "$OUT/sysupgrade-backup.tar.gz"
    sysupgrade -l >"$OUT/sysupgrade-file-list.txt" 2>&1 || true
    sysupgrade -k -b "$OUT/sysupgrade-backup-with-packages.tar.gz" 2>"$OUT/sysupgrade-with-packages.err" || true
fi

if command -v apk >/dev/null 2>&1; then
    apk list --installed >"$OUT/packages-installed.txt" 2>&1
    apk info >"$OUT/package-names.txt" 2>&1
elif command -v opkg >/dev/null 2>&1; then
    opkg list-installed >"$OUT/packages-installed.txt" 2>&1
    opkg list-changed-conffiles >"$OUT/package-changed-conffiles.txt" 2>&1 || true
    sed -ne '/^Package:[[:blank:]]*/ { s///; h } /user installed/ { g; p }' \
        /usr/lib/opkg/status >"$OUT/packages-user-installed.txt" 2>/dev/null || true
fi

for f in /etc/rc.d/S*; do
    [ -e "$f" ] && basename "$f"
done >"$OUT/services-enabled.txt"
ps w >"$OUT/processes-running.txt" 2>&1 || true

# Preserve commonly used custom data if present. Extend this list deliberately.
set -- /etc/config /etc/dropbear /etc/crontabs /etc/firewall.user /etc/sysupgrade.conf \
       /etc/openclash /etc/mosdns /etc/AdGuardHome.yaml /etc/tailscale \
       /root/.ssh /root/scripts /usr/share/AdGuardHome
existing=""
for path in "$@"; do
    [ -e "$path" ] && existing="$existing ${path#/}"
done
if [ -n "$existing" ]; then
    # Paths are fixed above and contain no spaces on a stock OpenWrt installation.
    tar -C / -czf "$OUT/selected-config-and-data.tar.gz" $existing
fi

cat >"$OUT/RESTORE-NOTES.txt" <<'EOF'
Do not blindly restore this archive over a new major release.
1. Boot the new image with its defaults and confirm console/network access.
2. Reinstall required packages from the reviewed package list.
3. Compare old and new /etc/config files; merge settings selectively.
4. Restore keys, certificates, scripts, and application data only to matching services.
5. Review any *-opkg or *-apknew files and restart one service at a time.
Never copy password hashes, private keys, PPPoE credentials, VPN keys, or certificates into Git.
EOF

printf '%s\n' "Backup written to $OUT"
printf '%s\n' "Copy the entire directory off the router before flashing."
