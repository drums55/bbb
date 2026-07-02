# Hardware -- Interlink FSR402 into the BBB ADC

## The part
Interlink **FSR402**: 0.5" (12.7 mm) round force-sensitive resistor, 2 pins.
- No force: **> 10 MOhm** (effectively open).
- Light touch .. hard press: **~100 kOhm down to ~200 Ohm - 1 kOhm**.
- Usable force ~0.2 - 20 N. It is a *resistance*, not a voltage source -- so unlike a piezo
  it produces **no high-voltage spikes** and needs **no clamp diodes**.

## The one rule: keep the ADC pin <= 1.8 V
The AM335x ADC reference is **1.8 V** and the pins are **not 3.3 V tolerant**. Power the
divider from the board's dedicated **1.8 V ADC rail** so the node physically cannot exceed
1.8 V -- no clamp, safe by construction.

```
  P9_32  VDD_ADC (1.8 V)
     |
   [ FSR402 ]
     |
     +---------------------> AINx   (e.g. P9_39 = AIN0)   -> in_voltage0_raw
     |
   [ Rm ~22k ]
     |
  P9_34  AGND
```

## P9 header pins
- **P9_32** = VDD_ADC (1.8 V reference out) -- top of the divider.
- **P9_34** = AGND -- bottom of the divider.
- **AINx**: P9_39=AIN0, P9_40=AIN1, P9_37=AIN2, P9_38=AIN3, P9_33=AIN4, P9_36=AIN5, P9_35=AIN6.
  Wire the FSR/Rm node to one AINx and set `ADC_CHAN` in `src/fsr_midi.py` to match.

## Choosing Rm
`Rm` trades sensitivity for headroom. Node voltage `V = 1.8 * Rm / (Rfsr + Rm)`:
- **Larger Rm (47 k)** -> more sensitive at light force, but rails sooner on hard hits.
- **Smaller Rm (10 k)** -> more dynamic range for hard slaps, less sensitive when light.
- **Start ~22 k.** On the bench watch `cat /sys/bus/iio/devices/iio:device0/in_voltageN_raw`:
  - resting value should be low (near 0),
  - a light tap should clear `REST_MARGIN` (default +60 counts),
  - a hard slap should read high but **stay under 4095** (not railed), so velocity has range.
  Adjust `Rm` and the `fsr_midi.py` thresholds together.

## Hit LED (matches the original rig)
The original rig lights an LED on each press. Drive it from any spare GPIO -> series
resistor -> LED -> GND (active-high). Keep the resistor ~330 Ohm - 1 k (BBB GPIO is 3.3 V,
~4-6 mA is plenty for an indicator).

```
  GPIO pin ---[ R 330-1k ]---|>|--- GND        (LED anode to R, cathode to GND)
```

Set `LED_GPIO` in `src/fsr_midi.py` to the **sysfs gpio number** of the pin you wired (not
the header label). `LED_MODE="hold"` lights it while pressed; `"flash"` gives a brief blink
per hit. If nothing lights, the pin likely isn't muxed as GPIO or the number is wrong -- the
script just logs and runs without the LED (never blocks MIDI).

Handy P8/P9 header pin -> gpio number (all default to GPIO mode on stock Debian):

| Header | gpio | Header | gpio |
|--------|------|--------|------|
| P9_15  | 48   | P8_11  | 45   |
| P9_23  | 49   | P8_12  | 44   |
| P9_12  | 60   | P8_14  | 26   |
| P9_27  | 115  | P8_16  | 46   |

(`gpio = 32*bank + index`; confirm your board with `gpioinfo` if you have libgpiod.) The
template default is **60 = P9_12** (`GPIO1_28`), matching the original rig -- change it if you
rewire the LED.

## Notes
- FSR402 is durable enough for repeated slap/tap triggering. Velocity is expressive but not
  lab-precise -- perfect for a drum trigger, not for weighing things.
- **If you ever swap in a piezo** instead, it DOES need protection: Schottky diodes from the
  node to GND and to 1.8 V, a ~1 MOhm bleed resistor, and a series resistor -- and the trigger
  algorithm changes to peak-detect-with-decay (a fast transient spike, not a sustained level).
  None of that is needed for the FSR.
