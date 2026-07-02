# bbb -- BeagleBone Black FSR pressure sensor -> USB MIDI

A BeagleBone Black (AM335x) reads an **Interlink FSR402** pressure sensor through the on-chip
ADC and emits **class-compliant USB-MIDI**. Slap/press the sensor -> a MIDI note goes to the
host (the **LiveBox / blackbox** looper, or any DAW). One FSR -> one note (**note 36 = pad 1**,
LiveBox convention), velocity from press force.

The device already works. This repo is a **clean template rewrite** plus a **boot-time fix**:
stock BeagleBoard Debian takes **~60 s** before the host sees MIDI (full Debian userland +
network wait + the multi-function USB gadget), and Stage 1 cuts that to **~10 s** with **no
reflash** -- reversibly.

## The key idea: decouple "host sees the device" from "the script started"
The **`g_midi` kernel module** is loaded early at boot, so the host enumerates the USB-MIDI
device within a few seconds -- independent of Python. The sensor script then just writes notes
into that already-present ALSA rawmidi port. A late (or stopped) script never hides the device.

## Layout
```
src/fsr_midi.py             # sensor read (IIO ADC) + velocity note-out (raw rawmidi, zero deps)
systemd/fsr-midi.service    # starts fast, waits for NOTHING network
gadget/                     # g_midi module config (Option A, default) + configfs script (Option B)
setup/stage1_apply.sh       # idempotent + reversible: set-default, mask bloat, free UDC, install
setup/stage1_revert.sh      # undo everything Stage 1 did
docs/diagnostics.md         # Stage 0: what to run on the BBB (read-only) and how to read it
docs/hardware.md            # FSR402 divider wiring + ADC 1.8 V safety
docs/stage2_fastboot.md     # optional <5 s proposal: initramfs g_midi + U-Boot trim + Buildroot
```

## Do it in order
1. **Diagnose (safe, read-only).** SSH into the BBB, run the block in
   [`docs/diagnostics.md`](docs/diagnostics.md), keep the output. It confirms the real
   service / gadget / ADC names on your image (they differ between BeagleBoard.org variants).
2. **Confirm the mask list.** Edit `MASK=` in `setup/stage1_apply.sh` to match the units that
   actually showed up in `systemd-analyze blame`. Don't mask what you didn't see. Check whether
   the stock gadget is a service **or** `enable_uboot_usb_gadgets=1` in `/boot/uEnv.txt` (the
   script handles both, but confirm which applies).
3. **Wire the sensor** per [`docs/hardware.md`](docs/hardware.md) (divider off the **1.8 V** rail
   so the ADC pin can't exceed 1.8 V). Note which `AINx` -> set `ADC_CHAN` in `src/fsr_midi.py`.
4. **Set the MIDI mapping + LED.** `NOTE` / `CHANNEL` in `src/fsr_midi.py` must match the app's
   pads channel (`_midiPadsChannel` in LiveBox). Default note 36, channel 10. If you wired the
   **hit LED**, set `LED_GPIO` to the sysfs gpio number of your pin (see `docs/hardware.md`);
   `LED_MODE` = `hold` (lit while pressed) or `flash` (brief blink). Set `LED_ENABLE=False` to skip it.
5. **Apply Stage 1:** `sudo setup/stage1_apply.sh`, then `sudo reboot`.
6. **Verify** (below). If you need faster, see `docs/stage2_fastboot.md`.

## Verify
```sh
systemd-analyze                         # userland boot time, well under 10 s
amidi -l                                # gadget MIDI port present on the BBB
journalctl -u fsr-midi -b               # "MIDI out -> /dev/snd/midiCxD0", rest/thresh line
# decoupling proof:
sudo systemctl stop fsr-midi            #  -> host STILL sees the USB-MIDI device
sudo systemctl start fsr-midi           #  -> notes flow again
```
On the host, `aseqdump -p <port>` (Linux) or a DAW should show **Note-On 36** with velocity
tracking press force, **Note-Off** on release, and no double-triggers (tune `REST_MARGIN` /
`RELEASE_HYST` / `REFRACTORY_MS` in `src/fsr_midi.py`).

## Safety
Meter the `AINx` node at max press -> it must stay **< 1.8 V**. Because the divider is powered
from the 1.8 V ADC rail, it can't exceed that by construction. FSR (not piezo) -> no clamp
needed. (Swapping in a piezo later *does* need clamp/bleed/series protection -- see
`docs/hardware.md`.)
