# QUICKSTART -- from 0 to a ~10 s USB-MIDI boot (Windows laptop, single mini-USB cable)

Your setup: BeagleBone Black on a microSD, powered + connected over **one mini-USB** cable to a
**Windows** laptop with **VS Code**; FSR402 + hit-LED already wired and working on the stock image.
Follow these in order. **STEP 1 output is what lets me pin the exact cut list** -- send it before STEP 4.

---

## STEP 0 -- Get a shell into the board (stock image, no reflash)
1. Plug the mini-USB in. Windows shows a **"BeagleBone Getting Started (E:)"** drive and the blue
   USR0 LED heart-beats = it booted.
2. If no network adapter appears, install the drivers on that drive: run the 64-bit installer in
   `E:\Drivers\`. (The "Getting Started" drive auto-ejects after a bit -- that's normal, the USB
   network stays up.)
3. Connect. The board is at **192.168.7.2** (stock default):
   - **VS Code**: install *Remote-SSH*, then **Remote-SSH: Connect to Host -> `debian@192.168.7.2`**.
   - or a terminal: `ssh debian@192.168.7.2` (your board password).
   - **Fallback** (if RNDIS is fussy): VS Code *Serial Monitor* on the board's `COMx` @ **115200**.

## STEP 1 -- Capture the old setup, send it to me  ⟵ *do this, paste the output*
Run on the board:
```sh
# (a) find + show the old sensor code (the one blinking the LED)
ls -lt /home/debian/*.py /root/*.py /opt/*/*.py 2>/dev/null
systemctl list-units --type=service | grep -iE 'midi|sensor|fsr'
crontab -l 2>/dev/null; cat /etc/rc.local 2>/dev/null
cat /home/debian/<the-file>.py          # cat the one that matched above

# (b) the diagnostics block (measures where the 60 s goes) -- copy the whole block from
#     docs/diagnostics.md and run it, then paste everything back.
```
From (a) I copy the **real values** (LED pin + blink mode, ADC channel, note, MIDI channel,
thresholds) into `src/fsr_midi.py`. From (b) I pin the **exact `MASK=`** and confirm how to free
the UDC for `g_midi`. **-> paste both back here.**

## STEP 2 -- Back up the working SD card (5 min, saves you later)
On Windows, image the card so you always have a known-good rollback:
- **balenaEtcher** (*Flash from file* has a companion *Clone drive*), or **Win32 Disk Imager**
  (*Read* -> save `bbb-stock-working.img`).
Then you can experiment freely and re-flash this image if anything breaks. (You boot from SD, so
a bad change is never fatal -- worst case, write this image back.)

## STEP 3 -- Put this template on the board + match your values
1. Get the repo onto the board. Easiest from the laptop repo folder (Windows has `scp`):
   ```powershell
   scp -r . debian@192.168.7.2:~/bbb
   ```
   (or `git clone -b claude/bbb-midi-boot-speed-jtmff1 https://github.com/drums55/bbb ~/bbb` if the
   board has internet; or drag the folder in via VS Code Remote-SSH.)
2. Edit `~/bbb/src/fsr_midi.py` CONFIG to match STEP 1(a): `ADC_CHAN`, `NOTE`, `CHANNEL`,
   `LED_GPIO`, `LED_MODE` (`hold`/`flash`). *(I'll give you the exact numbers from your old code.)*
3. Sanity-check the sensor path with the live tuner (no MIDI, safe):
   ```sh
   python3 ~/bbb/src/fsr_midi.py --tune      # press the sensor, watch min/max; Ctrl-C to stop
   ```

## STEP 4 -- Apply the Stage-1 boot cut, then measure  ⟵ *after I confirm MASK= from STEP 1*
```sh
cd ~/bbb
sudo nano setup/stage1_apply.sh     # set MASK= to the units your `blame` actually showed
sudo ./setup/stage1_apply.sh        # set multi-user, mask net-wait/bloat, free UDC, install g_midi + service
sudo reboot
```
After it reboots (unplug/replug or wait), reconnect and verify:
```sh
systemd-analyze                     # userland well under 10 s
amidi -l                            # the gadget MIDI port is present on the BBB
journalctl -u fsr-midi -b           # "MIDI out -> /dev/snd/midiCxD0", rest/thresh line
# decoupling proof: host still sees the MIDI device even with the script stopped
sudo systemctl stop fsr-midi        #   -> device stays visible to the host
sudo systemctl start fsr-midi       #   -> notes flow again
```
Something wrong? `sudo ./setup/stage1_revert.sh && sudo reboot` puts it back. Worst case, re-flash
the STEP 2 image.

> ⚠️ After Stage 1 the board is **g_midi only** -- the stock "Getting Started" drive and the
> **SSH-over-USB you used in STEP 0 are gone** (g_midi took the USB port). To keep developing on a
> single cable, use the **dev card** (`docs/dev_workflow.md` -> the RNDIS `usb-dev-gadget`), and
> keep this Stage-1 card as your **perf card**. Do STEP 2's backup on a second SD so you have both.

## STEP 5 -- Day-to-day dev loop (on the dev card)
From VS Code on the laptop, against `debian@192.168.7.2`:
- Edit `src/fsr_midi.py` locally -> Run Task **"BBB: deploy + restart"** (or `tools/deploy.sh`).
- Watch: Run Task **"BBB: follow logs"** (`tools/logs.sh`).
- Tune thresholds: Run Task **"BBB: tune sensor"** (`tools/tune.sh`).
See `docs/dev_workflow.md` for the full loop, and `docs/stage2_fastboot.md` if ~10 s isn't enough.

---

### Where each piece is documented
| Topic | File |
|---|---|
| What to run on the board + how to read it | `docs/diagnostics.md` |
| FSR402 wiring, 1.8 V safety, hit-LED, gpio table | `docs/hardware.md` |
| VS Code loop, RNDIS dev gadget, FTDI serial, dev/perf cards | `docs/dev_workflow.md` |
| The Stage-1 cut (masks, UDC, install) | `setup/stage1_apply.sh` (+ `revert`) |
| Optional <5 s (initramfs / Buildroot) | `docs/stage2_fastboot.md` |
