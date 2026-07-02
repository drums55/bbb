#!/usr/bin/env python3
"""
fsr_midi.py -- BeagleBone Black: read one FSR (Interlink FSR402) via the on-chip
ADC (IIO sysfs) and emit velocity-sensitive USB-MIDI notes through the g_midi gadget.

Design goals:
  * Fast start / tiny footprint -- default MIDI path writes raw bytes straight to the
    ALSA rawmidi node (/dev/snd/midiCxD0). ZERO third-party imports, so the process is
    live within a fraction of a second. (An optional python-rtmidi path is included but
    commented; the raw path is preferred.)
  * Decoupled from the gadget -- the g_midi kernel module (loaded early at boot) is what
    makes the host see the MIDI device. This script only pushes notes INTO that
    already-present port, so a late start never hides the device from the host.
  * One FSR -> one fixed note (LiveBox/Blackbox pad convention: note 36 = pad 1).

Wiring (ADC-safe, drive the divider from the 1.8 V rail so the pin can never exceed 1.8 V):
    P9_32 (VDD_ADC 1.8V) --- FSR402 ---+--- AINx  (e.g. P9_39 = AIN0)
                                       +--- Rm(~22k) --- P9_34 (AGND)

Tune the CONFIG block below on the bench, then run under systemd (see systemd/fsr-midi.service).
"""

import glob
import os
import sys
import time

# ----------------------------------------------------------------------------
# CONFIG -- edit these; everything else is generic.
# ----------------------------------------------------------------------------

# Which ADC channel the FSR is wired to (AIN0..AIN7 -> in_voltage0..in_voltage7).
ADC_CHAN = 0

# MIDI mapping. NOTE 36 = LiveBox/Blackbox pad 1. CHANNEL is 1-16; it MUST match the
# app's pads channel (_midiPadsChannel in player_screen.dart). 10 = GM-drums default.
NOTE = 36
CHANNEL = 10                 # 1..16 (human), converted to 0..15 on the wire below

# Trigger shaping (raw ADC counts, 0..4095 on the 12-bit AM335x ADC).
# THRESH is set relative to the measured resting level at startup (auto-calibrated).
REST_MARGIN = 60             # counts above rest to count as a "hit" onset
RELEASE_HYST = 30            # counts of hysteresis for the note-off (below THRESH-this)
VEL_CEIL = 3500              # ADC count that maps to full velocity (need not rail at 4095)
VEL_MIN = 20                 # velocity for the softest accepted hit
VEL_MAX = 127                # velocity ceiling
PEAK_WINDOW_MS = 7           # after onset, track the peak this long, then send NoteOn
REFRACTORY_MS = 35           # ignore new onsets this long after a note-off (debounce)

POLL_HZ = 1000               # sensor poll rate
RECAL_WHEN_IDLE_S = 2.0      # re-baseline the rest level after this long untouched

# MIDI output device. Leave "" to auto-detect the gadget rawmidi node.
MIDI_DEV = ""                # e.g. "/dev/snd/midiC1D0"

# ----------------------------------------------------------------------------
# Internals
# ----------------------------------------------------------------------------

IIO_RAW = "/sys/bus/iio/devices/iio:device0/in_voltage{}_raw".format(ADC_CHAN)
STATUS_ON = 0x90 | ((CHANNEL - 1) & 0x0F)
STATUS_OFF = 0x80 | ((CHANNEL - 1) & 0x0F)
POLL_DT = 1.0 / POLL_HZ


def find_midi_dev():
    """Return the gadget rawmidi node, or None if the host hasn't enumerated yet."""
    if MIDI_DEV:
        return MIDI_DEV if os.path.exists(MIDI_DEV) else None
    nodes = sorted(glob.glob("/dev/snd/midiC*D*"))
    return nodes[0] if nodes else None


def open_adc():
    """Open the IIO raw attribute once; we lseek+read it each sample (fresh value)."""
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
    """Raw-rawmidi writer that reopens on unplug/replug (ENODEV) without dying."""

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
            # host disconnected / node vanished -- drop and try again next event
            self.reopen()

    def note_on(self, note, vel):
        self.send((STATUS_ON, note & 0x7F, vel & 0x7F))

    def note_off(self, note):
        self.send((STATUS_OFF, note & 0x7F, 0))


def main():
    # Wait for the ADC to exist (systemd also gates on it, but be defensive).
    for _ in range(200):
        if os.path.exists(IIO_RAW):
            break
        time.sleep(0.05)
    else:
        sys.stderr.write("fsr-midi: {} not found -- is BB-ADC enabled?\n".format(IIO_RAW))
        return 1

    adc = open_adc()
    midi = MidiOut()

    # Auto-baseline the resting level (average a few samples).
    samples = []
    for _ in range(64):
        samples.append(read_adc(adc))
        time.sleep(0.001)
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

    while True:
        now = time.monotonic()
        val = read_adc(adc)

        if state == ARMED:
            if val >= thresh:
                state, peak, t_state = PEAKING, val, now
            else:
                # idle re-baseline so slow drift / temperature can't desensitise us
                if now - last_active > RECAL_WHEN_IDLE_S:
                    rest = (rest * 7 + val) // 8
                    thresh = rest + REST_MARGIN
                    release = thresh - RELEASE_HYST

        elif state == PEAKING:
            if val > peak:
                peak = val
            if now - t_state >= peak_window:
                midi.note_on(NOTE, scale_velocity(peak, thresh))
                state, t_state, last_active = HELD, now, now

        elif state == HELD:
            if val > peak:
                peak = val               # (peak kept for aftertouch later, if wanted)
            if val <= release:
                midi.note_off(NOTE)
                state, t_state, last_active = REFRACTORY, now, now

        elif state == REFRACTORY:
            if now - t_state >= refractory:
                state = ARMED

        time.sleep(POLL_DT)


# ----------------------------------------------------------------------------
# OPTIONAL robust backend (python-rtmidi). Uncomment to use instead of the raw path:
#
#   sudo apt-get install python3-rtmidi
#
# import rtmidi
# def open_rtmidi():
#     out = rtmidi.MidiOut()
#     for i, name in enumerate(out.get_ports()):
#         if "f_midi" in name.lower() or "gadget" in name.lower():
#             out.open_port(i); return out
#     out.open_virtual_port("BBB FSR"); return out
# ...then send with out.send_message([STATUS_ON, note, vel]).
# Slightly heavier import (~<1 s on BBB); nicer reconnection semantics.
# ----------------------------------------------------------------------------

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
