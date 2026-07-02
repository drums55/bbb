#!/bin/sh
# Undo stage1_apply.sh: unmask everything, remove our units/gadget config, restore uEnv.txt.
# Idempotent.
#   sudo ./stage1_revert.sh
set -e
[ "$(id -u)" = "0" ] || { echo "run as root (sudo)"; exit 1; }

echo "== unmask everything we may have masked =="
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

echo "== restore /boot/uEnv.txt (re-enable stock U-Boot gadget) =="
UENV=/boot/uEnv.txt
if [ -f "$UENV.bak.bbb" ]; then
    cp "$UENV.bak.bbb" "$UENV" && echo "  restored from $UENV.bak.bbb"
elif [ -f "$UENV" ]; then
    sed -i 's/^#bbb# //' "$UENV" && echo "  uncommented our #bbb# lines in $UENV"
fi

echo "== remove sensor service + gadget config =="
systemctl disable fsr-midi.service 2>/dev/null || true
rm -f /etc/systemd/system/fsr-midi.service
rm -f /etc/modules-load.d/g_midi.conf /etc/modprobe.d/g_midi.conf
systemctl daemon-reload

echo
echo "Left as-is: default target (multi-user). To restore a desktop:"
echo "  sudo systemctl set-default graphical.target"
echo "Reboot to restore stock behaviour: sudo reboot"
