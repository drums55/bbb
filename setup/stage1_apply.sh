#!/bin/sh
# ----------------------------------------------------------------------------
# Stage 1: get a stock BeagleBone Black Debian image booting to USB-MIDI in ~10 s,
# with NO reflash. Idempotent -- safe to re-run. Reversible via stage1_revert.sh.
#
#   sudo ./stage1_apply.sh
#
# BEFORE running: read docs/diagnostics.md, run the Stage 0 block, and CONFIRM the
# masked unit names below actually exist in `systemd-analyze blame` on your image.
# Editing the MASK list to match your board is expected.
# ----------------------------------------------------------------------------
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$(id -u)" != "0" ]; then echo "run as root (sudo)"; exit 1; fi

echo "== [1/5] default target -> multi-user (no graphical) =="
systemctl set-default multi-user.target

echo "== [2/5] mask network-wait (the big ~15-30s culprit) =="
for u in systemd-networkd-wait-online.service \
         NetworkManager-wait-online.service \
         connman-wait-online.service; do
    systemctl mask "$u" 2>/dev/null || true
done

echo "== [3/5] mask BeagleBoard bloat (edit this list to match your blame output) =="
# NOTE: masking the stock USB gadget bringup (generic-board-startup / bb-usb-gadgets)
# frees the UDC for g_midi. Confirm the exact name on your image first.
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

echo "== [4/5] install g_midi gadget (Option A) =="
install -m 0644 "$REPO/gadget/g_midi.modules-load.conf" /etc/modules-load.d/g_midi.conf
install -m 0644 "$REPO/gadget/g_midi.modprobe.conf"     /etc/modprobe.d/g_midi.conf
# load now so this boot already has it (next boot loads it early automatically)
modprobe g_midi 2>/dev/null || echo "  (g_midi will load on next boot; UDC may be busy now)"

echo "== [5/5] install sensor script + service =="
install -d /opt/fsr-midi
install -m 0755 "$REPO/src/fsr_midi.py" /opt/fsr-midi/fsr_midi.py
install -m 0644 "$REPO/systemd/fsr-midi.service" /etc/systemd/system/fsr-midi.service
systemctl daemon-reload
systemctl enable fsr-midi.service

echo
echo "Done. Reboot to measure:  sudo reboot"
echo "After boot:  systemd-analyze ; amidi -l ; journalctl -u fsr-midi -b"
