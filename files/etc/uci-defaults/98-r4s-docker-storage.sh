#!/bin/sh
# Provision the unused NanoPi R4S SD-card space as dedicated Docker storage.
# This script is intentionally conservative: it only acts on the R4S boot MMC,
# only when Docker is installed, and never repartitions a device that has p3.

LOG_TAG="r4s-docker-storage"
ROOT="${R4S_STORAGE_TEST_ROOT:-}"
BOARD_FILE="$ROOT/tmp/sysinfo/board_name"
DISK="${R4S_STORAGE_DISK:-/dev/mmcblk0}"
ROOT_PART="${R4S_STORAGE_ROOT_PART:-/dev/mmcblk0p2}"
DOCKER_PART="${R4S_STORAGE_DOCKER_PART:-/dev/mmcblk0p3}"
PARTITION_CHECK="${R4S_STORAGE_TEST_PARTITION:-$DOCKER_PART}"
DOCKER_MOUNT="/opt/docker"
DOCKER_BRIDGE_CIDR="172.30.0.1/24"

log() {
    logger -t "$LOG_TAG" "$*" 2>/dev/null || true
    printf '%s\n' "$LOG_TAG: $*"
}

board_name=$(cat "$BOARD_FILE" 2>/dev/null || true)
[ "$board_name" = "friendlyarm,nanopi-r4s" ] || exit 0
command -v dockerd >/dev/null 2>&1 || exit 0

# Keep Docker stopped until its dedicated filesystem is mounted. This avoids
# creating an accidental /opt/docker directory inside the 2 GiB root overlay.
/etc/init.d/dockerd stop 2>/dev/null || true

if [ ! -b "$ROOT_PART" ] && [ -z "$R4S_STORAGE_TEST_ROOT" ]; then
    log "Expected root partition $ROOT_PART was not found; refusing to modify storage."
    exit 0
fi

created_partition=0
if [ ! -e "$PARTITION_CHECK" ]; then
    command -v parted >/dev/null 2>&1 || {
        log "parted is unavailable; Docker storage was not created."
        exit 1
    }

    # The sysfs values are 512-byte sectors and identify the first free sector
    # without assuming that the partition starts immediately after the MBR.
    p2_start=$(cat "$ROOT/sys/class/block/mmcblk0p2/start" 2>/dev/null || true)
    p2_size=$(cat "$ROOT/sys/class/block/mmcblk0p2/size" 2>/dev/null || true)
    start=""
    [ -n "$p2_start" ] && [ -n "$p2_size" ] && start=$((p2_start + p2_size))
    [ -n "$start" ] || {
        log "Could not determine the end of $ROOT_PART; refusing to partition."
        exit 1
    }

    log "Creating an ext4 Docker partition from sector $start to the end of $DISK."
    parted -s -a optimal "$DISK" unit s mkpart primary ext4 "${start}s" 100% || exit 1
    partprobe "$DISK" 2>/dev/null || true
    sleep 2
    created_partition=1
fi

if [ ! -e "$PARTITION_CHECK" ]; then
    log "$DOCKER_PART did not appear after partitioning; leaving Docker on the root filesystem."
    exit 1
fi

if ! block info "$DOCKER_PART" 2>/dev/null | grep -q 'TYPE="ext4"'; then
    if [ "$created_partition" -ne 1 ]; then
        log "$DOCKER_PART already exists and is not ext4; refusing to format it."
        exit 1
    fi
    command -v mkfs.ext4 >/dev/null 2>&1 || {
        log "mkfs.ext4 is unavailable; Docker storage was not formatted."
        exit 1
    }
    log "Formatting $DOCKER_PART as ext4."
    mkfs.ext4 -F -L docker "$DOCKER_PART" || exit 1
fi

uuid=$(block info "$DOCKER_PART" 2>/dev/null | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
[ -n "$uuid" ] || {
    log "Could not read the Docker partition UUID; mount configuration was not changed."
    exit 1
}

mkdir -p "$ROOT$DOCKER_MOUNT"
uci -q delete fstab.docker
uci set fstab.docker='mount'
uci set fstab.docker.uuid="$uuid"
uci set fstab.docker.target="$DOCKER_MOUNT"
uci set fstab.docker.fstype='ext4'
uci set fstab.docker.options='rw,noatime'
uci set fstab.docker.enabled='1'
uci commit fstab

mount "$DOCKER_MOUNT" 2>/dev/null || block mount 2>/dev/null || true
if ! awk -v target="$DOCKER_MOUNT" '$2 == target { found=1 } END { exit !found }' /proc/mounts 2>/dev/null \
        && [ -z "$R4S_STORAGE_TEST_ROOT" ]; then
    log "Docker partition is configured but not mounted; dockerd was not redirected."
    exit 1
fi

uci set dockerd.globals='globals'
uci set dockerd.globals.data_root="$DOCKER_MOUNT"
# Keep Docker's default bridge outside the R4S LAN, Guest, and IoT networks.
# Create additional user-defined Docker networks with explicit subnets inside
# the separate 172.30.0.0/16 space.
uci set dockerd.globals.bip="$DOCKER_BRIDGE_CIDR"
uci commit dockerd
/etc/init.d/dockerd enable 2>/dev/null || true
/etc/init.d/dockerd start 2>/dev/null || true
log "Docker data root configured at $DOCKER_MOUNT on $DOCKER_PART."

exit 0
