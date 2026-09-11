# OpenClash Migration

OpenClash is not just a LuCI package. It manages a version-specific Mihomo/Clash core, generated configuration, proxy and rule providers, GeoIP/GeoSite databases, firewall integration, DNS interception, and scheduled update jobs. This workflow separates portable state from executable cores so an upgrade does not carry an old binary into a new kernel/userspace.

## Upstream facts used here

- The official OpenClash repository describes the project as a LuCI client for Mihomo/Clash and publishes package releases separately from the source tree: <https://github.com/vernesong/OpenClash>.
- The package installs a persistent `/etc/openclash/` tree and registers it with the sysupgrade keep list through its `luci-openclash` installation script.
- The upstream init script uses `/etc/openclash/clash` as the core path, `/etc/openclash` as the configuration root, and schedules GeoIP, GeoSite, GeoASN, and related updates from UCI settings.
- The OpenClash package declares runtime dependencies including `bash`, `curl`, `ca-bundle`, `ip-full`, `ruby`, `ruby-yaml`, `unzip`, TUN support, and firewall-specific packages. Dependency names differ between older OPKG releases and newer APK releases; let the target package manager resolve them.

## 1. Export on the old router

Use the repository tool while the old OpenClash installation is still working:

```sh
scp tools/openclash-backup.sh root@ROUTER_IP:/tmp/
ssh root@ROUTER_IP \
  'chmod 700 /tmp/openclash-backup.sh && /tmp/openclash-backup.sh /tmp/openclash-migration'
scp -r root@ROUTER_IP:/tmp/openclash-migration ./local-backups/
```

The export contains, when present:

- `/etc/config/openclash` UCI configuration;
- saved YAML configurations under `/etc/openclash/config/`;
- proxy and rule providers;
- custom domain, IP, DNS, firewall, hosts, fake-IP, and sniffer rules;
- overwrite files and game rules;
- `GeoIP.dat` and `GeoSite.dat`;
- `Country.mmdb` and `ASN.mmdb`;
- selected OpenClash history and Sub-Store state.

The export deliberately excludes `/etc/openclash/core/` and core executable paths. The old core is tied to the old build and must not be promoted into the new image merely because it happens to be nearby.

## 2. Record the old core and database inventory

Run these read-only commands on the old router and save the output beside the backup:

```sh
uci -q show openclash > /tmp/openclash-uci.txt
ls -lah /etc/openclash/core /etc/openclash/clash 2>/dev/null || true
file /etc/openclash/core/* /etc/openclash/clash 2>/dev/null || true
sha256sum /etc/openclash/GeoIP.dat /etc/openclash/GeoSite.dat \
  /etc/openclash/Country.mmdb /etc/openclash/ASN.mmdb 2>/dev/null || true
```

Do not paste the UCI dump into chat: it may contain subscription URLs, credentials, proxy addresses, or dashboard secrets.

## 3. Build the new image

For the NanoPi R4S workflow:

1. Install `luci-app-openclash` from the target ImmortalWrt 25.12 repository or a release compatible with that release.
2. Do not add the old OpenClash core to `files/`.
3. Do not hard-code the old `GeoIP.dat` or `GeoSite.dat` into the firmware image.
4. Install only the core selected for the target OpenClash release and R4S architecture.
5. Keep the OpenClash configuration and large provider databases in the migration archive, not GitHub Actions inputs.

The current builder already downloads a core when OpenClash is selected. Before the production build, replace the floating “latest” downloads with a pinned, reviewed release or let OpenClash download its compatible core after first boot. Floating downloads are convenient but poor forensic evidence and occasionally acquire a sense of adventure.

## 4. Restore on the new router

After flashing and confirming LAN/SSH access:

1. Install and start the target OpenClash package once.
2. Install or download a target-compatible Mihomo/Clash core.
3. Confirm `/etc/openclash/core/` exists and the core executes on `aarch64`.
4. Stop OpenClash before importing state.
5. Copy the portable archive to the router.
6. Run the restore helper:

```sh
scp ./local-backups/openclash-migration/openclash-portable-state.tar.gz root@NEW_ROUTER_IP:/tmp/
scp tools/openclash-restore.sh root@NEW_ROUTER_IP:/tmp/
ssh root@NEW_ROUTER_IP \
  'chmod 700 /tmp/openclash-restore.sh && /tmp/openclash-restore.sh /tmp/openclash-portable-state.tar.gz'
```

The helper creates a rollback archive of the current `/etc/config/openclash` and `/etc/openclash` tree, rejects archives containing core executable paths, imports the portable state, commits UCI, and attempts an OpenClash restart.

## 5. Validate configuration before enabling traffic interception

Check the following in LuCI and from SSH:

```sh
/etc/init.d/openclash status 2>/dev/null || true
logread -e openclash | tail -n 100
ls -lh /etc/openclash/core /etc/openclash/GeoIP.dat /etc/openclash/GeoSite.dat
uci show openclash | grep -E '^(openclash\.(config|config_.*|authentication))' \
  | sed -E 's/(password|secret|token|url)=.*/\1=<REDACTED>/'
```

Then verify in this order:

1. Core starts without dynamic-loader or architecture errors.
2. A saved configuration parses successfully.
3. Proxy providers load.
4. GeoIP and GeoSite databases are readable.
5. DNS mode works without a loop or duplicate interception.
6. LAN traffic routes correctly.
7. IPv4 and IPv6 behavior is intentional.
8. Firewall reload and router reboot preserve the result.
9. Only then enable automatic GeoIP/GeoSite updates and OpenClash autostart.

## 6. GeoIP and GeoSite policy

Keep the old databases in the migration archive for rollback and comparison, but refresh them on the new system after the target core is working. Geo databases are data files, not platform binaries; they are portable in principle, but their freshness and format must match the selected core and OpenClash release.

Recommended sequence:

1. Restore the old `GeoIP.dat` and `GeoSite.dat` only if the new installation needs an immediate offline baseline.
2. Confirm the core can read them.
3. Use OpenClash's own update mechanism to download current GeoIP/GeoSite/GeoASN data.
4. Record the new files' timestamps and SHA-256 hashes.
5. Remove or archive obsolete copies only after successful traffic tests.

Do not put these databases, subscription files, provider caches, or generated rule providers in Git. They are large, frequently changing, and may expose personal routing choices or subscription information.

## 7. Rollback

If the new OpenClash setup fails:

- stop OpenClash;
- restore the helper-created `/tmp/openclash-before-restore-*.tar.gz` archive, or re-run the old router from its untouched SD card;
- restore the old core only on the old firmware;
- retain the new router's logs for diagnosis.

Do not fix a new-core failure by copying the old executable into the new image. Reinstall a compatible core instead.
