# NanoPi R4S Audit, Backup, and Migration

This workflow gathers the facts first, keeps secrets out of Git, and treats a new major release as a controlled migration rather than an opportunity to restore several years of sediment wholesale.

## 1. Identify the SD card

SSH to the router and run:

```sh
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
block info
cat /proc/partitions
```

The R4S normally boots from an MMC device such as `/dev/mmcblk0`. Its `SIZE` is the usable card capacity. If `lsblk` is unavailable, calculate it from sysfs:

```sh
DEV=mmcblk0
sectors="$(cat /sys/class/block/$DEV/size)"
logical="$(cat /sys/class/block/$DEV/queue/logical_block_size)"
bytes=$((sectors * logical))
echo "$DEV: $bytes bytes"
```

Do not assume `/dev/mmcblk0` is the card until `mount`, `block info`, and the root mount confirm it. SD cards are sold in decimal units, so a nominal 32 GB card may appear near 29.8 GiB.

## 2. Collect the full inspection bundle

Copy the read-only audit script to the router, run it, then copy the result back:

```sh
mkdir -p local-backups
scp tools/router-audit.sh root@ROUTER_IP:/tmp/
ssh root@ROUTER_IP 'chmod 700 /tmp/router-audit.sh && /tmp/router-audit.sh /tmp/r4s-audit'
scp -r root@ROUTER_IP:/tmp/r4s-audit ./local-backups/
```

Review the bundle before sharing it. It can contain public IP addresses, MAC addresses, serial numbers, hostnames, routes, and package names. Do not commit the result.

If copying the script is inconvenient, these are the core manual commands:

```sh
ubus call system board
cat /etc/openwrt_release
uname -a
cat /tmp/sysinfo/model; cat /tmp/sysinfo/board_name
cat /proc/cpuinfo
cat /proc/meminfo
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL
block info
cat /proc/partitions
cat /proc/mtd 2>/dev/null
mount
df -h
du -sh /overlay/upper 2>/dev/null
ip -details link show
ip address show
ip route show table all
bridge link show 2>/dev/null
bridge vlan show 2>/dev/null
uci export network
uci export firewall
uci export dhcp
uci export system
uci export dropbear
fw4 print 2>/dev/null || nft list ruleset
for f in /etc/rc.d/S*; do [ -e "$f" ] && basename "$f"; done
ps w
ss -lntup 2>/dev/null || netstat -lntup
cat /proc/modules
dmesg | sed -n '/mmc\|sdhci\|I\/O error\|EXT4-fs\|F2FS-fs/p'
opkg list-installed 2>/dev/null || apk list --installed
opkg list-changed-conffiles 2>/dev/null || true
```

The audit script intentionally captures raw UCI configuration only through the native sysupgrade backup, not as ordinary text. PPPoE passwords, Wi-Fi keys, VPN credentials, private keys, and tokens deserve rather less publicity than a README.

## 3. Back up before changing anything

Run the backup script and copy the resulting directory to two separate systems:

```sh
mkdir -p local-backups
scp tools/router-backup.sh root@ROUTER_IP:/tmp/
ssh root@ROUTER_IP 'chmod 700 /tmp/router-backup.sh && /tmp/router-backup.sh /tmp/r4s-backup'
scp -r root@ROUTER_IP:/tmp/r4s-backup ./local-backups/
```

Then create a complete raw SD-card image while the router is powered down:

1. Shut down cleanly: `ssh root@ROUTER_IP 'poweroff'`.
2. Remove the SD card and attach it to another Linux machine.
3. Confirm the correct source device with `lsblk`.
4. Unmount its partitions.
5. As your own administrator account, image the entire card to storage with enough free space. One suitable command is:

```sh
sudo dd if=/dev/SD_DEVICE of=nanopi-r4s-before-upgrade.img bs=4M status=progress conv=fsync
sha256sum nanopi-r4s-before-upgrade.img > nanopi-r4s-before-upgrade.img.sha256
```

Replace `/dev/SD_DEVICE` only after verifying it. Reversing `if` and `of` is an admirably efficient way to erase the wrong disk. The raw image is the strongest rollback because it includes the partition table and boot data; the sysupgrade archive is better for inspecting and selectively migrating settings.

## 4. Convert the inventory into image requirements

Create three reviewed lists outside the router backup:

- `required-packages.txt`: services and LuCI applications that must be built in.
- `retired-packages.txt`: obsolete, replaced, or intentionally removed packages.
- `post-install-packages.txt`: packages that should remain separately updateable.

For each enabled service, record:

- purpose and owner;
- package name and repository;
- listening ports and firewall zones;
- UCI files under `/etc/config`;
- non-UCI data, keys, certificates, databases, and scripts;
- startup dependencies;
- whether its current configuration is compatible with the target release.

Do not blindly copy every installed package into ImageBuilder. Base packages, dependencies, kernel modules, and old ABI-specific packages must come from the target release. Prefer selecting top-level applications; ImageBuilder resolves their dependencies.

## 5. Build the R4S image

Use the Rockchip 25.12 workflow with:

- profile: `friendlyarm_nanopi-r4s`;
- an explicit ImmortalWrt release;
- a 2 GiB root filesystem;
- Docker enabled so first boot creates an ext4 third partition from the unused
  SD-card space, mounts it at `/opt/docker`, and assigns it as Docker's data root;
- only reviewed packages;
- PPPoE credentials left out of GitHub inputs and repository files.

Repository files that drive this path include:

- `.github/workflows/build-rockchip-25.12.x.yml`;
- `rockchip/build25.sh`;
- `shell/apk-custom-packages.sh`;
- `files/etc/uci-defaults/98-r4s-docker-storage.sh`;
- `files/etc/uci-defaults/99-custom.sh`.

The Docker partition initializer is R4S-specific and refuses to act when the
expected board, boot disk, or root partition is absent. Existing `mmcblk0p3`
content is never reformatted. Test the image on a spare SD card first: creating
the partition is intentionally a one-time, destructive operation on previously
unused space.

The current first-boot script temporarily accepts inbound WAN traffic. Remove or gate that behavior before production deployment unless it is strictly required for an isolated first boot.

## 6. Test before touching the production card

Prefer a spare SD card. Verify:

1. Image checksum and exact `friendlyarm_nanopi-r4s` filename.
2. Boot and serial/Ethernet recovery access.
3. Correct WAN/LAN interface mapping.
4. DHCP, DNS, routing, IPv6, and firewall default-deny behavior.
5. LuCI and SSH access from LAN only.
6. Every required service, one at a time.
7. Reboot persistence and storage expansion behavior.
8. No unexplained kernel, MMC, filesystem, or service errors.

## 7. Migrate settings selectively

For a major-version change, start from new defaults. Reinstall packages first, then compare old and new configuration schemas. Restore in layers:

1. hostname, timezone, users, and SSH keys;
2. LAN and management access;
3. WAN/PPPoE during a planned outage;
4. DHCP, DNS, VLANs, and static leases;
5. firewall rules and port forwards;
6. VPN/proxy services and their protected credentials;
7. monitoring, scheduled tasks, custom scripts, and application data.

After each layer, validate connectivity and keep a console/recovery path. Examine `*-opkg`, `*-apknew`, or equivalent replacement files rather than deleting them reflexively.

## 8. Rollback gate

Do not retire the old card until the new image has passed the full checklist. A clean rollback is simply powering down and reinstalling the untouched old SD card. Keep the raw image, checksum, sysupgrade archives, audit bundle, and final image manifest together in offline storage.
