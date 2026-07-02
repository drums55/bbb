// fsr_midi_teensy.ino -- FSR pressure sensor -> USB-MIDI + hit LED, on a Teensy.
// Instant-on (no OS/boot): power the Teensy and it's a class-compliant USB-MIDI device.
// Matches the original BeagleBone rig: note 51 (D#3) on MIDI channel 1, LED lit while pressed.
//
// Arduino IDE setup:  Tools > Board > your Teensy  |  Tools > USB Type > "MIDI"  |  Upload.
// Portable across Teensy 2.0 (ATmega32U4, 5V, 10-bit ADC) and Teensy 3.x/4.x (3.3V, 12-bit).
//
// LEDs:
//   POWER_LED = on-board LED -> solid ON while powered (a "device is alive" indicator).
//   LED_PIN   = external hit LED -> lights while the sensor is pressed.
//
// ⚠️ Feed the FSR divider from the board's logic rail (Teensy 2.0 = VCC 5V; 3.x/4.x = 3V3):
//     VCC/3V3 ---[ FSR402 ]---+--- A0            (FSR_PIN)
//                             +--- Rm ~22k ------ GND
//     LED_PIN ---[ R 330-1k ]---|>|--- GND       (external hit LED: anode to R, cathode to GND)
// FSR is a resistor (no spikes) -> no clamp. Meter A0 at max press: must stay <= the rail.

const int FSR_PIN   = A0;          // silk "F0" on Teensy 2.0. Any analog pin works.
const int LED_PIN   = 0;           // external HIT LED. Teensy 2.0 silk "B0" = Arduino pin 0.
const int POWER_LED = LED_BUILTIN; // on-board LED = solid ON while powered (2.0=11, ++2.0=6).
const int NOTE      = 51;          // D#3  (original rig)
const int CHANNEL   = 1;           // MIDI channel 1..16 (original rig used ch 1)

// ADC full-scale differs by board; thresholds are fractions of it so they port unchanged.
#if defined(__AVR__)
  const int ADC_MAX = 1023;      // Teensy 2.0 (AVR): fixed 10-bit
#else
  const int ADC_MAX = 4095;      // Teensy 3.x/4.x: 12-bit (set in setup())
#endif
const int THRESH    = (int)(0.20 * ADC_MAX);  // press onset  (old THRESHOLD 0.2)
const int RELEASE   = (int)(0.10 * ADC_MAX);  // note-off     (old RELEASE  0.1)
const int VEL_CEIL  = (int)(0.22 * ADC_MAX);  // press count that maps to velocity 127. LOWER =
                                              // reach 127 with a lighter hit. Tune to YOUR hardest
                                              // press (see the tune note in WORKFLOW.md).
const int VEL_MIN   = 20;    // softest accepted hit
const int PEAK_MS   = 7;     // track the peak this long, then send Note-On
const int REFRAC_MS = 35;    // debounce after a note-off

enum { ARMED, PEAKING, HELD, REFRACTORY } state = ARMED;
int peak = 0;
elapsedMillis sinceOnset, sinceOff;

void setup() {
#if !defined(__AVR__)
  analogReadResolution(12);          // ARM Teensy: 0..4095 (AVR is fixed 10-bit)
#endif
  pinMode(POWER_LED, OUTPUT);
  digitalWrite(POWER_LED, HIGH);     // on-board LED solid ON = powered / alive
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);        // external hit LED off until pressed
}

int velocity(int p) {
  int v = map(constrain(p, THRESH, VEL_CEIL), THRESH, VEL_CEIL, VEL_MIN, 127);
  return constrain(v, 1, 127);
}

void loop() {
  int val = analogRead(FSR_PIN);

  switch (state) {
    case ARMED:
      if (val >= THRESH) { peak = val; sinceOnset = 0; state = PEAKING; }
      break;

    case PEAKING:
      if (val > peak) peak = val;
      if (sinceOnset >= PEAK_MS) {
        usbMIDI.sendNoteOn(NOTE, velocity(peak), CHANNEL);
        digitalWrite(LED_PIN, HIGH);            // hit LED on while pressed ("hold")
        state = HELD;
      }
      break;

    case HELD:
      if (val <= RELEASE) {
        usbMIDI.sendNoteOff(NOTE, 0, CHANNEL);
        digitalWrite(LED_PIN, LOW);
        sinceOff = 0; state = REFRACTORY;
      }
      break;

    case REFRACTORY:
      if (sinceOff >= REFRAC_MS) state = ARMED;
      break;
  }

  usbMIDI.send_now();          // flush -> low latency
  while (usbMIDI.read()) {}    // drain incoming so the host stays happy
}
