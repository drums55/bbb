#!/bin/sh
# ---------------------------------------------------------------------------
# Option B (alternative to the g_midi module): build a MIDI-only USB gadget via configfs.
# Use this ONLY if you need a custom VID/PID or strings the g_midi module options can't
# express. Otherwise prefer Option A (gadget/g_midi.modules-load.conf) -- it is simpler and
# loads earlier.
#
# Install to: /usr/local/sbin/usb_f_midi_gadget.sh  (run by gadget/usb-midi-gadget.service)
# Requires: libcomposite. Do NOT run this alongside g_midi or the stock composite gadget --
# only one gadget may bind the single musb UDC.
# ---------------------------------------------------------------------------
set -e

G=/sys/kernel/config/usb_gadget/bbbmidi
VID=0x1d6b            # Linux Foundation (safe for a hobby device; change if you own a VID)
PID=0x0104
MANUF="drums55"
PROD="BBB FSR Trigger"
SERIAL="0001"

modprobe libcomposite

# Idempotent: if it already exists, assume it's set up and bound.
[ -d "$G" ] && exit 0

mkdir -p "$G"
echo "$VID"  > "$G/idVendor"
echo "$PID"  > "$G/idProduct"
echo 0x0100  > "$G/bcdDevice"
echo 0x0200  > "$G/bcdUSB"

mkdir -p "$G/strings/0x409"
echo "$SERIAL" > "$G/strings/0x409/serialnumber"
echo "$MANUF"  > "$G/strings/0x409/manufacturer"
echo "$PROD"   > "$G/strings/0x409/product"

# One MIDI function (1 in + 1 out port). qlen tunes the packet queue.
mkdir -p "$G/functions/midi.usb0"
echo 32 > "$G/functions/midi.usb0/qlen"
echo 1  > "$G/functions/midi.usb0/in_ports"
echo 1  > "$G/functions/midi.usb0/out_ports"

mkdir -p "$G/configs/c.1/strings/0x409"
echo "MIDI" > "$G/configs/c.1/strings/0x409/configuration"
echo 120    > "$G/configs/c.1/MaxPower"
ln -s "$G/functions/midi.usb0" "$G/configs/c.1/"

# Bind to the first available USB Device Controller.
UDC=$(ls /sys/class/udc | head -n1)
echo "$UDC" > "$G/UDC"
