# Stage 2 -- toward <5 s (optional, proposal only -- needs reflash)

Only pursue this if Stage 1's ~10 s isn't enough. **This is not applied by the setup scripts**
-- it's a documented path. Be realistic about the floor:

> **AM335x U-Boot + kernel ~= 4-6 s.** "MIDI usable in ~5 s" is achievable; "<3 s" is not
> without a heavy kernel/U-Boot diet. The wins below stack on the Stage-1 Debian for ~5-7 s
> with **no rootfs rebuild**.

Chosen order: **2.1 initramfs g_midi** then **2.2 U-Boot trim**. Buildroot (2.3) is deferred
unless you later need to reach the very floor.

## 2.1 -- g_midi in the initramfs (host sees MIDI during *early* boot)
Load the gadget from the initramfs so the USB device enumerates *before* the rootfs/userland
is up -- the host sees a MIDI port in ~3-5 s while Debian finishes behind it.

```sh
echo g_midi | sudo tee -a /etc/initramfs-tools/modules
sudo update-initramfs -u
# make sure /boot/uEnv.txt actually loads the regenerated initrd (uInitrd / initrd.img); reboot.
```
The sensor script still starts from systemd (a bit later), but per the decoupling rule the
**device is present the whole time** -- only the first note might be marginally late. Biggest
honest win of Stage 2.

## 2.2 -- U-Boot trim (`/boot/uEnv.txt`)
- `bootdelay=0` -- no interactive countdown.
- Silence the console: add `quiet` (and optionally `loglevel=3`) to the kernel cmdline.
- Drop overlays you don't use (keep only BB-ADC); every overlay costs probe time.
- Disable HDMI/audio overlays if present (`disable_uboot_overlay_video=1`).

Each saves ~1-3 s combined. All reversible by editing `uEnv.txt` back.

## 2.3 -- Tiny Buildroot image (the real <5 s path -- most effort, deferred)
A minimal rootfs with no systemd/Debian services, whose `init` loads `usb_f_midi` (or `g_midi`)
and execs the sensor loop directly. `g_midi` can be compiled **into** the kernel so it's live
the instant the kernel runs -- boot goes straight to MIDI. This is the only route that genuinely
approaches the 4-5 s floor, but it's a separate SD image and a cross-build. Revisit only if
2.1 + 2.2 aren't fast enough.

## Measuring
```sh
systemd-analyze                       # userland time (Stage 1)
# wall clock: power-on -> host enumerates the USB-MIDI device (the number that matters)
# on the host (Linux): `dmesg -w` and watch for the MIDI device appear; or time aseqdump -l.
```
