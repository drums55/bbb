#!/bin/sh
# Follow the sensor service journal from your laptop.
# Usage:  tools/logs.sh [user@host]     (default: debian@192.168.7.2)
set -e
BBB="${1:-${BBB:-debian@192.168.7.2}}"
exec ssh -t "$BBB" 'journalctl -u fsr-midi -f -o cat'
