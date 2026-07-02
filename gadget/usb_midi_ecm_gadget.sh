#!/bin/sh
# ---------------------------------------------------------------------------
# DEV gadget: MIDI + USB-Ethernet (ECM) on the ONE mini-USB port at the same time.
# Lets you keep single-cable development -- the host sees a MIDI device AND a usb network
# it can SSH over (VS Code Remote-SSH), so you never lose your way into the board when
# g_midi-only would otherwise take the whole UDC.
#
#   *** DEV ONLY. *** The fast/production path is g_midi alone (gadget/g_midi.*). This
#   composite enumerates a hair slower and keeps networking up -- fine for the bench, not
#   for the ~10 s boot. Use two SD cards: a dev card (this) and a perf card (g_midi).
#
# Install to: /usr/local/sbin/usb_midi_ecm_gadget.sh  (run by usb-midi-ecm-gadget.service)
# Requires libcomposite. Do NOT run alongside g_midi / the stock gadget -- one UDC only.
# Board gets 192.168.7.2; set the host's usb-net iface to 192.168.7.1/24 then:
#   ssh debian@192.168.7.2
# ---------------------------------------------------------------------------
set -e

G=/sys/kernel/config/usb_gadget/bbbdev
BOARD_IP=192.168.7.2
# Locally-administered MACs (2nd hex nibble = 2). Stable so the host keeps one iface name.
MAC_DEV=02:1d:6b:00:00:02      # board side
MAC_HOST=02:1d:6b:00:00:01     # host side

modprobe libcomposite
[ -d "$G" ] && exit 0          # idempotent

mkdir -p "$G"
echo 0x1d6b > "$G/idVendor"    # Linux Foundation
echo 0x0104 > "$G/idProduct"   # multifunction composite
echo 0x0100 > "$G/bcdDevice"
echo 0x0200 > "$G/bcdUSB"
mkdir -p "$G/strings/0x409"
echo "0002"                   > "$G/strings/0x409/serialnumber"
echo "drums55"                > "$G/strings/0x409/manufacturer"
echo "BBB FSR Trigger (dev)"  > "$G/strings/0x409/product"

# --- MIDI function (same as production) ---
mkdir -p "$G/functions/midi.usb0"
echo 32 > "$G/functions/midi.usb0/qlen"
echo 1  > "$G/functions/midi.usb0/in_ports"
echo 1  > "$G/functions/midi.usb0/out_ports"

# --- ECM (USB-Ethernet) function for SSH-over-USB ---
mkdir -p "$G/functions/ecm.usb0"
echo "$MAC_DEV"  > "$G/functions/ecm.usb0/dev_addr"
echo "$MAC_HOST" > "$G/functions/ecm.usb0/host_addr"

mkdir -p "$G/configs/c.1/strings/0x409"
echo "MIDI+ECM" > "$G/configs/c.1/strings/0x409/configuration"
echo 250        > "$G/configs/c.1/MaxPower"
ln -s "$G/functions/midi.usb0" "$G/configs/c.1/"
ln -s "$G/functions/ecm.usb0"  "$G/configs/c.1/"

UDC=$(ls /sys/class/udc | head -n1)
echo "$UDC" > "$G/UDC"

# Bring up the board-side usb network interface (usb0) with a static IP.
sleep 1
IFACE=$(ls /sys/class/net | grep -E '^usb0$' | head -n1 || true)
[ -n "$IFACE" ] && ip addr add "$BOARD_IP/24" dev "$IFACE" 2>/dev/null || true
[ -n "$IFACE" ] && ip link set "$IFACE" up 2>/dev/null || true
echo "dev gadget up: MIDI + ssh debian@$BOARD_IP (set host usb-net to 192.168.7.1/24)"
