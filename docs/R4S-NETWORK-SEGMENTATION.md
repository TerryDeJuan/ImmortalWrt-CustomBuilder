# R4S Network Segmentation

The NanoPi R4S has two Ethernet interfaces. This design keeps `eth0` as PPPoE WAN and uses `eth1` as a tagged trunk to a managed switch or VLAN-aware access point.

## Requested networks

| Network | VLAN ID | Subnet | Router address | Policy |
|---|---:|---|---|---|
| LAN | 98 | Existing `10.0.3.0/24` | `10.0.3.1` | Existing trusted LAN |
| Guest | 37 | `192.168.37.0/24` | `192.168.37.1` | DHCP, DNS, NTP, ping only |
| IoT | 12 | `172.31.12.0/24` | `172.31.12.1` | LAN and later-selected remote private subnets only |

Docker's default bridge is pinned to `172.30.0.0/24`, outside the routed
VLANs. The firewall binds the Docker zone to the named `docker` network rather
than treating the entire `172.16.0.0/12` range as Docker; that broad range
includes the IoT subnet. Create additional Docker networks with explicit,
reviewed subnets in the separate `172.30.0.0/16` space.

The old backup confirms the LAN subnet as `10.0.3.0/24` with router address `10.0.3.1`. The previous untagged LAN is intentionally moved to VLAN 98, so the upstream switch/AP trunk must be changed at the same time as the router.

## Firewall policy

### Guest

Guest has `input=REJECT`, `output=ACCEPT`, and `forward=REJECT`. Explicit router-service rules permit only:

- DHCP;
- DNS;
- NTP;
- ICMP echo request (ping).

There is no Guest forwarding to LAN, IoT, WAN, Docker, or WireGuard zones. LuCI, SSH, `ttyd`, OpenClash dashboards, HAProxy, and other router listeners are not exposed to Guest.

### IoT

IoT has `input=REJECT`, `output=ACCEPT`, and `forward=REJECT`. Explicit rules permit:

- DHCP, DNS, NTP, and ping to the router;
- IoT → LAN forwarding;
- later-selected remote private routes through the appropriate WireGuard zone.

There is deliberately no IoT → WAN forwarding and no IoT → Guest forwarding. IoT devices therefore have no ordinary Internet path through the firewall. OpenClash/policy-routing rules must also be reviewed so they do not create a second external path for IoT traffic.

## Implemented files

- `files/etc/uci-defaults/97-r4s-network.sh` applies the VLAN, DHCP, and firewall policy on first boot.
- The same initializer preserves PPPoE mode by reading the build-generated `/etc/config/pppoe-settings`; credentials are never stored in the repository.
- Existing WireGuard interface names `wg0`, `wg6`, `wg16`, and uppercase `WG3` remain in the protected migration configuration; the generic legacy mapper is bypassed on the R4S so it cannot replace the VLAN layout.
- `IOT_REMOTE_PRIVATE_SUBNETS` is reserved for future explicit remote-network policy. It is empty by default.

## Hardware requirement

The R4S does not provide separate physical ports for Guest and IoT. Configure `eth1` as a tagged trunk:

- VLAN 98: trusted LAN;
- VLAN 37: Guest;
- VLAN 12: IoT.

The switch/AP must tag these VLANs consistently. Keep a serial-console or physical recovery route during the first deployment; changing the LAN to a tagged VLAN can otherwise make a perfectly healthy router appear to have vanished.

## Validation checklist

From a trusted LAN host:

1. Confirm LAN address `10.0.3.1` on VLAN 98.
2. Confirm DHCP leases on Guest and IoT.
3. Confirm Guest can resolve DNS, obtain NTP, and ping the router.
4. Confirm Guest cannot reach LuCI, SSH, LAN, IoT, WAN, or WireGuard peers.
5. Confirm IoT can reach permitted LAN services.
6. Confirm IoT cannot reach public IPv4 or IPv6 Internet destinations.
7. Confirm IoT cannot reach Guest.
8. Add remote private subnets one at a time and test only the intended WireGuard route.
9. Test firewall reload and reboot persistence.
10. Keep the old SD card untouched until all checks pass.
