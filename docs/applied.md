# Applied Stage-1 recipe (as proven on the live board)

The board runs BeagleBone.org Debian (kernel 4.19.94-ti-r42) from microSD, with a **custom
composite USB gadget** (`setup_midi_gadget.sh` -> ACM + MIDI) started by `midi_gadget.service`,
and the sensor script (`/home/debian/midi_autorun/midi_send.py`) started by `midi_autorun.service`.

## Result
```
before:  kernel 9.8s + userspace 52s  = 62s   (host saw MIDI ~50s)
after:   kernel 9.6s + userspace 13s  = 24s   (multi-user @13s; MIDI comes up early)
```

## Root causes found (via systemd-analyze on the board)
1. **`generic-board-startup.service` = 41s** (BeagleBoard.org boot bundle) held up multi-user.target.
2. **`midi_gadget.service` was `After=multi-user.target`** -> the gadget (host-visible MIDI) only
   came up after ~50s. Reordering it early is the decouple win.
3. **`serial-getty@ttyGS0.service`** (USB-serial login on the gadget's ACM) sat on the critical
   path and, once the gadget was reordered, ballooned to a **~90s** wait on getty.target. We don't
   use USB-serial login (SSH over the RJ45 works), so masking it was the big fix.

## Gotcha
`setup_midi_gadget.sh` never `modprobe`s **libcomposite** -- it relied on the stock `g_multi`
(loaded by generic-board-startup) to pull it in. Once we masked generic-board-startup, the gadget
`mkdir /sys/kernel/config/usb_gadget/...` failed with *Operation not permitted*. Fix: load
libcomposite ourselves.

## The exact commands (run over SSH as debian, reversible)
```sh
# 1) default target: drop graphical
sudo systemctl set-default multi-user.target

# 2) mask the boot hogs / unused services
sudo systemctl mask generic-board-startup.service \
                     bonescript-autorun.service \
                     nginx.service \
                     wpa_supplicant.service \
                     serial-getty@ttyGS0.service \
                     getty@tty1.service

# 3) load libcomposite ourselves (generic-board-startup used to)
echo libcomposite | sudo tee /etc/modules-load.d/libcomposite.conf

# 4) bring the MIDI gadget up EARLY (not after multi-user.target), self-load libcomposite
sudo mkdir -p /etc/systemd/system/midi_gadget.service.d
sudo tee /etc/systemd/system/midi_gadget.service.d/early.conf >/dev/null <<'CONF'
[Unit]
After=
After=sys-kernel-config.mount systemd-modules-load.service

[Service]
ExecStartPre=/sbin/modprobe libcomposite
CONF

# 5) sensor script right after the gadget
sudo mkdir -p /etc/systemd/system/midi_autorun.service.d
sudo tee /etc/systemd/system/midi_autorun.service.d/early.conf >/dev/null <<'CONF'
[Unit]
After=
After=midi_gadget.service
CONF

sudo systemctl daemon-reload
sudo reboot
```

## Verify
```sh
systemd-analyze                              # userspace ~13s
systemctl is-active midi_gadget midi_autorun # active active
amidi -l                                     # IO hw:1,0 f_midi
# squeeze the sensor -> LED + notes
```

## Revert (all reversible)
```sh
sudo systemctl unmask generic-board-startup.service bonescript-autorun.service nginx.service \
                       wpa_supplicant.service serial-getty@ttyGS0.service getty@tty1.service
sudo rm -rf /etc/systemd/system/midi_gadget.service.d /etc/systemd/system/midi_autorun.service.d
sudo rm -f /etc/modules-load.d/libcomposite.conf
sudo systemctl set-default graphical.target
sudo systemctl daemon-reload && sudo reboot
```

## Notes
- Access is over **RJ45 -> router** (laptop on the same WiFi). mDNS `beaglebone.local` was flaky
  after reboot; connect by IP instead (find via `arp -a | findstr 1c-ba-8c` after a ping sweep).
## Stage-2 attempts (measured -- not worth it on this board)
- **uEnv trim** (commented `uboot_overlay_pru`, added `loglevel=3`; kept `enable_uboot_cape_universal`
  and `net.ifnames=0`): kernel stayed **9.62s** (was 9.60s) -> **~0 gain**. The kernel time is a
  fixed cost of the stock 4.19-ti kernel + cape-universal probing every pin, not the PRU overlay.
  (uEnv backed up to `/boot/uEnv.txt.bak`; revert with `sudo cp /boot/uEnv.txt.bak /boot/uEnv.txt`.)
- **initramfs gadget**: not pursued. The gadget can only bind the UDC *after* the kernel USB stack
  is up (inside that 9.6s), so host-sees-MIDI can't beat ~kernel time -> ~10s vs the current ~12s,
  i.e. ~2s for added risk/complexity. Skipped.
- **The real floor here is kernel ~9.6s.** Going below ~15s total needs a custom minimal kernel /
  Buildroot (drop unused drivers, replace cape-universal with a BB-ADC-only overlay) -- a separate
  project, not a config tweak. Stopped at **24s total / ~12s host-sees-MIDI** (from 62s / ~50s).
