#!/bin/sh
# ---------------------------------------------------------------------------
# Stage 1: get a stock BeagleBone Black Debian image booting to USB-MIDI in ~10 s, with NO
# reflash. Idempotent -- safe to re-run. Fully reversible via stage1_revert.sh.
#
#   sudo ./stage1_apply.sh
#
# BEFORE running: read docs/diagnostics.md, run the Stage 0 block, and CONFIRM the masked
# unit names below actually exist in `systemd-analyze blame` on YOUR image. Editing the MASK
# list to match your board is expected -- do not mask what you didn't see.
# ---------------------------------------------------------------------------
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ "$(id -u)" = "0" ] || { echo "run as root (sudo)"; exit 1; }

echo "== [1/6] default target -> multi-user (drop graphical) =="
systemctl set-default multi-user.target

echo "== [2/6] mask network-wait (the biggest single win, ~15-30 s) =="
for u in systemd-networkd-wait-online.service \
         NetworkManager-wait-online.service \
         connman-wait-online.service; do
    systemctl mask "$u" 2>/dev/null && echo "  masked $u" || true
done

echo "== [3/6] mask BeagleBoard bloat (EDIT to match your blame output) =="
# NOTE: generic-board-startup.service is the stock USB-gadget bringup on many images; masking
# it helps free the UDC for g_midi. Confirm exact names first (docs/diagnostics.md).
MASK="cloud9.service cloud9.socket \
      bonescript.service bonescript.socket bonescript-autorun.service \
      nodered.service nodered.socket node-red.service \
      apache2.service \
      avahi-daemon.service avahi-daemon.socket \
      bluetooth.service hciuart.service \
      wpa_supplicant.service \
      generic-board-startup.service"
for u in $MASK; do
    systemctl mask "$u" 2>/dev/null && echo "  masked $u" || true
done

echo "== [4/6] free the UDC so g_midi can bind =="
# The single musb UDC can host only ONE gadget. On modern images U-Boot binds a composite
# gadget via enable_uboot_usb_gadgets=1 in /boot/uEnv.txt. If present, comment it (with a
# backup) so g_midi (loaded in step 5) wins the UDC. Reverted by stage1_revert.sh.
UENV=/boot/uEnv.txt
if [ -f "$UENV" ] && grep -qE '^[[:space:]]*enable_uboot_usb_gadgets=1' "$UENV"; then
    [ -f "$UENV.bak.bbb" ] || cp "$UENV" "$UENV.bak.bbb"
    sed -i 's/^\([[:space:]]*enable_uboot_usb_gadgets=1\)/#bbb# \1/' "$UENV"
    echo "  commented enable_uboot_usb_gadgets in $UENV (backup: $UENV.bak.bbb) -- takes effect next boot"
else
    echo "  no active enable_uboot_usb_gadgets line (or no uEnv.txt) -- nothing to do"
fi

echo "== [5/6] install g_midi gadget config (Option A) =="
install -m 0644 "$REPO/gadget/g_midi.modules-load.conf" /etc/modules-load.d/g_midi.conf
install -m 0644 "$REPO/gadget/g_midi.modprobe.conf"     /etc/modprobe.d/g_midi.conf
# Load now so the current boot already has it (next boot loads it early automatically). If the
# UDC is still held by the stock gadget this boot, it will bind cleanly after the reboot below.
modprobe g_midi 2>/dev/null || echo "  (g_midi will bind on next boot; UDC busy now)"

echo "== [6/6] install sensor script + service =="
install -d /opt/fsr-midi
install -m 0755 "$REPO/src/fsr_midi.py" /opt/fsr-midi/fsr_midi.py
install -m 0644 "$REPO/systemd/fsr-midi.service" /etc/systemd/system/fsr-midi.service
# channel/note override file -- install only if absent so we never clobber your edits
[ -f /etc/default/fsr-midi ] || install -m 0644 "$REPO/systemd/fsr-midi.default" /etc/default/fsr-midi
systemctl daemon-reload
systemctl enable fsr-midi.service

echo
echo "Done. Reboot to measure:  sudo reboot"
echo "After boot:  systemd-analyze ; amidi -l ; journalctl -u fsr-midi -b"
