#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/src/fpga"
mkdir -p "$ROOT/build/sim"
TOP=${1:-rom_tb}
EXTRA_SOURCES=()
if [[ "$TOP" == setup_tb ]]; then
    EXTRA_SOURCES=(core/core_top.v core/core_bridge_cmd.v apf/common.v)
fi
verilator --binary --timing -DSYNTHESIS -j 8 -Wno-fatal --top-module "$TOP" \
 --Mdir "$ROOT/build/sim/$TOP" -o run \
 "$ROOT/sim/$TOP.sv" "$ROOT/sim/psram_model.sv" "$ROOT/sim/sram_model.sv" "${EXTRA_SOURCES[@]}" \
 pocket/pocket_gamecom.sv pocket/pocket_rom.sv pocket/pocket_bios.sv pocket/psram.sv pocket/pocket_save_ram.sv \
 pocket/pocket_input.sv pocket/pocket_rtc.sv pocket/pocket_video.sv pocket/pocket_audio.sv pocket/pocket_state.sv \
 rtl/gamecom.v rtl/gamecom_audio_output.v rtl/gamecom_input.v rtl/gamecom_video.v \
 rtl/sm8521.v rtl/sm8521_boot_rom.v rtl/Mem/cache_ram.v rtl/gamecom_cheat_engine.sv \
 > "$ROOT/build/sim/$TOP-build.log" 2>&1
shift || true
"$ROOT/build/sim/$TOP/run" "$@" | tee "$ROOT/build/sim/$TOP-result.log"
