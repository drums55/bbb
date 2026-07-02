#!/bin/sh
# Push the working copy from your laptop to the board and restart the service.
# Usage:  tools/deploy.sh [user@host]      (default: debian@192.168.7.2 = USB-net dev gadget)
#   BBB=debian@bbb.local  tools/deploy.sh   # or set the BBB env var / pass an arg
set -e
BBB="${1:-${BBB:-debian@192.168.7.2}}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "deploy -> $BBB"
# rsync if present (fast, only changed bytes); else scp.
if command -v rsync >/dev/null 2>&1; then
    rsync -az "$REPO/src/fsr_midi.py" "$BBB:/tmp/fsr_midi.py"
else
    scp "$REPO/src/fsr_midi.py" "$BBB:/tmp/fsr_midi.py"
fi
# shellcheck disable=SC2029
ssh "$BBB" 'sudo install -m0755 /tmp/fsr_midi.py /opt/fsr-midi/fsr_midi.py \
            && sudo systemctl restart fsr-midi \
            && systemctl --no-pager -l status fsr-midi | head -n 6'
echo "done. logs:  tools/logs.sh $BBB"
