# Game.com for Analogue Pocket

An openFPGA port of [Jamie Blanks' Game.com core for MiSTer](https://github.com/MiSTer-devel/GameCom_MiSTer), built on Analogue's core template. This is a development port; see [validation notes](docs/VALIDATION.md) for the checks actually completed.

## Install

Copy the contents of `release/` to the root of the Pocket SD card. The core is `jacob.GameCom` and the platform is `gamecom`.

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
| Hold L + D-pad | Move the touch cursor across the 12 × 10 grid |
| R, or L + A | Touch the screen at the cursor |
| Docked controller right stick | Move the touch cursor |

The core menu includes palette selection, the Game.com Power and Sound buttons, cold reset, and ejecting cartridge 2. Startup automatically supplies a short Game.com Power press.

The BIOS starts at the organizer home menu. From the initial touch-cursor position, hold L and tap Up twice, then Left three times; release L and press R to open Cartridge. For Lights Out, wait for the cartridge animation and press A at the copyright screen.

The core's approximately 75 Hz LCD scan feeds a buffered 60 Hz display mode. Three block-RAM framebuffers let capture continue while the display takes the latest completed frame at each refresh, without changing CPU or LCD scan timing. Pocket receives a 200 × 160 image with a 5:4 aspect ratio and 48 kHz mono audio in a stereo I2S stream. Modem/Internet connectivity is intentionally omitted. Pocket Memories capture CPU state, both video RAM banks and console RAM. Sleep and MiSTer cheat files are not exposed.

## Build and test

Quartus Prime Lite 18.1 with Cyclone V support is required. On macOS the build script automatically uses CrossOver's `Quartus` bottle; `CX_WINE`, `QUARTUS_BOTTLE` and `QUARTUS_EXE` can override the installation paths. A native `quartus_sh` on PATH is also supported.

```sh
bash sim/run.sh rom_tb
bash sim/run.sh bios_tb
bash sim/run.sh io_tb
bash sim/run.sh state_tb
bash sim/run.sh setup_tb
bash sim/run.sh dma_tb
bash sim/run.sh video_cadence_tb
bash sim/run.sh boot_tb +BIOS=/absolute/path/boot.rom +CART=/absolute/path/game.tgc
bash scripts/build.sh
python3 scripts/install.py /Volumes/Untitled --assets ~/Downloads/gamecom
```

The optional install `--assets` directory should contain `boot.rom`, `ROMS.zip`, and `memory.sav` or `boot1.vhd`. Existing saves and ROM files are preserved. Replaced core files are backed up under `build/sd-backup/`. Build outputs, generated build timestamps, and user-provided assets are excluded from Git. A fresh clone contains source and metadata; run the build script to create `release/` and the installable ZIP. Quartus regenerates `apf/build_id.mif` through its pre-flow script.

`build/jacob.GameCom_0.1.4.zip` contains the distribution, and `release/` is SD-ready. Use `src/fpga/output_files/ap_core.rbf` for JTAG with openFPGALoader; the SOF is also available for Intel's programmer. The packager reverses the bits **within each byte** of Quartus's RBF to produce the SD file `bitstream.rbf_r`. The metadata identity `author.shortname` must exactly match the `jacob.GameCom` core folder; the packager enforces this because Pocket derives its launch path from those fields.

For setup debugging, enable **Tools → Developer → Pause Core Boot** and **Debug Logging** on Pocket. Launch Game.com and leave it paused, then replace the volatile FPGA configuration using:

```sh
openFPGALoader -c usb-blaster --detect
openFPGALoader -c usb-blaster --write-sram src/fpga/output_files/ap_core.rbf
```

The tested JTAG reload programmed successfully but did not resume the core: the image froze and subsequent OS bridge commands timed out. Use SD installation and a fresh core launch for runtime testing until this reload issue is resolved. The documented APF procedure calls for pressing A after programming to continue setup and load assets, but that sequence has not worked on this port. Debug logs are saved in `/System/Logs/` on the SD card. JTAG programming does not install the core's JSON metadata or assets; install the SD package first. See Analogue's [debugging options](https://www.analogue.co/developer/docs/debugging-aids). With USB SD Access enabled, Analogue + X attaches the SD card to the Mac and Analogue + Y detaches it.

## Source and licensing

- Game.com RTL: MiSTer-devel/GameCom_MiSTer commit `96ed90ec865302d5eb5a0aa8336844dbfb4a5342`, copyright Jamie Blanks, GPL-2.0-or-later. Included in `src/fpga/rtl/` with upstream attribution.
- Pocket PSRAM controller: Adam Gastineau's [openfpga-SNES](https://github.com/agg23/openfpga-SNES) commit `ad9fed4e9cbeee56f624ffcffc6477b2908daa3d`, MIT license preserved in `src/fpga/pocket/psram.sv`.
- APF: [Analogue core template](https://github.com/open-fpga/core-template), supplied framework and Intel IP retain their original notices. The template README notice is preserved in [Analogue notice](docs/ANALOGUE_NOTICE.md).
- New Pocket integration: GPL-2.0-or-later.

Upstream edits parameterize the buffered video divider (30 MHz / 5 on Pocket instead of 60 MHz / 10), replace the two-buffer handoff with three framebuffers, add optional DMA ROM-ready waits for Pocket PSRAM, and compile out the unused MiSTer cheat engine on Pocket. The external BIOS uses Pocket SRAM. See [port architecture](docs/PORT.md).
