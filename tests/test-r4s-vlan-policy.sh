#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/files/etc/uci-defaults/97-r4s-network.sh"
LEGACY="$ROOT/files/etc/uci-defaults/99-custom.sh"
GUIDE="$ROOT/docs/R4S-NETWORK-SEGMENTATION.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

for file in "$SCRIPT" "$LEGACY" "$GUIDE"; do
    [ -f "$file" ] || fail "missing $file"
done
sh -n "$SCRIPT" || fail "network initializer syntax"

for token in "br-lan.98" "192.168.37.1" "vid='37'" "172.31.12.1" \
    "name='guest'" "name='iot'" "src='guest'" "src='iot'" "dest='lan'" \
    "IOT_REMOTE_PRIVATE_SUBNETS"; do
    grep -q "$token" "$SCRIPT" || fail "missing network policy token: $token"
done
! grep -q "src=guest.*dest=lan" "$SCRIPT" || fail "Guest-to-LAN forwarding must be absent"
! grep -q "src=iot.*dest=wan" "$SCRIPT" || fail "IoT-to-WAN forwarding must be absent"

for iface in wg0 wg6 wg16 WG3; do
    grep -q "$iface" "$GUIDE" || fail "$iface preservation documentation missing"
done
grep -q "IOT_REMOTE_PRIVATE_SUBNETS" "$SCRIPT" || fail "future IoT remote-subnet hook missing"
grep -q "friendlyarm,nanopi-r4s" "$LEGACY" || fail "legacy mapper does not protect the R4S VLAN layout"
grep -q "pppoe-settings" "$SCRIPT" || fail "PPPoE preservation hook missing"

echo "PASS: R4S VLAN and firewall policy contract"
