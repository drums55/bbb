#!/usr/bin/env python3
"""
fsr_midi.py -- BeagleBone Black: read one FSR402 pressure sensor via the on-chip
ADC (IIO sysfs) and emit velocity-sensitive USB-MIDI notes through the g_midi gadget.

Design goals
------------
* Fast start / tiny footprint. The MIDI path writes raw bytes straight to the ALSA
  rawmidi node (/dev/snd/midiC*D*). ZERO third-party imports -> the process is live in a
  fraction of a second, nothing to pip-install, nothing heavy to import. (An optional
  python-rtmidi backend is included at the bottom, commented out; the raw path is preferred.)
* Decoupled from the gadget. The g_midi kernel module -- loaded early at boot -- is what
  makes the host enumerate the MIDI device. This script only pushes notes INTO that
  already-present port, so a late/paused script never hides the device from the host.
* One FSR -> one fixed note. LiveBox/blackbox pad convention: note 36 = pad 1.
* FSR (not piezo) trigger shape: a *sustained pressure* level, not a transient spike.
  Auto-baseline the rest level, fire on a threshold crossing, hold while pressed, release
  on the way down with hysteresis + a refractory debounce.

Wiring (ADC-safe -- drive the divider from the 1.8 V rail so the pin can never exceed 1.8 V):

    P9_32 (VDD_ADC 1.8V) --[ FSR402 ]--+--> AINx  (e.g. P9_39 = AIN0)  -> in_voltage0_raw
                                       |
                                    [ Rm ~22k ]
                                       |
                                    P9_34 (AGND)

See docs/hardware.md for pin map + Rm sizing. Tune the CONFIG block on the bench, then run
under systemd (systemd/fsr-midi.service).
"""

import glob
import os
import sys
import time

# ---------------------------------------------------------------------------
# CONFIG -- edit these on the bench; everything below is generic.
# ---------------------------------------------------------------------------

# Which ADC channel the FSR is wired to (AIN0..AIN6 -> in_voltage0..in_voltage6_raw).
ADC_CHAN = 0

# MIDI mapping. NOTE 36 = LiveBox/blackbox pad 1. CHANNEL is 1..16 (human); it MUST equal
# the app's pads channel (_midiPadsChannel in LiveBox). 10 = GM-drums default on both.
NOTE = 36
CHANNEL = 10

# Trigger shaping, in raw ADC counts (0..4095 on the 12-bit AM335x ADC). THRESH is derived
# from the resting level measured at startup (auto-calibrated), not hard-coded.
REST_MARGIN = 60         # counts above rest that count as a "hit" onset
RELEASE_HYST = 30        # note-off once the value falls below (THRESH - this)
VEL_CEIL = 3500          # ADC count that maps to full velocity (need not rail at 4095)
VEL_MIN = 20             # velocity for the softest accepted hit
VEL_MAX = 127            # velocity ceiling
PEAK_WINDOW_MS = 7       # after onset, track the peak this long, then send Note-On
REFRACTORY_MS = 35       # ignore new onsets this long after a note-off (debounce)

POLL_HZ = 1000           # sensor poll rate
RECAL_WHEN_IDLE_S = 2.0  # re-baseline the rest level after this long untouched (drift/creep)

# MIDI output node. Leave "" to auto-detect the gadget rawmidi node.
MIDI_DEV = ""            # e.g. "/dev/snd/midiC1D0"

# LED-on-hit (matches the original rig: an LED flashes when you press). Driven via zero-dep
# sysfs GPIO. Wire: GPIO pin -> series R (~330-1k) -> LED -> GND (see docs/hardware.md).
LED_ENABLE = True
LED_GPIO = 48            # sysfs gpio number. 48 = P9_15 (GPIO1_16). *** CHANGE to your pin ***
LED_MODE = "hold"        # "hold" = lit while pressed; "flash" = a brief blink per hit
LED_FLASH_MS = 40        # flash length when LED_MODE == "flash"
LED_ACTIVE_HIGH = True   # True: GPIO high = LED on (GPIO->R->LED->GND). False if wired to 3.3V.

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

IIO_RAW = "/sys/bus/iio/devices/iio:device0/in_voltage{}_raw".format(ADC_CHAN)
STATUS_ON = 0x90 | ((CHANNEL - 1) & 0x0F)
STATUS_OFF = 0x80 | ((CHANNEL - 1) & 0x0F)
POLL_DT = 1.0 / POLL_HZ
VERBOSE = False          # set by --verbose: log every note on/off to the journal


def find_midi_dev():
    """Return the gadget rawmidi node, or None if the host hasn't enumerated yet."""
    if MIDI_DEV:
        return MIDI_DEV if os.path.exists(MIDI_DEV) else None
    nodes = sorted(glob.glob("/dev/snd/midiC*D*"))
    return nodes[0] if nodes else None


def open_adc():
    """Open the IIO raw attribute once; lseek+read it each sample for a fresh value."""
    return os.open(IIO_RAW, os.O_RDONLY)


def read_adc(fd):
    os.lseek(fd, 0, os.SEEK_SET)
    return int(os.read(fd, 16).strip() or b"0")


def scale_velocity(peak, thresh):
    span = max(1, VEL_CEIL - thresh)
    frac = (peak - thresh) / span
    if frac < 0.0:
        frac = 0.0
    if frac > 1.0:
        frac = 1.0
    return int(VEL_MIN + frac * (VEL_MAX - VEL_MIN))


class MidiOut:
    """Raw-rawmidi writer that reopens on host unplug/replug (ENODEV) without dying."""

    def __init__(self):
        self.fd = None
        self.reopen()

    def reopen(self):
        if self.fd is not None:
            try:
                os.close(self.fd)
            except OSError:
                pass
            self.fd = None
        dev = find_midi_dev()
        if dev:
            try:
                self.fd = os.open(dev, os.O_WRONLY)
                sys.stderr.write("fsr-midi: MIDI out -> {}\n".format(dev))
            except OSError:
                self.fd = None

    def send(self, data):
        if self.fd is None:
            self.reopen()
            if self.fd is None:
                return
        try:
            os.write(self.fd, bytes(data))
        except OSError:
            # host disconnected / node vanished -- drop it and retry on the next event
            self.reopen()

    def note_on(self, note, vel):
        self.send((STATUS_ON, note & 0x7F, vel & 0x7F))

    def note_off(self, note):
        self.send((STATUS_OFF, note & 0x7F, 0))


class Led:
    """Zero-dep GPIO LED via legacy sysfs. No-ops (never crashes the trigger) if the pin
    can't be exported -- e.g. wrong number or not muxed as GPIO. (libgpiod is the modern
    alternative but needs an apt package; sysfs keeps us dependency-free.)"""

    def __init__(self, gpio, active_high=True):
        self.ok = False
        self.active_high = active_high
        self.val = None
        if not LED_ENABLE:
            return
        base = "/sys/class/gpio/gpio{}".format(gpio)
        try:
            if not os.path.exists(base):
                with open("/sys/class/gpio/export", "w") as f:
                    f.write(str(gpio))
            with open(base + "/direction", "w") as f:
                f.write("out")
            self.val = open(base + "/value", "w")
            self.ok = True
            self.set(False)
            sys.stderr.write("fsr-midi: LED on gpio{} ({})\n".format(gpio, LED_MODE))
        except OSError as e:
            sys.stderr.write("fsr-midi: LED gpio{} unavailable ({}) -- running without LED\n"
                             .format(gpio, e))

    def set(self, on):
        if not self.ok:
            return
        physical = on if self.active_high else (not on)
        try:
            self.val.seek(0)
            self.val.write("1" if physical else "0")
            self.val.flush()
        except OSError:
            self.ok = False


def main():
    # Be defensive: wait (bounded) for the ADC/IIO node in case the DT overlay is late.
    # The systemd unit orders us after sysinit.target so this normally passes immediately.
    for _ in range(200):                      # up to ~10 s
        if os.path.exists(IIO_RAW):
            break
        time.sleep(0.05)
    else:
        sys.stderr.write("fsr-midi: {} not found -- is BB-ADC enabled?\n".format(IIO_RAW))
        return 1

    adc = open_adc()
    midi = MidiOut()
    led = Led(LED_GPIO, LED_ACTIVE_HIGH)

    # Auto-baseline the resting level (average a handful of samples).
    samples = [read_adc(adc) for _ in range(64)]
    rest = sum(samples) // len(samples)
    thresh = rest + REST_MARGIN
    release = thresh - RELEASE_HYST
    sys.stderr.write("fsr-midi: rest={} thresh={} note={} ch={}\n".format(
        rest, thresh, NOTE, CHANNEL))

    ARMED, PEAKING, HELD, REFRACTORY = 0, 1, 2, 3
    state = ARMED
    peak = 0
    t_state = time.monotonic()
    last_active = time.monotonic()
    peak_window = PEAK_WINDOW_MS / 1000.0
    refractory = REFRACTORY_MS / 1000.0
    led_flash = LED_FLASH_MS / 1000.0
    led_off_at = 0.0                          # for LED_MODE == "flash"

    while True:
        now = time.monotonic()
        val = read_adc(adc)

        # LED "flash" mode: auto-extinguish after the flash window, independent of hold.
        if led_off_at and now >= led_off_at:
            led.set(False)
            led_off_at = 0.0

        if state == ARMED:
            if val >= thresh:
                state, peak, t_state = PEAKING, val, now
            elif now - last_active > RECAL_WHEN_IDLE_S:
                # slow re-baseline so temperature / FSR creep can't desensitise us
                rest = (rest * 7 + val) // 8
                thresh = rest + REST_MARGIN
                release = thresh - RELEASE_HYST

        elif state == PEAKING:
            if val > peak:
                peak = val
            if now - t_state >= peak_window:
                vel = scale_velocity(peak, thresh)
                midi.note_on(NOTE, vel)
                led.set(True)
                if LED_MODE == "flash":
                    led_off_at = now + led_flash
                if VERBOSE:
                    sys.stderr.write("fsr-midi: NOTE-ON  {} vel={} (peak={})\n"
                                     .format(NOTE, vel, peak))
                state, t_state, last_active = HELD, now, now

        elif state == HELD:
            if val > peak:
                peak = val                    # kept for optional aftertouch later
            if val <= release:
                midi.note_off(NOTE)
                if LED_MODE == "hold":
                    led.set(False)
                if VERBOSE:
                    sys.stderr.write("fsr-midi: NOTE-OFF {}\n".format(NOTE))
                state, t_state, last_active = REFRACTORY, now, now

        elif state == REFRACTORY:
            if now - t_state >= refractory:
                state = ARMED

        time.sleep(POLL_DT)


def tune():
    """Calibration/debug mode (no MIDI): stream live ADC so you can pick thresholds.
    Run on the board:  python3 fsr_midi.py --tune   (Ctrl-C to stop). Press the sensor and
    watch the numbers -- set REST_MARGIN a bit above the resting noise, VEL_CEIL near the
    hardest-slap peak."""
    for _ in range(200):
        if os.path.exists(IIO_RAW):
            break
        time.sleep(0.05)
    else:
        sys.stderr.write("fsr-midi --tune: {} not found -- is BB-ADC enabled?\n".format(IIO_RAW))
        return 1
    adc = open_adc()
    base = [read_adc(adc) for _ in range(64)]
    rest = sum(base) // len(base)
    lo = hi = read_adc(adc)
    sys.stdout.write("tuning {}  (ADC_CHAN={})  rest~{}  -- press the sensor; Ctrl-C to stop\n"
                     .format(IIO_RAW, ADC_CHAN, rest))
    sys.stdout.write("suggest: REST_MARGIN ~ noise+20, VEL_CEIL ~ hardest peak below 4095\n\n")
    last = 0.0
    while True:
        v = read_adc(adc)
        lo = min(lo, v)
        hi = max(hi, v)
        now = time.monotonic()
        if now - last >= 0.1:                 # ~10 Hz print, readable in a terminal
            bar = "#" * min(50, v * 50 // 4095)
            sys.stdout.write("\rcur={:4d}  rest={:4d}  min={:4d}  max={:4d}  |{:<50}|"
                             .format(v, rest, lo, hi, bar))
            sys.stdout.flush()
            last = now
        time.sleep(0.002)


# ---------------------------------------------------------------------------
# OPTIONAL robust backend (python-rtmidi). Nicer reconnection semantics, but a slightly
# heavier import (~<1 s on the BBB) and an apt dependency. To use instead of the raw path:
#
#   sudo apt-get install python3-rtmidi
#
# import rtmidi
# def open_rtmidi():
#     out = rtmidi.MidiOut()
#     for i, name in enumerate(out.get_ports()):
#         if "f_midi" in name.lower() or "gadget" in name.lower():
#             out.open_port(i); return out
#     return out.open_virtual_port("BBB FSR")   # fallback
# ...then send with out.send_message([STATUS_ON, note, vel]).
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    try:
        if "--tune" in sys.argv:
            sys.exit(tune())
        VERBOSE = "--verbose" in sys.argv or "-v" in sys.argv
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stdout.write("\n")
