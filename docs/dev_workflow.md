# Dev workflow -- laptop + VS Code, easy to work and debug (without slowing the boot)

Goal: a tight **edit -> deploy -> watch** loop from your laptop, and a debug path that always
gets you into the board. The trick is that the fast/production setup (`g_midi` alone) **takes
over the one mini-USB port**, so the usual BeagleBone SSH-over-USB (192.168.7.2) disappears.
This doc keeps development easy *and* leaves the production boot lean -- the dev conveniences
are opt-in (a separate SD card / gadget), they don't live on the perf image.

## TL;DR
- **Edit** in VS Code on your laptop; **run** on the board via **Remote-SSH** (the board is the
  runtime). Or edit the board's files directly over Remote-SSH.
- Keep **two SD cards** (you already boot from SD -> swapping is the rollback):
  - **dev card** -> composite **MIDI + USB-Ethernet** gadget, so one cable gives you MIDI *and*
    SSH-over-USB. Verbose, comfy.
  - **perf card** -> `g_midi` only + the Stage-1 cuts. This is the ~10 s boot you measure/gig with.
- Three ways in, in order of preference: **(1) Remote-SSH over ethernet**, **(2) Remote-SSH over
  the USB-Ethernet dev gadget**, **(3) FTDI serial console** (always works, even when boot breaks).

## 1. Get a shell into the board (pick what you have)

**A. Ethernet SSH (best if you have an RJ45 at the desk).** Fully decoupled from the USB port,
so it works even on the **perf card** (g_midi-only). We mask network-*wait*, not networking, so
the box still gets an IP -- boot just doesn't block on it. `ssh debian@<board-ip>` (find it from
your router, or `ssh debian@beaglebone.local` if mDNS/avahi is left on).

**B. USB-Ethernet dev gadget (single cable, no RJ45 needed).** Boot the **dev card**; it runs
`gadget/usb_midi_ecm_gadget.sh` -> the host sees a MIDI device **and** a usb network. Board =
`192.168.7.2`; set your laptop's usb-net interface to `192.168.7.1/24`, then `ssh debian@192.168.7.2`.
(This is the same UDC hosting both functions -- dev only; the perf card drops ECM for speed.)

**C. FTDI serial console (the always-works fallback).** A 3.3 V USB-serial cable on the **J1**
6-pin header (next to P9_1): GND/RX/TX, **115200 8N1**. Independent of USB gadget *and* network,
so it's how you debug the boot itself, a wedged network, or a bad gadget. In VS Code use the
**Serial Monitor** extension (baud 115200) or `screen /dev/ttyUSB0 115200`.

## 2. VS Code Remote-SSH (the core loop)

Add to `~/.ssh/config` on your laptop:
```
Host bbb
    HostName 192.168.7.2      # or the ethernet IP / beaglebone.local
    User debian
```
Then in VS Code: **Remote-SSH: Connect to Host -> bbb**. Open `/opt/fsr-midi` (the installed
copy) or a git clone in the home dir. You now edit the board's files directly, with an integrated
terminal for `systemctl` / `journalctl`. Open this repo locally too -- VS Code will offer the
recommended extensions (`.vscode/extensions.json`) and the tasks below (`.vscode/tasks.json`).

## 3. The edit -> deploy -> watch loop

**Option 1 -- edit locally, deploy over SSH** (keeps git history on the laptop):
```
tools/deploy.sh   [user@host]   # rsync src/fsr_midi.py -> /opt + restart the service
tools/logs.sh     [user@host]   # journalctl -u fsr-midi -f
```
Or from VS Code: **Run Task -> "BBB: deploy + restart"**, **"BBB: follow logs"**. Default target
is `debian@192.168.7.2`; pass your ethernet host if you use path A.

**Option 2 -- edit on the board over Remote-SSH**: change `/opt/fsr-midi/fsr_midi.py`, then
`sudo systemctl restart fsr-midi`. Fastest inner loop, no deploy step.

## 4. Debugging the actual hard part (the sensor)

- **Tune thresholds live:** `tools/tune.sh` (or Task **"BBB: tune sensor"**). It pauses the
  service and streams raw ADC with a bar + running min/max. Press the sensor: set `REST_MARGIN`
  just above the resting jitter, `VEL_CEIL` near your hardest slap (kept under 4095). Ctrl-C
  restarts the service.
- **See every note:** run with `--verbose` (or add it to the unit's `ExecStart` on the dev card)
  -> `NOTE-ON 36 vel=… (peak=…)` / `NOTE-OFF 36` in the journal.
- **Confirm the MIDI side:** on the board `amidi -l`; on the host `aseqdump -p <port>` (Linux) or
  a DAW. **Decoupling check:** `sudo systemctl stop fsr-midi` -> the host **still** lists the MIDI
  device (that's the gadget, not the script); `start` -> notes resume.
- **LED not lighting:** `--tune` shows the sensor is fine; check `LED_GPIO` is your actual pin and
  muxed as GPIO (the script logs `LED gpio<n> unavailable` and keeps running if not).

## 5. Dev card vs perf card (doesn't fight the ~10 s goal)

| | dev card | perf card |
|---|---|---|
| gadget | `usb-midi-ecm-gadget` (MIDI + SSH-over-USB) | `g_midi` only (Option A) |
| services | leave more on (avahi for `.local`, networking) | Stage-1 masks applied |
| logging | `--verbose` in the unit | quiet |
| boot | comfy, not measured | the ~10 s you ship |

Build the perf card by running `setup/stage1_apply.sh` on it. Keep the dev card as your bench +
rollback. When Stage 2 (`docs/stage2_fastboot.md`) is in play, experiment on a *third* spare card
and keep both known-good cards untouched.
