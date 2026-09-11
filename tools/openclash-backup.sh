#!/bin/sh
# Export OpenClash state without exporting its version-specific core binaries.
set -eu

OUT="${1:-/tmp/openclash-backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT"
umask 077

command -v tar >/dev/null 2>&1 || {
    echo "tar is required" >&2
    exit 1
}

if command -v uci >/dev/null 2>&1; then
    uci -q show openclash >"$OUT/uci-openclash.txt" || true
fi

if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
    {
        printf 'DISTRIB_ID=%s\n' "${DISTRIB_ID:-}"
        printf 'DISTRIB_RELEASE=%s\n' "${DISTRIB_RELEASE:-}"
        printf 'DISTRIB_REVISION=%s\n' "${DISTRIB_REVISION:-}"
        printf 'DISTRIB_TARGET=%s\n' "${DISTRIB_TARGET:-}"
        printf 'DISTRIB_ARCH=%s\n' "${DISTRIB_ARCH:-}"
    } >"$OUT/platform.txt"
fi

# These are the portable state categories. Core executables are deliberately
# excluded: install a compatible core on the new release instead.
paths=""
for path in \
    etc/config/openclash \
    etc/openclash/config \
    etc/openclash/custom \
    etc/openclash/game_rules \
    etc/openclash/overwrite \
    etc/openclash/proxy_provider \
    etc/openclash/rule_provider \
    etc/openclash/sub-store.yaml \
    etc/openclash/GeoIP.dat \
    etc/openclash/GeoSite.dat \
    etc/openclash/Country.mmdb \
    etc/openclash/ASN.mmdb \
    etc/openclash/china_ip_route.ipset \
    etc/openclash/china_ip6_route.ipset \
    etc/openclash/history; do
    [ -e "/$path" ] && paths="$paths $path"
done

[ -n "$paths" ] || {
    echo "No portable OpenClash state found" >&2
    exit 1
}

tar -C / -czf "$OUT/openclash-portable-state.tar.gz" $paths

tar -tzf "$OUT/openclash-portable-state.tar.gz" \
    | grep -Eq '(^|/)core/|(^|/)(clash|mihomo|meta)$' \
    && {
        echo "Refusing to create an archive containing a core executable" >&2
        exit 1
    } || true

cat >"$OUT/README.txt" <<'EOF'
OpenClash migration export

Included:
- UCI configuration snapshot
- OpenClash YAML configurations and providers
- custom rules, overwrite files, and game rules
- GeoIP.dat, GeoSite.dat, Country.mmdb, and ASN.mmdb when present
- selected history/sub-store state

Not included by design:
- /etc/openclash/core/*
- /etc/openclash/clash or other core symlinks/binaries
- /usr/bin and /usr/lib OpenClash core binaries

Install the new OpenClash package and a compatible Mihomo core on the target
firmware first. Restore this archive only after validating the target paths and
configuration schema. Geo databases can be replaced by fresh downloads after
restore; retaining the old copies is a rollback aid, not a substitute for
refreshing them.
EOF

printf '%s\n' "OpenClash portable backup written to $OUT"
printf '%s\n' "Copy $OUT off the router and keep it out of Git."
