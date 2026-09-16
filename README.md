# ImmortalWrt Custom Builder

A GitHub Actions workflow collection for building customized ImmortalWrt firmware with the official ImmortalWrt ImageBuilder. It supports ImmortalWrt 24.10.x and 25.12.x images for x86-64 (including ISO installers), Rockchip, Allwinner sunxi, Raspberry Pi, ARM virtual machines, development boards, and supported wireless routers.

See the [supported device list](SUPPORT.md) and [package notes](PACKAGES.md) before building.

## Important Notice

> This is an independently maintained third-party project and is not affiliated with the ImmortalWrt project.
>
> Firmware produced here uses the official ImmortalWrt ImageBuilder, but bugs caused by custom packages or configuration are not ImmortalWrt firmware bugs. Do not report project-specific problems to ImmortalWrt maintainers or community groups. Use this project's [Discussions](https://github.com/wukongdaily/ImmortalWrt-ImageBuilder/discussions) instead.

## Features

- Selectable ImmortalWrt and LuCI versions.
- Configurable image size; the default is 1 GB. A size of 1–2 GB is recommended, with later expansion for larger installations.
- Optional Docker and app-store integration where supported.
- Optional third-party packages from the [package store](https://github.com/wukongdaily/store). See the [integration guide](https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/209).
- Configurable management IP for multi-port devices.
- Builds for x86-64, ISO, Rockchip, sunxi, Raspberry Pi, ARM virtual machines, development boards, and wireless routers.

## Build

1. Fork this repository.
2. Open the fork's **Actions** tab.
3. Select the workflow for the required ImmortalWrt version and target device.
4. Choose **Run workflow**, set the available options, and start the build.
5. Download the generated artifact after the workflow completes.

Additional guidance is available in the [project wiki](https://github.com/wukongdaily/AutoBuildImmortalWrt/wiki).

## Network Defaults

- **Single-port devices:** the interface uses DHCP. Find the assigned address in the upstream router before opening the web interface, then configure any downstream-router address from ImmortalWrt itself.
- **Multi-port devices:** `eth0` is WAN and uses DHCP; the other interfaces are LAN, with a default management address of `192.168.100.1`.
- If PPPoE credentials are supplied in the workflow, WAN uses PPPoE instead of DHCP. Restarting the modem before first use is recommended.
- These defaults can be adjusted in `files/etc/uci-defaults/99-custom.sh`.

Changing the workflow's management IP is intended for multi-port devices only. It does not assign a fixed address to a single-port device.

## Packages and identity

The installed-package inventory from an existing router is not stored in this
repository: it is device-specific and can contain sensitive configuration
context. Run `opkg list-installed` on an OpenWrt 24.10 router, or
`apk list --installed` on an OpenWrt 25.12 router. The repository's read-only
collectors save those results as `packages-installed.txt`; use
`tools/router-audit.sh` for an inventory or `tools/router-backup.sh` for an
off-device backup. Review the list and select only top-level applications for
ImageBuilder; do not paste the complete dependency list into a build.

The long commented catalog in `shell/custom-packages.sh` is intentional. It is
not installed merely because it appears there. Uncomment a `CUSTOM_PACKAGES=...`
line to include that package set, or select a package through the workflow's
manual options where one is provided. The build script sources this file and
merges `CUSTOM_PACKAGES` into the ImageBuilder `PACKAGES` argument.

The R4S backup's `packages-installed.txt` contains 312 packages, including the
old 5.4 kernel, kernel modules, shared libraries, base system, and dependency
packages. Those exact versions must not be copied into a newer ImageBuilder:
many are release- or architecture-specific and would either be unavailable or
make the image inconsistent. The recovered block in
`shell/custom-packages.sh` therefore contains the reviewed application-level
subset from that backup; ImageBuilder resolves matching dependencies for the
selected release. The current 24.10 R4S block contains only the application
packages suitable for that opkg-based build. The complete raw inventory
remains in the ignored local backup and is not uploaded to GitHub. The 25.12
apk build uses `shell/apk-custom-packages.sh` separately and does not consume
this legacy opkg list.

For the Rockchip workflows, Docker is a manual `workflow_dispatch` choice named
`include_docker`. Select `yes` to install the Docker runtime and storage
helpers; select `no` to omit them. The default is now `no`, so Docker is
opt-in rather than quietly consuming flash space.

The current default login is **root** with the initial password **changeme**.
Change this password immediately after first boot in **System → Administration**,
or with `passwd` over the trusted LAN. The first-boot script sets the hostname
to `peachwrt` and the firmware description to `PeachWRT`.
The human-readable build name/description is currently set in
`files/etc/uci-defaults/99-custom.sh` as `NEW_DESCRIPTION`; the actual network
hostname is set there through the standard `system.@system[0].hostname` UCI
setting.

## Installation and Safety

- Verify that the selected image matches the exact target device before flashing. Back up the current configuration and data first.
- The x86-64 ISO workflow creates an installer image. Boot it on the target system, run `ddd`, and follow the prompts to select and write the destination disk. **This erases the selected disk; confirm the target carefully.** See [img-installer](https://github.com/wukongdaily/img-installer) for implementation details.
- For initial setup convenience, generated firmware allows inbound traffic on the WAN firewall zone. After setup, change **Network → Firewall → WAN → Input** to **Reject**, then save and apply. See the [security discussion](https://github.com/wukongdaily/AutoBuildImmortalWrt/discussions/341).

## License

See [LICENSE](LICENSE).

# Special Thanks

Thanks to the following projects and authors for their contributions and inspiration.

<div align="left">

<a href="https://github.com/immortalwrt"><img src="https://avatars.githubusercontent.com/immortalwrt?v=4&s=80" width="80" height="80" alt="immortalwrt" /></a>
<a href="https://github.com/Openwrt-Passwall"><img src="https://avatars.githubusercontent.com/Openwrt-Passwall?v=4&s=80" width="80" height="80" alt="Openwrt-Passwall" /></a>
<a href="https://github.com/sirpdboy"><img src="https://avatars.githubusercontent.com/sirpdboy?v=4&s=80" width="80" height="80" alt="sirpdboy" /></a>
<a href="https://github.com/ophub"><img src="https://avatars.githubusercontent.com/ophub?v=4&s=80" width="80" height="80" alt="ophub" /></a>
<a href="https://github.com/linkease"><img src="https://avatars.githubusercontent.com/linkease?v=4&s=80" width="80" height="80" alt="linkease" /></a>

<a href="https://github.com/coolsnowwolf"><img src="https://avatars.githubusercontent.com/coolsnowwolf?v=4&s=80" width="80" height="80" alt="coolsnowwolf" /></a>
<a href="https://github.com/stackia"><img src="https://avatars.githubusercontent.com/stackia?v=4&s=80" width="80" height="80" alt="stackia" /></a>
<a href="https://github.com/kiddin9"><img src="https://avatars.githubusercontent.com/kiddin9?v=4&s=80" width="80" height="80" alt="kiddin9" /></a>
<a href="https://github.com/sbwml"><img src="https://avatars.githubusercontent.com/sbwml?v=4&s=80" width="80" height="80" alt="sbwml" /></a>
<a href="https://github.com/kenzok8"><img src="https://avatars.githubusercontent.com/kenzok8?v=4&s=80" width="80" height="80" alt="kenzok8" /></a>

<a href="https://github.com/timsaya"><img src="https://avatars.githubusercontent.com/timsaya?v=4&s=80" width="80" height="80" alt="timsaya" /></a>
<a href="https://github.com/AdguardTeam"><img src="https://avatars.githubusercontent.com/AdguardTeam?v=4&s=80" width="80" height="80" alt="AdguardTeam" /></a>
<a href="https://github.com/Thaolga"><img src="https://avatars.githubusercontent.com/Thaolga?v=4&s=80" width="80" height="80" alt="Thaolga" /></a>
<a href="https://github.com/eamonxg"><img src="https://avatars.githubusercontent.com/eamonxg?v=4&s=80" width="80" height="80" alt="eamonxg" /></a>
<a href="https://github.com/nikkinikki-org"><img src="https://avatars.githubusercontent.com/nikkinikki-org?v=4&s=80" width="80" height="80" alt="nikkinikki-org" /></a>

<a href="https://github.com/gdy666"><img src="https://avatars.githubusercontent.com/gdy666?v=4&s=80" width="80" height="80" alt="gdy666" /></a>
<a href="https://github.com/lwb1978"><img src="https://avatars.githubusercontent.com/lwb1978?v=4&s=80" width="80" height="80" alt="lwb1978" /></a>
<a href="https://github.com/Tokisaki-Galaxy"><img src="https://avatars.githubusercontent.com/Tokisaki-Galaxy?v=4&s=80" width="80" height="80" alt="Tokisaki-Galaxy" /></a>
<a href="https://github.com/QiuSimons"><img src="https://avatars.githubusercontent.com/QiuSimons?v=4&s=80" width="80" height="80" alt="QiuSimons" /></a>
<a href="https://xz.vumstar.com/"><img src="https://xz.vumstar.com/static/img/logo.png" width="80" height="80" alt="wukongdaily" /></a>

</div>
