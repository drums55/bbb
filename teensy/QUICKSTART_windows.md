# Teensy 2.0 -- from nothing to playing, on Windows

A from-scratch runbook: install the tools, flash `fsr_midi_teensy.ino`, wire the FSR, test.
No Linux, no boot wait -- plug the Teensy in and it's a USB-MIDI device.

## You need
- **Teensy 2.0** + a **mini-USB** cable (data, not charge-only)
- **FSR** (the one from the rig) + a **~22 kΩ** resistor (Rm) + jumper wires + breadboard
- (later) the rig's **LED** + a **330 Ω-1 kΩ** resistor -- optional; the on-board LED works first
- Windows 10/11. No driver needed (Teensy MIDI is class-compliant; the IDE handles uploads).

## STEP 1 -- Arduino IDE
Download + install **Arduino IDE 2.x**: https://www.arduino.cc/en/software (Windows installer).

## STEP 2 -- Add Teensy support (Boards Manager)
1. Open Arduino IDE -> **File > Preferences**.
2. In **Additional boards manager URLs**, add:
   ```
   https://www.pjrc.com/teensy/package_teensy_index.json
   ```
   -> OK.
3. **Tools > Board > Boards Manager…**, search **Teensy**, install **"Teensy (for Arduino IDE 2.x)"**
   by Paul Stoffregen. (This replaces the old separate Teensyduino installer.)

## STEP 3 -- Board + USB settings
- **Tools > Board > Teensy > Teensy 2.0**
- **Tools > USB Type > MIDI**   ← this is what makes it a MIDI device / enables `usbMIDI`

## STEP 4 -- Get the code
You already have the repo at `C:\git\bbb`. Update + open:
```powershell
cd C:\git\bbb
git pull
```
Then in Arduino IDE: **File > Open… > `C:\git\bbb\teensy\fsr_midi_teensy.ino`**.
(Or just download that one file from GitHub and open it.)

## STEP 5 -- Wire the FSR (⚠️ Teensy 2.0 is 5 V)
On the breadboard:
```
  VCC(5V) ──[ FSR ]──┬── F0   (= A0 in code)
                     └── Rm(22k) ── GND
```
- FSR leg 1 -> Teensy **VCC** pin (top-left, next to the USB)
- FSR leg 2 -> Teensy **F0** pin, and from that same node -> Rm(22k) -> a **GND** pin
- LED: **skip for now** -- the code uses the **on-board LED (pin 11)** so you get feedback with no wiring.

## STEP 6 -- Upload
1. Plug the Teensy in (mini-USB).
2. Click **Upload** (→). The **Teensy Loader** window pops up; if it says "press button",
   press the tiny button on the Teensy once. It flashes and reboots in ~1 s.

## STEP 7 -- Test
- Squeeze the FSR -> the **on-board LED lights** while pressed, and a **Note 51 (D#3) on channel 1**
  goes out, velocity tracking force.
- Watch the MIDI on Windows with a free monitor -- **MIDI-OX** (http://www.midiox.com) -> it lists
  a "Teensy MIDI" input; press = Note On 51, release = Note Off. Or just open your DAW / the LiveBox
  app -- same MIDI contract as the BeagleBone, so it "just works".

## STEP 8 -- Tune (if needed)
Thresholds are fractions of full-scale (10-bit on Teensy 2.0): `THRESH` = 0.20 (≈205),
`RELEASE` = 0.10 (≈102), `VEL_CEIL` = 0.32. To see live values, add in `loop()`:
```cpp
Serial.println(analogRead(A0));
```
set **Tools > USB Type > Serial + MIDI**, upload, open **Serial Monitor**, press the sensor, then
set `THRESH` just above the resting value and `VEL_CEIL` near your hardest press.

## Move the LED to the rig's external LED (optional)
Once it works: silk **B0** = Arduino pin `0` -> R(330-1k) -> LED(+) , LED(-) -> GND. Set
`LED_PIN = 0` in the sketch, re-upload.

## Troubleshooting
- **No "Teensy 2.0" in the board list** -> STEP 2 didn't finish; re-open Boards Manager and install.
- **Upload hangs / "please press button"** -> press the button on the Teensy once.
- **No MIDI device on Windows** -> USB Type isn't MIDI (STEP 3), or the cable is charge-only.
- **Note fires but no velocity range / double hits** -> tune `THRESH`/`VEL_CEIL`/`REFRAC_MS` (STEP 8).
