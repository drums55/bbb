# Stage 0 -- Diagnostics (run this FIRST, read-only)

SSH into the BBB, run the block, keep the output. It tells us the real service/gadget/ADC
names on *your* image so we mask the right things (they differ across BeagleBoard.org Debian
variants). **Nothing here changes the system.** Paste the output back before Stage 1.

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
  ls /opt/scripts/boot/ 2>/dev/null; \
  echo "== UENV (U-Boot gadget/overlays) =="; grep -viE '^#|^$' /boot/uEnv.txt 2>/dev/null; \
  echo "== MIDI =="; amidi -l 2>/dev/null; aplaymidi -l 2>/dev/null; \
  echo "== IIO/ADC =="; ls /sys/bus/iio/devices/ 2>/dev/null; \
  head -1 /sys/bus/iio/devices/iio:device0/in_voltage*_raw 2>/dev/null; \
  echo "== BOOT MEDIUM (SD vs eMMC) =="; findmnt -n -o SOURCE / 2>/dev/null; \
  cat /proc/cmdline 2>/dev/null; lsblk 2>/dev/null; \
  echo "== START =="; grep -rilE "midi|sensor|note" /etc/systemd/system/ /etc/rc.local 2>/dev/null; \
  crontab -l 2>/dev/null; ls -lt /home/debian/*.py /root/*.py 2>/dev/null | head; } 2>&1
```

## How to read it

| Section    | What to look for | Action |
|------------|------------------|--------|
| `BOOT`     | `systemd-analyze` total; top of `blame` / `critical-chain` | The named units eating seconds are the mask targets in `setup/stage1_apply.sh`. |
| `NET-WAIT` | which wait-online is `enabled` | Mask that one (usually only one exists). Biggest single win, ~15-30 s. |
| `GADGET` + `UENV` | `libcomposite` loaded? a gadget under configfs? a `generic-board-startup` / `bb-usb-gadgets` unit? **`enable_uboot_usb_gadgets=1` in uEnv.txt?** | This is the stock composite gadget holding the single **UDC**. It must be freed so `g_midi` can bind. `UENV` tells us whether U-Boot (not a service) is the one grabbing it. |
| `IIO/ADC`  | `iio:device0` present, `in_voltageN_raw` returns a number | Confirms the BB-ADC overlay is on and which `AINx` reads a value (your FSR channel = `ADC_CHAN`). |
| `BOOT MEDIUM` | `/` on `mmcblk0p*` (=microSD) or `mmcblk1p*` (=onboard eMMC); `root=` in cmdline | Tells us which card holds the live `/boot/uEnv.txt` the setup script edits. **Booting from SD = card-swap reflash** (keep the working card, experiment on a spare, swap back to revert). |
| `MIDI`     | `amidi -l` shows a port + its `hw:X,0` -> `/dev/snd/midiCXD0` | Confirms the gadget path and the rawmidi node (the script auto-detects it; only set `MIDI_DEV` if there are several). |
| `START`    | any existing midi/sensor `.py` + how it's launched (unit / cron / rc.local) | The messy old launcher to disable and replace with `fsr-midi.service`. |

## If the ADC section is empty
The BB-ADC overlay isn't enabled. On modern images edit `/boot/uEnv.txt`: ensure
`enable_uboot_overlays=1` and add a line loading the ADC overlay, e.g.
`uboot_overlay_addr4=/lib/firmware/BB-ADC-00A0.dtbo` (or the `dtb_overlay=` form your image
uses), reboot, re-check `/sys/bus/iio/devices/`.
