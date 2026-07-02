#!/bin/sh
# ---------------------------------------------------------------------------
# DEV gadget for a WINDOWS laptop: MIDI + USB-Ethernet (RNDIS) on the ONE mini-USB port.
# One cable gives the host a MIDI device AND a usb network to SSH / VS Code Remote-SSH over,
# so you never lose your way in when g_midi-only would take the whole UDC.
#
#   *** DEV ONLY. *** Production/perf = g_midi alone (gadget/g_midi.*). Keep two SD cards:
#   a dev card (this) and a perf card (g_midi). See docs/dev_workflow.md.
#
# Windows-specific: RNDIS (not ECM -- macOS/Linux use gadget/usb_midi_ecm_gadget.sh) plus
# Microsoft OS descriptors so Win10/11 auto-binds the "USB RNDIS" driver with no INF file.
#
# Install to: /usr/local/sbin/usb_dev_gadget.sh  (run by usb-dev-gadget.service)
# Board = 192.168.7.2; a tiny dnsmasq (if installed) hands the host 192.168.7.1 automatically.
# If dnsmasq isn't there, set the Windows adapter to static 192.168.7.1/24 (one-time).
# ---------------------------------------------------------------------------
set -e

G=/sys/kernel/config/usb_gadget/bbbdev
BOARD_IP=192.168.7.2
HOST_IP=192.168.7.1
MAC_DEV=02:1d:6b:00:00:02       # board side  (locally-administered)
MAC_HOST=02:1d:6b:00:00:01      # host side

modprobe libcomposite
[ -d "$G" ] && exit 0           # idempotent

mkdir -p "$G"
echo 0x1d6b > "$G/idVendor"     # Linux Foundation
echo 0x0104 > "$G/idProduct"    # multifunction composite
echo 0x0100 > "$G/bcdDevice"
echo 0x0200 > "$G/bcdUSB"
echo 0xEF   > "$G/bDeviceClass" # Misc / IAD -- needed for a composite gadget on Windows
echo 0x02   > "$G/bDeviceSubClass"
echo 0x01   > "$G/bDeviceProtocol"
mkdir -p "$G/strings/0x409"
echo "0002"                    > "$G/strings/0x409/serialnumber"
echo "drums55"                 > "$G/strings/0x409/manufacturer"
echo "BBB FSR Trigger (dev)"   > "$G/strings/0x409/product"

# --- Microsoft OS descriptors: makes Windows auto-load the RNDIS driver ---
echo 1       > "$G/os_desc/use"
echo 0xcd    > "$G/os_desc/b_vendor_code"
echo MSFT100 > "$G/os_desc/qw_sign"

# --- RNDIS (USB-Ethernet for Windows) ---
mkdir -p "$G/functions/rndis.usb0"
echo "$MAC_DEV"  > "$G/functions/rndis.usb0/dev_addr"
echo "$MAC_HOST" > "$G/functions/rndis.usb0/host_addr"
echo RNDIS   > "$G/functions/rndis.usb0/os_desc/interface.rndis/compatible_id"
echo 5162001 > "$G/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"

# --- MIDI (same function as production) ---
mkdir -p "$G/functions/midi.usb0"
echo 32 > "$G/functions/midi.usb0/qlen"
echo 1  > "$G/functions/midi.usb0/in_ports"
echo 1  > "$G/functions/midi.usb0/out_ports"

mkdir -p "$G/configs/c.1/strings/0x409"
echo "RNDIS+MIDI" > "$G/configs/c.1/strings/0x409/configuration"
echo 250          > "$G/configs/c.1/MaxPower"
# RNDIS first so Windows enumerates the network cleanly, then MIDI.
ln -s "$G/functions/rndis.usb0" "$G/configs/c.1/"
ln -s "$G/functions/midi.usb0"  "$G/configs/c.1/"
ln -s "$G/configs/c.1" "$G/os_desc"          # attach the MS OS descriptor to this config

UDC=$(ls /sys/class/udc | head -n1)
echo "$UDC" > "$G/UDC"

# Board-side network + optional DHCP so Windows just gets an IP on plug-in.
sleep 1
IFACE=$(ls /sys/class/net | grep -E '^usb0$' | head -n1 || true)
if [ -n "$IFACE" ]; then
    ip addr add "$BOARD_IP/24" dev "$IFACE" 2>/dev/null || true
    ip link set "$IFACE" up 2>/dev/null || true
    if command -v dnsmasq >/dev/null 2>&1; then
        dnsmasq --interface="$IFACE" --bind-interfaces --except-interface=lo \
            --dhcp-range="$HOST_IP,$HOST_IP,255.255.255.0,1h" \
            --dhcp-option=3 --dhcp-option=6 2>/dev/null || true
        echo "dev gadget up: MIDI + RNDIS; dnsmasq hands the host $HOST_IP -> ssh debian@$BOARD_IP"
    else
        echo "dev gadget up: MIDI + RNDIS. No dnsmasq -> set Windows adapter to $HOST_IP/24, then ssh debian@$BOARD_IP"
    fi
fi
