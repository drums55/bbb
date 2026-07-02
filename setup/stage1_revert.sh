#!/bin/sh
# Undo stage1_apply.sh: unmask everything and remove our units/gadget. Idempotent.
#   sudo ./stage1_revert.sh
set -e
if [ "$(id -u)" != "0" ]; then echo "run as root (sudo)"; exit 1; fi

echo "== unmask everything we masked =="
for u in systemd-networkd-wait-online.service NetworkManager-wait-online.service \
         connman-wait-online.service \
         cloud9.service cloud9.socket \
         bonescript.service bonescript.socket bonescript-autorun.service \
         nodered.service nodered.socket node-red.service \
         apache2.service avahi-daemon.service avahi-daemon.socket \
         bluetooth.service hciuart.service wpa_supplicant.service \
         generic-board-startup.service; do
    systemctl unmask "$u" 2>/dev/null || true
done

echo "== remove sensor service + gadget config =="
systemctl disable fsr-midi.service 2>/dev/null || true
rm -f /etc/systemd/system/fsr-midi.service
rm -f /etc/modules-load.d/g_midi.conf /etc/modprobe.d/g_midi.conf
systemctl daemon-reload

echo "== restore graphical/default target if you want it (left as-is) =="
echo "  (run: sudo systemctl set-default graphical.target   if this board had a desktop)"
echo "Done. Reboot to restore stock behaviour: sudo reboot"
