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

## Notes
- FSR402 is durable enough for repeated slap/tap triggering. Velocity is expressive but not
  lab-precise -- perfect for a drum trigger, not for weighing things.
- **If you ever swap in a piezo** instead, it DOES need protection: Schottky diodes from the
  node to GND and to 1.8 V, a ~1 MOhm bleed resistor, and a series resistor -- and the trigger
  algorithm changes to peak-detect-with-decay (a fast transient spike, not a sustained level).
  None of that is needed for the FSR.
