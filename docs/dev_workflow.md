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
- This laptop is **Windows with no ethernet**, so the dev loop rides the **one mini-USB cable**:
  a composite **MIDI + USB-Ethernet (RNDIS)** dev gadget gives MIDI *and* SSH-over-USB at once.
  **FTDI serial** is the always-works fallback for debugging boot itself.

## 0. Day-0: the stock image already gives you SSH-over-USB (use it first)

Plug the untouched board into Windows and you'll see a **"BeagleBone Getting Started (E:)"** drive
and the blue **USR0** LED heart-beating -- that's the stock multi-function gadget (mass-storage +
serial + RNDIS network) booted and working. Use it to get in and run diagnostics *before* flashing
or cutting anything:
1. Install the Windows drivers from the board drive: run the 64-bit installer in `E:\Drivers\`.
   This adds the **RNDIS network adapter** + a **serial COM** port.
2. The board is at **192.168.7.2** (stock default; its dnsmasq configures your adapter). `ssh
   debian@192.168.7.2` (your board password), or VS Code **Remote-SSH**. No-network fallback: open
   the board's serial COM in VS Code **Serial Monitor** @115200 -> a login prompt.
3. Run `docs/diagnostics.md` and `cat` the old sensor `.py`. *Then* build the dev/perf cards.

The "Getting Started" drive is just the stock gadget's mass-storage; it disappears once we switch
to `g_midi` / the dev gadget. You don't need `START.htm`. Our RNDIS dev gadget (section 1A) simply
replicates this same SSH-over-USB path *minus* the mass-storage, *plus* the MIDI function.

## 1. Get a shell into the board (Windows, single mini-USB cable)

**A. USB-Ethernet dev gadget = the primary path.** Boot the **dev card**; it runs
`gadget/usb_midi_rndis_gadget.sh` (installed as `usb_dev_gadget.sh`) -> the host sees a MIDI
device **and** a usb network on the same cable. It uses **RNDIS + Microsoft OS descriptors**, so
Win10/11 auto-installs the "USB RNDIS" driver with no INF file. Board = `192.168.7.2`.

Windows host steps (one-time):
1. Plug the mini-USB cable. Windows enumerates a "Remote NDIS Compatible Device" + a new
   network adapter (a few seconds).
2. IP: if the board has `dnsmasq`, Windows gets `192.168.7.1` automatically -- done. If not,
   set that adapter static: *Settings > Network > Ethernet > Edit IP > Manual > IPv4* =
   `192.168.7.1`, mask `255.255.255.0` (gateway blank).
3. `ssh debian@192.168.7.2` (Windows has a built-in OpenSSH client), or VS Code **Remote-SSH:
   Connect to Host** (see section 2).

> The perf card drops RNDIS for `g_midi` alone (faster, no network) -- so do the tuning/coding on
> the **dev card**, then move the finished `fsr_midi.py` to the perf card. Since you boot from SD,
> that's just swapping cards.

**B. FTDI serial console (the always-works fallback -- needs a cheap 3.3 V USB-serial cable).**
On the **J1** 6-pin header (next to P9_1): GND/RX/TX, **115200 8N1**. Independent of USB gadget
*and* network -- this is how you debug the boot itself or a gadget that won't enumerate. On
Windows: VS Code **Serial Monitor** extension (or PuTTY) on the cable's `COMx`, baud 115200.
Console-only (no file editing) -- for Remote-SSH you need path A.

## 2. VS Code Remote-SSH (the core loop)

Add to `~/.ssh/config` on your laptop:
```
Host bbb
    HostName 192.168.7.2      # the RNDIS dev-gadget board IP
    User debian
```
On Windows this file is `C:\Users\<you>\.ssh\config`.
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
| gadget | `usb-dev-gadget` (MIDI + RNDIS SSH-over-USB) | `g_midi` only (Option A) |
| services | leave more on (avahi for `.local`, networking) | Stage-1 masks applied |
| logging | `--verbose` in the unit | quiet |
| boot | comfy, not measured | the ~10 s you ship |

Set up the **dev card** gadget once (on the board, over serial or the stock USB-net before you
cut it):
```sh
# Windows laptop -> RNDIS. (macOS/Linux: use gadget/usb_midi_ecm_gadget.sh instead.)
sudo install -m0755 gadget/usb_midi_rndis_gadget.sh /usr/local/sbin/usb_dev_gadget.sh
sudo install -m0644 gadget/usb-dev-gadget.service /etc/systemd/system/
sudo systemctl enable --now usb-dev-gadget.service
# also install the sensor script + unit (as stage1 step 5/6 does), then reboot.
```
Build the **perf card** by running `setup/stage1_apply.sh` on it (g_midi only, no RNDIS). Keep the
dev card as your bench + rollback. When Stage 2 (`docs/stage2_fastboot.md`) is in play, experiment on a *third* spare card
and keep both known-good cards untouched.
