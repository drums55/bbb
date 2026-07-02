#!/bin/sh
# Live ADC calibration from your laptop: stops the service, streams raw counts, restarts on exit.
# Press the sensor and watch min/max to pick REST_MARGIN / VEL_CEIL in src/fsr_midi.py.
# Usage:  tools/tune.sh [user@host]     (default: debian@192.168.7.2)
set -e
BBB="${1:-${BBB:-debian@192.168.7.2}}"
echo "tuning on $BBB (service paused; Ctrl-C to stop + restart it)"
# shellcheck disable=SC2029
exec ssh -t "$BBB" 'sudo systemctl stop fsr-midi; \
    trap "sudo systemctl start fsr-midi" EXIT INT TERM; \
    python3 /opt/fsr-midi/fsr_midi.py --tune'
