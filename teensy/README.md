# Teensy version -- the instant-on alternative

The BeagleBone is a Linux computer, so it always pays a boot cost (we cut it 62s -> 24s, floor
~9.6s kernel). A **Teensy is a microcontroller: no OS, firmware runs from flash on power-up**, so
it's a class-compliant USB-MIDI device in **<0.1 s** -- "plug in = play". For one FSR -> one note
this is the natural fit.

## Flash it
1. Install **Arduino IDE** + **Teensyduino**.
2. `Tools > Board` -> your Teensy (3.x / LC / 4.x).
3. `Tools > USB Type` -> **MIDI** (this is what makes `usbMIDI` available).
4. Open `fsr_midi_teensy.ino`, **Upload**. Done -- the host shows a "Teensy MIDI" device instantly.

## Wire it (⚠️ 3.3 V analog -- Teensy pins are NOT 5 V tolerant)
```
  3V3 ---[ FSR402 ]---+--- A0            (FSR_PIN)
                      +--- Rm ~22k ------ GND
  LED_PIN(2) ---[ R 330-1k ]---|>|--- GND
```
FSR is a resistor (no spikes) -> no clamp needed. Meter A0 at max press: must stay <= 3.3 V
(guaranteed since the divider is fed from 3V3). Pick any analog pin for `FSR_PIN`, any digital
pin for `LED_PIN`.

## Config (top of the .ino) -- locked to the original rig
`NOTE=51` (D#3), `CHANNEL=1`, `LED` lit while pressed. Trigger thresholds are the raw-count
equivalents of the old normalized 0.2 / 0.1. Tune `THRESH` / `RELEASE` / `VEL_CEIL` by watching
the sensor (add a `Serial.println(analogRead(FSR_PIN));` in `loop()` and open the Serial Monitor).

## vs the BeagleBone
Keep the BBB build (`../src`, `../docs/applied.md`) if you need Linux on the device for other
reasons. For *just* FSR -> MIDI, the Teensy wins on boot time, simplicity, and reliability -- no
services, no SD card, no SSH. Same MIDI contract (note 51 / ch 1) so the LiveBox/blackbox app
doesn't know the difference.
