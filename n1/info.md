## ImmortalWrt for Phicomm N1
#### LuCI version: 24.10.2. The firmware uses btrfs rather than the traditional ext4 or squashfs formats and supports snapshots.
#### Web interface address: `None; must be looked up`. See below for details.
#### Username: `root`; password: password
#### Docker included: based on the user's selection
#### Default package size: 1 GB
#### Kernel version: based on the user's selection
#### Amlogic Toolbox: ✅ Included for installation to eMMC. Consider doing this only after the system is stable; writing to eMMC is optional, and using a USB drive offers more flexibility.
#### rootfs.tar.gz is built with the ImmortalWrt ImageBuilder.
#### The img file is packaged with `onhub/amlogic-s9xxx-openwrt` or `flippy-openwrt-actions`.
#### Default base-image location: https://github.com/wukongdaily/AutoBuildImmortalWrt/releases/tag/rootfs


### The Phicomm N1 is a single-port device. Connect it to your router with an Ethernet cable. It obtains an IP address automatically after booting.<br> Find its LAN IP address in the DHCP client list of the upstream router.
### To set a different IP address or configure it as a bypass router later, use the web interface.<br> The default setup simply ensures that it has network access, like an ordinary computer or NAS.
### Read the instructions carefully before flashing. Testing with a USB drive is recommended and carries no flashing risk. Do not write to eMMC at the outset.
## Avoid using the Releases from this project directly. Fork the project and build the firmware yourself.<br> The Releases in this project are only for the author's testing and are deleted periodically.
##### If downloading from Releases is slow, use the China-based accelerator.
[![GitHub](https://img.shields.io/badge/Releases_available_from_a_China--based_accelerator-FC7C0D?logo=github&logoColor=fff&labelColor=000&style=for-the-badge)](https://wkdaily.cpolar.top/archives/1)
