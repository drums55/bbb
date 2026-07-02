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

## Wire it (⚠️ feed the divider from the board's logic rail)
- **Teensy 2.0** (ATmega32U4): runs at **5 V**, ADC is **10-bit** -> divider off **VCC (5V)**.
- **Teensy 3.x/4.x**: **3.3 V** analog (pins NOT 5 V tolerant) -> divider off **3V3**.

```
  VCC(5V) / 3V3 ---[ FSR402 ]---+--- A0            (FSR_PIN; Teensy 2.0 silk "F0")
                                +--- Rm ~22k ------ GND
  LED_PIN ---[ R 330-1k ]---|>|--- GND
```
FSR is a resistor (no spikes) -> no clamp needed. Meter A0 at max press: must stay <= the rail
(guaranteed since the divider is fed from that rail). The sketch auto-scales the thresholds to the
board's ADC bits, so the same code works on 2.0 and 3.x/4.x.

**Teensy 2.0 pin labels:** the silk uses AVR port names. `FSR_PIN = A0` is the pin silked **F0**;
`LED_PIN = 11` is the **on-board LED** (handy for a first test). For the rig's external LED, use a
digital pin, e.g. silk **B0** = Arduino pin `0` -> R -> LED -> GND, and set `LED_PIN = 0`.

## Config (top of the .ino) -- locked to the original rig
`NOTE=51` (D#3), `CHANNEL=1`, `LED` lit while pressed. Trigger thresholds are the raw-count
equivalents of the old normalized 0.2 / 0.1. Tune `THRESH` / `RELEASE` / `VEL_CEIL` by watching
the sensor (add a `Serial.println(analogRead(FSR_PIN));` in `loop()` and open the Serial Monitor).

## vs the BeagleBone
Keep the BBB build (`../src`, `../docs/applied.md`) if you need Linux on the device for other
reasons. For *just* FSR -> MIDI, the Teensy wins on boot time, simplicity, and reliability -- no
services, no SD card, no SSH. Same MIDI contract (note 51 / ch 1) so the LiveBox/blackbox app
doesn't know the difference.
