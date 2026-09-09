#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build"
python3 "$ROOT/scripts/package.py" --record-sources
cd "$ROOT/src/fpga"
if command -v quartus_sh >/dev/null 2>&1; then
    quartus_sh --flow compile ap_core 2>&1 | tee "$ROOT/build/quartus.log"
else
    CX_WINE=${CX_WINE:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine}
    QUARTUS_EXE=${QUARTUS_EXE:-C:\\intelFPGA_lite\\18.1\\quartus\\bin64\\quartus_sh.exe}
    "$CX_WINE" --bottle "${QUARTUS_BOTTLE:-Quartus}" "$QUARTUS_EXE" \
        --flow compile ap_core 2>&1 | tee "$ROOT/build/quartus.log"
fi
python3 "$ROOT/scripts/package.py"
