// fsr_midi_teensy.ino -- FSR pressure sensor -> USB-MIDI + hit LED, on a Teensy.
// Instant-on (no OS/boot): power the Teensy and it's a class-compliant USB-MIDI device.
// Matches the original BeagleBone rig: note 51 (D#3) on MIDI channel 1, LED lit while pressed.
//
// Arduino IDE setup:  Tools > Board > your Teensy  |  Tools > USB Type > "MIDI"  |  Upload.
// (Works on Teensy 3.x / LC / 4.x. `usbMIDI` exists only when USB Type includes MIDI.)
//
// Wiring -- FSR voltage divider off the 3.3 V rail (Teensy analog pins are 3.3 V, NOT 5 V!):
//     3V3 ---[ FSR402 ]---+--- A0        (FSR_PIN)
//                         +--- Rm ~22k --- GND
//     LED:  LED_PIN ---[ R 330-1k ]---|>|--- GND   (anode to R, cathode to GND)
// No clamp needed for an FSR (it's a resistor, no spikes). Meter A0: must stay <= 3.3 V.

const int FSR_PIN  = A0;   // FSR/Rm divider node
const int LED_PIN  = 2;    // hit LED (GPIO -> R -> LED -> GND)
const int NOTE     = 51;   // D#3  (original rig)
const int CHANNEL  = 1;    // MIDI channel 1..16 (original rig used ch 1)

// Trigger shaping in 12-bit ADC counts (0..4095). Old rig used normalized 0..1.0; the raw
// equivalents are noted (norm * 4095). Tune on the bench with the Serial print below.
const int THRESH    = 800;   // press onset          (old THRESHOLD 0.2 ~= 820)
const int RELEASE   = 400;   // note-off below this   (old RELEASE  0.1 ~= 410)
const int VEL_CEIL  = 1300;  // count that maps to velocity 127 (old rig railed ~norm 0.31)
const int VEL_MIN   = 20;    // softest accepted hit
const int PEAK_MS   = 7;     // track the peak this long, then send Note-On
const int REFRAC_MS = 35;    // debounce after a note-off

enum { ARMED, PEAKING, HELD, REFRACTORY } state = ARMED;
int peak = 0;
elapsedMillis sinceOnset, sinceOff;

void setup() {
  analogReadResolution(12);          // 0..4095
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
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
        digitalWrite(LED_PIN, HIGH);            // LED on while pressed ("hold")
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
