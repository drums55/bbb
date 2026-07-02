# Build guide — FSR multi-pad (audience drum-pad)

Turn the breadboard prototype into a durable 2–4 pad box people can press/tap at the front of the
stage. Keeps the FSR (press/tap feel), Teensy 2.0 (instant-on USB-MIDI), USB run ≤5 m.

## How pads map to the app (important)
LiveBox/blackbox has a **4×4 pad grid = MIDI notes 36–51** — `pad 1 = 36 … pad 16 = 51`
(`pad index = note − 36`). Notes outside 36–51 fire **no** pad. Set `NOTE[]` in the sketch to the
pads you want:

| pad | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |10 |11 |12 |13 |14 |15 |16 |
|-----|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| note|36 |37 |38 |39 |40 |41 |42 |43 |44 |45 |46 |47 |48 |49 |50 |51 |

The app's **MIDI pads channel** (`midi_pads_ch`) must equal the sketch's `CHANNEL` (**10**). It's
already set — that's why the single pad fires pad 16 (note 51). (Tip: the app also has **MIDI-Learn
for pads**, so you can re-map a pad to whatever note a pad sends if you prefer.)

## Parts
- **Teensy 2.0** + mini-USB cable (data), ≤5 m total to the host (plain passive cable is fine).
- Per pad (×N): **FSR402**, **Rm 22 kΩ**, a **1 kΩ** series R + **10 nF** cap (filter, optional but
  nice for a public device), and — optional — a **hit LED** + **330 Ω–1 kΩ** R.
- **perfboard**, wire, **screw terminals** (for the FSR leads), an **ABS project box**, grommets,
  a cable gland (or hot-glue) for USB strain relief, a **plywood base** + non-slip feet.

## Pad construction (press/tap-friendly, protects the FSR)
```
  [ pad surface: rubber / silicone / thin mouse-pad ]
  [ foam disc/dome over the FSR active area ]   <- spreads force, no point-loads
  [ FSR402 ]
  [ rigid base: plywood / acrylic ]
```
The foam turns a poky finger into even pressure and shields the FSR from abuse. Glue the FSR to the
base; don't let people hit the bare sensor.

## Wiring (shared rails, one divider per pad)
```
  Teensy 5V  ─────┬───────────┬─────────  (rail to all pads)
                [FSR0]      [FSR1]  ...
                  │           │
     ┌── A0 ◄──[1k]──┴─[10nF]─┴─ (node)      each: 5V-[FSR]-node ; node-[Rm 22k]-GND
     │              [Rm0 22k]
  Teensy GND ─────┴───────────┴─────────  (rail to all pads)
```
- One **5V** rail + one **GND** rail across the box; **Rm + the 1k/10nF filter stay on the board**
  near the Teensy. Only the **two FSR leads** run out to each pad (via screw terminals).
- Analog pins (Teensy 2.0): **A0=F0, A1=F1, A2=F4, A3=F5** (add A4=F6, A5=F7 … for more pads).
- Optional per-pad **hit LED**: `HIT_LED pin (B0..B3 = 0..3) —[330–1k]—▶|— GND`.

## Assembly / durability (no breadboard)
- **Solder** the Teensy + Rm/filter parts to a **perfboard**. Bring FSR leads to **screw terminals**
  so a worn pad swaps out without soldering.
- Put the board in the **ABS box**; FSR leads exit through **grommets**.
- **Strain-relieve the USB**: anchor the cable to the box (cable gland / knot + hot-glue) so tugs
  pull on the box, not the fragile mini-USB jack — the jack is the #1 failure point on a stage floor.
- Mount pads on the **plywood base** with **non-slip feet**; label pads.

## USB
≤5 m → a single passive mini-USB→A cable (or a short mini-USB + a USB-A extension, total ≤5 m). No
powered hub / active repeater needed at this length.

## Bring-up test
1. Set `NUM_PADS` + `NOTE[]` in `fsr_midi_teensy/fsr_midi_teensy.ino`; USB Type = MIDI; upload.
2. **MidiView**: tap each pad → its note (from the table) on **ch 10**, velocity by force; that pad's
   LED lights; on-board LED stays solid.
3. **LiveBox**: each pad fires its 4×4 grid cell. Rapid taps → no double-trigger (refractory).
