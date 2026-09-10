[![GitHub](https://img.shields.io/badge/Releases_available_from_a_China--based_accelerator-FC7C0D?logo=github&logoColor=fff&labelColor=000&style=for-the-badge)](https://wkdaily.cpolar.top/archives/1)
#### This firmware is intended specifically for ARM64 virtual machines.
#### It uses the qcow2 format, which can be expanded freely inside a virtual machine without adding another virtual hard disk.
#### Firmware address: `192.168.100.1`
#### Username: `root`; password: none
#### Default package size: 2 GB

##### When imported into a single-port virtual machine, this firmware uses DHCP by default. Run `ip a` in the virtual-machine terminal to find its IP address, then open the web interface.
##### When imported into a multi-port virtual machine, the first network interface uses DHCP by default and acts as the WAN; the other interfaces are automatically added to br-lan.
##### If downloading from Releases is slow, use the China-based accelerator: https://wkdaily.cpolar.top/archives/1

- Think of this as a general-purpose ARM64 build of OpenWrt. It is distributed in qcow2 format and is suitable for virtual machines on any ARM64 platform.
- Examples of ARM64 virtual-machine environments include:
- A Phicomm N1 running Armbian with PVE installed.
- UTM on newer Apple computers with Apple silicon.
- The official Debian system with PVE preinstalled for FriendlyElec NanoPi R3S and R5S devices.
- A Radxa E20C running Armbian with a manually installed QEMU and native KVM setup.
