# Teensy dev workflow -- VS Code + git + Arduino IDE (Windows)

The complete loop, end to end: where each tool fits, one-time setup, and the daily
edit -> flash -> test -> commit cycle.

## The mental model (who does what)
```
  VS Code  ── your home base: git (pull/commit/push) + read the repo/docs
     │
     │  (the code file: teensy/fsr_midi_teensy.ino)
     ▼
  Arduino IDE  ── compiles + uploads the .ino to the Teensy
     │
     ▼
  Teensy 2.0  ── the instrument: plug in = runs (no boot)
     │  USB-MIDI
     ▼
  Windows / DAW / LiveBox  ── receives Note 51 on ch 1
```
Rule of thumb: **edit + upload in Arduino IDE, do git in VS Code.** (You *can* edit in VS Code too --
see the note at the end -- but keeping the code in one editor avoids "who has the latest file?".)

---

## Part A -- one-time setup

### A1. Tools
- **VS Code** -- you have it.
- **Git** -- you have it (`C:\git\bbb` exists).
- **Arduino IDE 2.x** -- install from https://www.arduino.cc/en/software
- **Teensy support** in Arduino IDE:
  1. `File > Preferences` -> **Additional boards manager URLs** ->
     `https://www.pjrc.com/teensy/package_teensy_index.json`
  2. `Tools > Board > Boards Manager…` -> search **Teensy** -> install *Teensy (for Arduino IDE 2.x)*.
- **MIDI-OX** (optional, to watch MIDI on Windows) -- http://www.midiox.com

### A2. Get the code onto your machine (it's on a feature branch)
All the work is on the branch `claude/bbb-midi-boot-speed-jtmff1`. In VS Code open a **Terminal**
(`Ctrl+~`) and:
```powershell
cd C:\git\bbb
git fetch origin
git checkout claude/bbb-midi-boot-speed-jtmff1
git pull
```
Now `C:\git\bbb\teensy\` has the sketch + docs.

### A3. Arduino IDE settings (set once)
- `Tools > Board > Teensy > **Teensy 2.0**`
- `Tools > USB Type > **MIDI**`   ← makes it a MIDI device / enables `usbMIDI`

### A4. Wire the FSR (⚠️ Teensy 2.0 = 5 V)
```
  VCC(5V) ──[ FSR ]──┬── F0   (= A0 in code)
                     └── Rm(22k) ── GND
```
LED: skip -- the sketch uses the on-board LED (pin 11) for now. (External LED later: silk **B0** =
pin `0`, set `LED_PIN = 0`.)

---

## Part B -- the daily loop

1. **VS Code -> Terminal:** get the latest
   ```powershell
   cd C:\git\bbb && git pull
   ```
2. **Arduino IDE:** `File > Open… > C:\git\bbb\teensy\fsr_midi_teensy.ino` (first time; after that it
   remembers). Tweak a value (e.g. `THRESH`, `NOTE`, `LED_PIN`).
3. **Upload** (→). Plug the Teensy in; if it says "press button", tap the button once. ~1 s later
   it's running the new code.
4. **Test:** squeeze the FSR -> on-board LED + a Note in MIDI-OX / your DAW. Tune and re-upload
   until it feels right.
5. **VS Code -> Source Control** (the branch icon on the left): you'll see `fsr_midi_teensy.ino`
   changed. Type a message -> **Commit** -> **Sync/Push**. (Or in the terminal:)
   ```powershell
   git add teensy/fsr_midi_teensy.ino
   git commit -m "teensy: tune thresholds"
   git push
   ```

That's the whole cycle: **pull -> edit -> upload -> test -> commit/push.**

---

## Tuning (see live sensor values)
In `loop()` add `Serial.println(analogRead(A0));`, set `Tools > USB Type > **Serial + MIDI**`,
upload, open **Tools > Serial Monitor**. Press the sensor: set `THRESH` just above the resting
number, `VEL_CEIL` near your hardest press. Then switch USB Type back to **MIDI** if you don't need
serial.

## Editing in VS Code instead of Arduino IDE (optional)
VS Code is a nicer editor. If you edit `fsr_midi_teensy.ino` there and **save**, Arduino IDE 2.x
notices the file changed and offers to reload -- accept, then Upload. Just don't edit the same file
in both at once. (For a fully-integrated "build+upload inside VS Code" setup, the **PlatformIO**
extension supports Teensy 2.0 -- more powerful, but a bigger learning curve than Arduino IDE. Only
worth it if you outgrow the simple loop above.)

## Troubleshooting
- **No "Teensy 2.0" board** -> A1 boards-manager step didn't finish.
- **Upload hangs** -> tap the button on the Teensy.
- **No MIDI device on Windows** -> USB Type isn't MIDI (A3), or a charge-only cable.
- **`git checkout` says pathspec not found** -> run `git fetch origin` first (A2).
