#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/files/etc/uci-defaults/98-r4s-docker-storage.sh"
WORKFLOW="$ROOT/.github/workflows/build-rockchip-25.12.x.yml"
BUILD="$ROOT/rockchip/build25.sh"
IGNORE="$ROOT/.gitignore"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ -x "$SCRIPT" ] || fail "Docker storage initializer is missing or not executable"
sh -n "$SCRIPT" || fail "Docker storage initializer has invalid shell syntax"

grep -q "default: '2G'" "$WORKFLOW" || fail "Rockchip rootfs default is not 2G"
grep -q "default: 'friendlyarm_nanopi-r4s'" "$WORKFLOW" || fail "Rockchip profile default is not the NanoPi R4S"
grep -q 'ROOTFS_SIZE=2048' "$WORKFLOW" || fail "2G does not map to 2048 MiB"
grep -q 'source shell/apk-custom-packages.sh' "$BUILD" || fail "25.12 build does not load APK custom packages"
grep -q 'luci-app-dockerman' "$BUILD" || fail "English Docker LuCI application is absent"
! grep -q 'luci-i18n-dockerman-zh-cn' "$BUILD" || fail "Chinese Docker translation should not be installed"
grep -q 'parted' "$BUILD" || fail "partitioning prerequisite is absent"
grep -q 'e2fsprogs' "$BUILD" || fail "ext4 formatting prerequisite is absent"

for pattern in 'local-backups/' 'router-backups/' '.env' '.env.*' '*.env' '*.key' '*.pem' '*.p12' '*.pfx' '*.ovpn' '*.mobileconfig'; do
    grep -Fqx "$pattern" "$IGNORE" || fail "missing ignore rule: $pattern"
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/etc/config" "$TMP/opt/docker" \
    "$TMP/sys/class/block/mmcblk0p2" "$TMP/tmp/sysinfo"
LOG="$TMP/calls.log"
: >"$LOG"
printf '%s\n' 'friendlyarm,nanopi-r4s' >"$TMP/tmp/sysinfo/board_name"
printf '%s\n' '32768' >"$TMP/sys/class/block/mmcblk0p2/start"
printf '%s\n' '4194304' >"$TMP/sys/class/block/mmcblk0p2/size"

cat >"$TMP/bin/cat" <<'EOF'
#!/bin/sh
case "$1" in
  /tmp/sysinfo/board_name) printf '%s\n' 'friendlyarm,nanopi-r4s' ;;
  /proc/partitions) printf '%s\n' 'major minor  #blocks  name' '179 0 124868608 mmcblk0' '179 1 16384 mmcblk0p1' '179 2 2097152 mmcblk0p2' ;;
  *) exec /bin/cat "$@" ;;
esac
EOF
cat >"$TMP/bin/parted" <<EOF
#!/bin/sh
printf 'parted %s\n' "\$*" >>'$LOG'
touch '$TMP/state/partition-created'
EOF
cat >"$TMP/bin/dockerd" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/bin/partprobe" <<EOF
#!/bin/sh
printf 'partprobe %s\n' "\$*" >>'$LOG'
EOF
cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$TMP/bin/mkfs.ext4" <<EOF
#!/bin/sh
printf 'mkfs.ext4 %s\n' "\$*" >>'$LOG'
touch '$TMP/state/formatted'
EOF
cat >"$TMP/bin/block" <<EOF
#!/bin/sh
[ "\$1" = info ] || exit 0
if [ -e '$TMP/state/formatted' ]; then
    printf '%s\n' '/dev/mmcblk0p3: UUID="docker-uuid" TYPE="ext4"'
else
    printf '%s\n' '/dev/mmcblk0p3:'
fi
EOF
cat >"$TMP/bin/uci" <<EOF
#!/bin/sh
printf 'uci %s\n' "\$*" >>'$LOG'
EOF
cat >"$TMP/bin/mount" <<EOF
#!/bin/sh
printf 'mount %s\n' "\$*" >>'$LOG'
EOF
cat >"$TMP/bin/logger" <<EOF
#!/bin/sh
printf 'logger %s\n' "\$*" >>'$LOG'
EOF
chmod +x "$TMP/bin/"*

PATH="$TMP/bin:/usr/bin:/bin" \
R4S_STORAGE_TEST_ROOT="$TMP" \
R4S_STORAGE_TEST_PARTITION="$TMP/state/partition-created" \
sh "$SCRIPT"

grep -q 'parted .*mkpart.*100%' "$LOG" || fail "remaining-space partition was not created"
grep -q 'mkfs.ext4 .*docker' "$LOG" || fail "Docker partition was not formatted"
grep -q "uci set fstab.docker.target=/opt/docker" "$LOG" || fail "Docker mount target was not configured"
grep -q "uci set dockerd.globals.data_root=/opt/docker" "$LOG" || fail "dockerd data root was not configured"
grep -q "uci set dockerd.globals.bip=172.30.0.1/24" "$LOG" || fail "Docker bridge subnet was not pinned away from the IoT network"
! grep -q "172.16.0.0/12" "$ROOT/files/etc/uci-defaults/99-custom.sh" || fail "Docker firewall still overlaps the IoT subnet"
grep -q "list network 'docker'" "$ROOT/files/etc/uci-defaults/99-custom.sh" || fail "Docker firewall zone is not bound to the Docker network"

cp "$LOG" "$TMP/first.log"
: >"$LOG"
PATH="$TMP/bin:/usr/bin:/bin" \
R4S_STORAGE_TEST_ROOT="$TMP" \
R4S_STORAGE_TEST_PARTITION="$TMP/state/partition-created" \
sh "$SCRIPT"

! grep -q 'parted ' "$LOG" || fail "initializer repartitioned storage on its second run"

# A pre-existing third partition with an unknown filesystem must never be
# formatted. It may contain personal data from an earlier installation.
rm -f "$TMP/state/formatted"
touch "$TMP/state/pre-existing-partition"
: >"$LOG"
if PATH="$TMP/bin:/usr/bin:/bin" \
    R4S_STORAGE_TEST_ROOT="$TMP" \
    R4S_STORAGE_TEST_PARTITION="$TMP/state/pre-existing-partition" \
    sh "$SCRIPT"; then
    fail "initializer accepted a pre-existing non-ext4 partition"
fi
! grep -q 'mkfs.ext4 ' "$LOG" || fail "initializer formatted a pre-existing partition"

echo "PASS: R4S Docker storage provisioning contract"
