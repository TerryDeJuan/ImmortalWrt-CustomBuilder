#!/bin/sh
# Restore portable OpenClash state after installing OpenClash and its core.
set -eu

ARCHIVE=${1:?usage: $0 /path/to/openclash-portable-state.tar.gz}
[ -f "$ARCHIVE" ] || { echo "Archive not found: $ARCHIVE" >&2; exit 1; }

command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
command -v uci >/dev/null 2>&1 || { echo "uci is required" >&2; exit 1; }

# Refuse archives that contain executable core paths.
if tar -tzf "$ARCHIVE" | grep -Eq '(^|/)core/|(^|/)(clash|mihomo|meta)$'; then
    echo "Refusing an archive containing an OpenClash core executable" >&2
    exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
ROLLBACK="/tmp/openclash-before-restore-$STAMP.tar.gz"
paths="etc/config/openclash etc/openclash"
existing=""
for path in $paths; do
    [ -e "/$path" ] && existing="$existing $path"
done
[ -n "$existing" ] && tar -C / -czf "$ROLLBACK" $existing

tar -C / -xzf "$ARCHIVE"

# Re-apply the config through UCI when the snapshot is present. This makes the
# import explicit and leaves a rollback archive if the schema needs adjustment.
if tar -tzf "$ARCHIVE" | grep -qx 'etc/config/openclash'; then
    uci commit openclash || true
fi

/etc/init.d/openclash restart 2>/dev/null || true
printf '%s\n' "OpenClash portable state restored. Rollback archive: $ROLLBACK"
printf '%s\n' "Verify the selected config, core version, proxy providers, and Geo databases before enabling autostart."
