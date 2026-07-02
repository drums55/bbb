# Stage 0 -- Diagnostics

Run this FIRST on the BBB (over SSH) and keep the output. It tells us the real service
and gadget names on *your* image so we mask the right things (they differ between the
BeagleBoard.org Debian variants).

```sh
{ echo "== ID =="; cat /etc/dogtag 2>/dev/null; uname -a; \
  echo "== BOOT =="; systemd-analyze; systemd-analyze blame 2>/dev/null | head -25; \
  systemd-analyze critical-chain 2>/dev/null | head -30; \
  echo "== TARGET =="; systemctl get-default; \
  echo "== ENABLED =="; systemctl list-unit-files --state=enabled --type=service; \
  echo "== NET-WAIT =="; systemctl is-enabled systemd-networkd-wait-online.service \
    NetworkManager-wait-online.service connman-wait-online.service 2>&1; \
  echo "== GADGET =="; lsmod | grep -iE "midi|gadget|libcomposite|g_"; \
  ls /sys/kernel/config/usb_gadget/ 2>/dev/null; cat /etc/modules-load.d/* 2>/dev/null; \
  ls /opt/scripts/boot/ 2>/dev/null; cat /boot/uEnv.txt 2>/dev/null | grep -viE '^#|^$'; \
  echo "== MIDI =="; amidi -l 2>/dev/null; aplaymidi -l 2>/dev/null; \
  echo "== IIO/ADC =="; ls /sys/bus/iio/devices/ 2>/dev/null; \
  head -1 /sys/bus/iio/devices/iio:device0/in_voltage*_raw 2>/dev/null; \
  echo "== START =="; grep -rilE "midi|sensor|note" /etc/systemd/system/ /etc/rc.local 2>/dev/null; \
  crontab -l 2>/dev/null; ls -lt /home/debian/*.py /root/*.py 2>/dev/null | head; } 2>&1
```

## How to read it

| Section    | What to look for | Action |
|------------|------------------|--------|
| `BOOT`     | `systemd-analyze` total; top of `blame`/`critical-chain` | The named units eating seconds are the mask targets in `setup/stage1_apply.sh`. |
| `NET-WAIT` | which wait-online is `enabled` | That's the one to mask (usually only one exists). Biggest single win. |
| `GADGET`   | `libcomposite` loaded? a gadget under `configfs`? a `bb-usb-gadgets`/`generic-board-startup` unit? gadget lines in `am335x_evm.sh`? | This is the stock composite gadget that must be disabled so `g_midi` can bind the UDC. |
| `IIO/ADC`  | `iio:device0` present, `in_voltageN_raw` returns a number | Confirms BB-ADC overlay is on and which `AINx` reads a value (the one your FSR is wired to = `ADC_CHAN`). |
| `MIDI`     | `amidi -l` shows the gadget port + its `hw:X,0` -> `/dev/snd/midiCXD0` | Confirms the gadget path and the rawmidi node number for `MIDI_DEV`. |
| `START`    | any existing midi/sensor `.py` + how it's launched (unit/cron/rc.local) | The messy old launcher to disable/replace with `fsr-midi.service`. |

## If the ADC section is empty
BB-ADC overlay isn't enabled. On modern images: edit `/boot/uEnv.txt`, ensure
`enable_uboot_overlays=1` and add `uboot_overlay_addr4=/lib/firmware/BB-ADC-00A0.dtbo`
(or the equivalent `dtb_overlay=` line for your image), reboot, re-check
`/sys/bus/iio/devices/`.
