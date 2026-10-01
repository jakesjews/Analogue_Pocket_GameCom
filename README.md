# Game.com for Analogue Pocket

An openFPGA port of [Jamie Blanks' Game.com core for MiSTer](https://github.com/MiSTer-devel/GameCom_MiSTer), built on Analogue's core template. This is a development port; see [validation notes](docs/VALIDATION.md) for the checks actually completed.

**This port was developed with AI.** The Pocket integration, testbenches, build scripts and documentation were written by AI coding agents, including Anthropic's Claude, directed by Jacob Jewell, who tests the core on a real Analogue Pocket. The platform image and core icon were generated with OpenAI's image model through the Codex CLI. The Game.com emulation itself is Jamie Blanks' MiSTer core.

## Install

Unzip the release onto the root of the Pocket SD card; it only contains `Cores/`, `Platforms/` and `Assets/` folders. The core is `jacob.GameCom` and the platform is `gamecom`.

- Put the 262,144-byte external BIOS at `Assets/gamecom/common/boot.rom`.
- Put `.tgc` cartridge images in `Assets/gamecom/common/`.
- The console-wide 8 KB save is `Saves/gamecom/common/gamecom.sav`. An existing MiSTer `boot1.vhd` can be copied here. Saves are shared between games, like the original console.
- Launch Game.com from openFPGA and choose the first cartridge. Cartridge 2 can be loaded from the core menu.
- Exit the core through Analogue OS to write the console save to the SD card.

BIOS and game files are not included in the release. The internal BIOS is already represented by the upstream core's boot logic; do not load the 4 KB internal BIOS as `boot.rom`.

## Controls

| Pocket | Game.com |
| --- | --- |
| D-pad | D-pad |
| A / B / X / Y | A / B / C / D |
| Start | Pause |
| Select | Menu |
| Hold L + D-pad | Move the touch cursor across the 13 × 10 grid |
| R, or L + A | Touch the screen at the cursor |
| Docked controller right stick | Move the touch cursor |
| A / B / X / Y or Start while the Game.com is off | Power (turn it on) |

The core menu includes palette selection, the Game.com Power and Sound buttons, cold reset, and ejecting cartridge 2. Startup automatically supplies a short Game.com Power press. If the Game.com turns itself off, the screen asks for Power, as on the real console. Press A, B, X, Y or Start, or use Game.com Power in the core menu, to turn it back on.

The BIOS starts at the organizer home menu. From the initial touch-cursor position, hold L and tap Up twice, then Left three times; release L and press R to open Cartridge. For Lights Out, wait for the cartridge animation and press A at the copyright screen.

The core's approximately 75 Hz LCD scan feeds a buffered 60 Hz display mode. Three block-RAM framebuffers let capture continue while the display takes the latest completed frame at each refresh, without changing CPU or LCD scan timing. Pocket receives a 200 × 160 image with a 5:4 aspect ratio and 48 kHz mono audio in a stereo I2S stream. Analogue OS display modes are available: Grayscale LCD, Reflective Color LCD and Backlit Color LCD. While Grayscale LCD is selected the core outputs its grayscale palette, which that mode requires. Modem/Internet connectivity is intentionally omitted. Sleep and MiSTer cheat files are not exposed.

Pocket Memories capture CPU state, both video RAM banks and console RAM. Every Game.com game saves into that console RAM, so loading a Memory also returns all games' saves to the moment it was made, and that is what is written to `gamecom.sav` when you exit. The organizer clock is set from the Pocket's clock at launch, and a cold reset or cartridge eject picks up the current time.

## Build and test

Quartus Prime Lite 18.1 with Cyclone V support is required. On macOS the build script automatically uses CrossOver's `Quartus` bottle; `CX_WINE`, `QUARTUS_BOTTLE` and `QUARTUS_EXE` can override the installation paths. A native `quartus_sh` on PATH is also supported.

```sh
bash sim/run.sh rom_tb
bash sim/run.sh bios_tb
bash sim/run.sh io_tb
bash sim/run.sh state_tb
bash sim/run.sh rtc_tb
bash sim/run.sh setup_tb
bash sim/run.sh dma_tb
bash sim/run.sh video_cadence_tb
bash sim/run.sh boot_tb +BIOS=/absolute/path/boot.rom +CART=/absolute/path/game.tgc
bash scripts/build.sh
python3 scripts/install.py /Volumes/Untitled --assets ~/Downloads/gamecom
```

The optional install `--assets` directory should contain `boot.rom`, `ROMS.zip`, and `memory.sav` or `boot1.vhd`. Existing saves and ROM files are preserved. Replaced core files are backed up under `build/sd-backup/`. Build outputs, generated build timestamps, and user-provided assets are excluded from Git. A fresh clone contains source and metadata; run the build script to create `release/` and the installable ZIP. Quartus regenerates `apf/build_id.mif` through its pre-flow script.

`build/jacob.GameCom_<version>.zip` contains the distribution, and `release/` is SD-ready. Use `src/fpga/output_files/ap_core.rbf` for JTAG with openFPGALoader; the SOF is also available for Intel's programmer. The packager reverses the bits **within each byte** of Quartus's RBF to produce the SD file `bitstream.rbf_r`. The metadata identity `author.shortname` must exactly match the `jacob.GameCom` core folder; the packager enforces this because Pocket derives its launch path from those fields.

For setup debugging, enable **Tools → Developer → Pause Core Boot** and **Debug Logging** on Pocket. Launch Game.com and leave it paused, then replace the volatile FPGA configuration using:

```sh
openFPGALoader -c usb-blaster --detect
openFPGALoader -c usb-blaster --write-sram src/fpga/output_files/ap_core.rbf
```

The tested JTAG reload programmed successfully but did not resume the core: the image froze and subsequent OS bridge commands timed out. Use SD installation and a fresh core launch for runtime testing until this reload issue is resolved. The documented APF procedure calls for pressing A after programming to continue setup and load assets, but that sequence has not worked on this port. Debug logs are saved in `/System/Logs/` on the SD card. JTAG programming does not install the core's JSON metadata or assets; install the SD package first. See Analogue's [debugging options](https://www.analogue.co/developer/docs/debugging-aids). With USB SD Access enabled, Analogue + X attaches the SD card to the Mac and Analogue + Y detaches it.

## Changes to upstream code

Three upstream files are modified; the other upstream files in `src/fpga/rtl/` are byte-identical to commit `96ed90e`.

- `gamecom.v` passes three new parameters (`VIDEO_DIV`, `DMA_ROM_WAIT`, `ENABLE_CHEATS`) down to the CPU and video blocks. Their defaults preserve upstream behavior. It also exposes the CPU's STOP state as `cpu_stopped_o`, so the Pocket buttons can turn the Game.com back on.
- `sm8521.v` adds optional DMA ROM-ready waits for Pocket PSRAM (`DMA_ROM_WAIT`) and lets the unused MiSTer cheat engine be compiled out (`ENABLE_CHEATS=0` on Pocket).
- `gamecom_video.v` parameterizes the buffered video divider (30 MHz / 5 on Pocket instead of 60 MHz / 10) and replaces the two-buffer handoff with three framebuffers. The three-framebuffer change is not behind a parameter.

The external BIOS uses Pocket SRAM. See [port architecture](docs/PORT.md).

## Credits and licensing

This port is built from the following work. Upstream copyright and license headers are kept in each file.

| Component | Files in this repository | Author | Source | License |
| --- | --- | --- | --- | --- |
| Game.com core: SM8521 CPU, video, sound, timers, input, open boot-ROM stub, power-off logo, cache RAM | `src/fpga/rtl/` | Jamie Blanks | [MiSTer-devel/GameCom_MiSTer](https://github.com/MiSTer-devel/GameCom_MiSTer), commit `96ed90ec865302d5eb5a0aa8336844dbfb4a5342` | GPL-2.0 (upstream `LICENSE`) |
| Cheat engine (included but disabled on Pocket) | `src/fpga/rtl/gamecom_cheat_engine.sv` | Jamie Blanks, following the MiSTer cheat-engine convention by Kitrinx | GameCom_MiSTer, same commit | GPL-2.0 |
| Block RAM wrapper | `src/fpga/rtl/Mem/bram.vhd` | MiSTer project common file; no author in the file | Shipped with GameCom_MiSTer, same commit | GPL-2.0 |
| PSRAM controller | `src/fpga/pocket/psram.sv` (unmodified) | Adam Gastineau | [agg23/openfpga-SNES](https://github.com/agg23/openfpga-SNES), commit `ad9fed4e9cbeee56f624ffcffc6477b2908daa3d` | MIT, notice kept in the file |
| openFPGA framework and core template | `src/fpga/apf/`, `src/fpga/core/core_bridge_cmd.v`, and the template base of `core_top.v`, `core_constraints.sdc` and `ap_core.qpf`/`.qsf` | Analogue | [open-fpga/core-template](https://github.com/open-fpga/core-template) | Analogue's template terms; notice kept in [Analogue notice](docs/ANALOGUE_NOTICE.md) |
| Quartus-generated IP and build-ID script | `src/fpga/apf/mf_*`, `src/fpga/apf/build_id_gen.tcl` | Intel (Altera) | Supplied with the core template | Intel/Altera license in each file's header |
| Pocket integration, simulation benches and build scripts | `src/fpga/pocket/` (except `psram.sv`), Pocket changes to `src/fpga/core/`, `sim/`, `scripts/` | Jacob Jewell, written with AI coding agents | This repository | GPL-2.0-or-later |
| Platform image and core icon | `dist/art/`, `dist/icon.bin`, `dist/platforms/_images/gamecom.bin` | Generated with OpenAI's image model through the Codex CLI | This repository | GPL-2.0-or-later |

The upstream core's comments cite [MAME](https://github.com/mamedev/mame)'s Game.com (SM8500) driver as a hardware-behavior reference. No MAME code is included.

The combined work is distributed under the GNU General Public License, version 2; see [LICENSE](LICENSE). The BIOS and cartridge images are not included and are not covered by this license.
