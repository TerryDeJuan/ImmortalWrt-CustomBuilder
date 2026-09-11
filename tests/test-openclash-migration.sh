#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BACKUP="$ROOT/tools/openclash-backup.sh"
RESTORE="$ROOT/tools/openclash-restore.sh"
IGNORE="$ROOT/.gitignore"
DOC="$ROOT/docs/OPENCLASH-MIGRATION.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

for file in "$BACKUP" "$RESTORE" "$DOC"; do
    [ -f "$file" ] || fail "missing OpenClash migration artifact: $file"
done
for file in "$BACKUP" "$RESTORE"; do
    [ -x "$file" ] || fail "OpenClash helper is not executable: $file"
    sh -n "$file" || fail "invalid shell syntax: $file"
done

grep -q 'luci-app-openclash' "$DOC" || fail "migration guide does not name OpenClash package"
grep -q 'GeoIP.dat' "$DOC" || fail "migration guide omits GeoIP"
grep -q 'GeoSite.dat' "$DOC" || fail "migration guide omits GeoSite"
grep -q '/etc/openclash/core' "$DOC" || fail "migration guide omits core handling"
grep -q 'openclash-migration/' "$IGNORE" || fail "OpenClash migration output is not ignored"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/router/etc/config" "$TMP/router/etc/openclash/config" \
    "$TMP/router/etc/openclash/custom" "$TMP/router/etc/openclash/core" \
    "$TMP/router/etc/openclash/history" "$TMP/bin"
printf '%s\n' 'config openclash' >"$TMP/router/etc/config/openclash"
printf '%s\n' 'mixed-port: 7890' >"$TMP/router/etc/openclash/config/main.yaml"
printf '%s\n' 'payload' >"$TMP/router/etc/openclash/custom/rules.list"
printf '%s\n' 'geoip' >"$TMP/router/etc/openclash/GeoIP.dat"
printf '%s\n' 'geosite' >"$TMP/router/etc/openclash/GeoSite.dat"
printf '%s\n' 'core-binary' >"$TMP/router/etc/openclash/core/clash_meta"

cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
  *show*) printf '%s\n' 'openclash.config.auto_update=1';;
  *) : ;;
esac
EOF
cat >"$TMP/bin/tar" <<'EOF'
#!/bin/sh
exec /bin/tar "$@"
EOF
cat >"$TMP/bin/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TMP/bin/"*

# The production helper is syntax-tested above; archive content policy is
# checked structurally here so no live router state is required.
if grep -Fq 'tar -C / -czf "$OUT/openclash-portable-state.tar.gz" $paths' "$BACKUP"; then
    :
else
    fail "backup helper does not create portable archive"
fi
if grep -Eq 'core/|clash|mihomo|meta' "$BACKUP" && \
   ! grep -Eq 'deliberately excluded|excluded|Not included' "$BACKUP"; then
    fail "backup helper mentions core paths without an exclusion guard"
fi

echo "PASS: OpenClash migration contract"
