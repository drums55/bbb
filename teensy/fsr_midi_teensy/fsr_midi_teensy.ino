// fsr_midi_teensy.ino -- multi-pad FSR -> USB-MIDI + per-pad hit LED, on a Teensy.
// Instant-on (no OS/boot): power the Teensy and it's a class-compliant USB-MIDI device.
// Each pad = one FSR -> one MIDI note (velocity by press force), with its own hit LED.
//
// Arduino IDE setup:  Tools > Board > your Teensy  |  Tools > USB Type > "MIDI"  |  Upload.
// Portable across Teensy 2.0 (ATmega32U4, 5V, 10-bit ADC) and Teensy 3.x/4.x (3.3V, 12-bit).
//
// LEDs:
//   POWER_LED = on-board LED -> solid ON while powered (a "device is alive" indicator).
//   HIT_LED[p] = external LED per pad -> lights while that pad is pressed (-1 to skip a pad).
//
// ⚠️ Feed each FSR divider from the board's logic rail (Teensy 2.0 = VCC 5V; 3.x/4.x = 3V3):
//     VCC/3V3 ---[ FSR402 ]---+--- (FSR_PIN[p])
//                             +--- Rm ~22k ------ GND
// FSR is a resistor (no spikes) -> no clamp. Meter each pin at max press: must stay <= the rail.
// See teensy/BUILD.md for the full multi-pad wiring + enclosure.

const int NUM_PADS = 4;                              // how many pads are wired (2..~12 on Teensy 2.0)
const int FSR_PIN[NUM_PADS] = { A0, A1, A2, A3 };    // Teensy 2.0 silk F0, F1, F4, F5
// LiveBox/blackbox 4x4 pad grid = MIDI notes 36..51  (pad 1 = 36 ... pad 16 = 51;
// pad index = note - 36). Notes OUTSIDE 36..51 hit no pad. Pick the pads you want here:
const int NOTE[NUM_PADS]    = { 48, 49, 50, 51 };    // top row / pads 13-16 (bottom row = 36-39)
const int HIT_LED[NUM_PADS] = {  0,  1,  2,  3 };    // silk B0..B3. Use -1 to skip a pad's LED.
const int CHANNEL   = 10;                            // MIDI channel 1..16 (all pads share it)
const int POWER_LED = LED_BUILTIN;                   // on-board LED = solid ON while powered

// ADC full-scale differs by board; thresholds are fractions of it so they port unchanged.
#if defined(__AVR__)
  const int ADC_MAX = 1023;      // Teensy 2.0 (AVR): fixed 10-bit
#else
  const int ADC_MAX = 4095;      // Teensy 3.x/4.x: 12-bit (set in setup())
#endif
const int THRESH    = (int)(0.20 * ADC_MAX);  // press onset
const int RELEASE   = (int)(0.10 * ADC_MAX);  // note-off below this
const int VEL_CEIL  = (int)(0.25 * ADC_MAX);  // press count that maps to velocity 127
const int VEL_MIN   = 90;    // softest accepted hit (raise for a louder floor)
const int PEAK_MS   = 7;     // track the peak this long, then send Note-On
const int REFRAC_MS = 35;    // debounce after a note-off

enum { ARMED, PEAKING, HELD, REFRACTORY };
int state[NUM_PADS];
int peak[NUM_PADS];
elapsedMillis sinceOnset[NUM_PADS];
elapsedMillis sinceOff[NUM_PADS];

void setup() {
#if !defined(__AVR__)
  analogReadResolution(12);          // ARM Teensy: 0..4095 (AVR is fixed 10-bit)
#endif
  pinMode(POWER_LED, OUTPUT);
  digitalWrite(POWER_LED, HIGH);     // on-board LED solid ON = powered / alive
  for (int p = 0; p < NUM_PADS; p++) {
    state[p] = ARMED;
    peak[p]  = 0;
    if (HIT_LED[p] >= 0) { pinMode(HIT_LED[p], OUTPUT); digitalWrite(HIT_LED[p], LOW); }
  }
}

int velocity(int adc) {
  int v = map(constrain(adc, THRESH, VEL_CEIL), THRESH, VEL_CEIL, VEL_MIN, 127);
  return constrain(v, 1, 127);
}

void hitLed(int p, bool on) {
  if (HIT_LED[p] >= 0) digitalWrite(HIT_LED[p], on ? HIGH : LOW);
}

void loop() {
  for (int p = 0; p < NUM_PADS; p++) {
    int val = analogRead(FSR_PIN[p]);

    switch (state[p]) {
      case ARMED:
        if (val >= THRESH) { peak[p] = val; sinceOnset[p] = 0; state[p] = PEAKING; }
        break;

      case PEAKING:
        if (val > peak[p]) peak[p] = val;
        if (sinceOnset[p] >= PEAK_MS) {
          usbMIDI.sendNoteOn(NOTE[p], velocity(peak[p]), CHANNEL);
          hitLed(p, true);                       // this pad's LED on while pressed
          state[p] = HELD;
        }
        break;

      case HELD:
        if (val <= RELEASE) {
          usbMIDI.sendNoteOff(NOTE[p], 0, CHANNEL);
          hitLed(p, false);
          sinceOff[p] = 0; state[p] = REFRACTORY;
        }
        break;

      case REFRACTORY:
        if (sinceOff[p] >= REFRAC_MS) state[p] = ARMED;
        break;
    }
  }

  usbMIDI.send_now();          // flush -> low latency
  while (usbMIDI.read()) {}    // drain incoming so the host stays happy
}
