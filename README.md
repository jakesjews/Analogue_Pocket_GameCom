# Game.com for Analogue Pocket

This openFPGA core runs Tiger Game.com cartridge images on the Analogue Pocket. It starts in the Game.com's own menu, and you work its touch screen with a cursor moved by the D-pad. It is a port of [Jamie Blanks' Game.com core for MiSTer](https://github.com/MiSTer-devel/GameCom_MiSTer) and is still in development.

**This port was developed with AI.** The Pocket integration, testbenches, build scripts and documentation were written by AI coding agents, including Anthropic's Claude, directed by Jacob Jewell, who tests the core on a real Analogue Pocket. The platform image and core icon were generated with OpenAI's image model through the Codex CLI. The Game.com emulation itself is Jamie Blanks' MiSTer core.

## What you need

- An Analogue Pocket.
- The latest zip from the [releases page](https://github.com/jakesjews/Analogue_Pocket_GameCom/releases).
- The Game.com external BIOS: a 262,144-byte file, `external.bin` in MAME's `gamecom` set. It is not included.
- Game.com cartridge images (`.tgc`). They are not included.

## Setup

1. Unzip the release onto the root of the Pocket's SD card.
2. Copy the BIOS into `Assets/gamecom/common/` and name it `boot.rom`.
3. Copy your `.tgc` files into `Assets/gamecom/common/`.
4. On the Pocket, open openFPGA, choose Game.com and pick a cartridge.
5. At the Game.com menu, hold L and press Up twice, then Left three times.
6. Release L and press R to open Cartridge.
7. Press A at the game's copyright screen.

To bring a save over from MiSTer, copy its `boot1.vhd` to `Saves/gamecom/common/gamecom.sav`.

## Controls

- D-pad: D-pad
- A, B, X, Y: A, B, C, D
- Start: Pause
- Select: Menu
- Hold L and use the D-pad: move the touch cursor
- R, or L + A: touch the screen at the cursor
- Right stick on a docked controller: move the touch cursor

The Pocket's Core Settings menu has the screen palette, the Game.com's Power and Sound buttons, a cold reset, and loading or ejecting a second cartridge.

## Good to know

- **All games share one save, as on the real console, and loading a Memory restores it too.** An old Memory puts every game's saves back to the moment it was made.
- `boot.rom` must be the 256 KB external BIOS. The 4 KB internal BIOS does not work in its place.
- Sleep, cheats and the Game.com's modem and link features are not supported.

## Status

- Checked on a Pocket, in version 0.1.3: the core starts, shows the Game.com menu, loads cartridges and the save, and games have clean graphics and sound. Motion looked jerky.
- Checked in simulation only so far: Memories, the LCD display modes, the second cartridge slot, the organizer clock, turning the Game.com back on with the buttons, and the frame pacing and cartridge speed changes made since 0.1.3.

## Troubleshooting

- The Pocket reports a missing file or a core setup error: check that `Assets/gamecom/common/boot.rom` exists and is exactly 262,144 bytes.
- A cartridge is refused: its size must be a power of two from 32 KB to 2 MB.
- The Game.com has turned itself off: press A, B, X, Y or Start, or use Game.com Power in Core Settings.

How the port works, how to build and test it, and the record of what has been checked are in [docs/](docs/).

## Credits and licensing

This port is built from the following work. Upstream copyright and license headers are kept in each file.

- **Game.com core** (`src/fpga/rtl/`): Jamie Blanks, [MiSTer-devel/GameCom_MiSTer](https://github.com/MiSTer-devel/GameCom_MiSTer) at commit `96ed90ec865302d5eb5a0aa8336844dbfb4a5342`. GPL-2.0, from the upstream `LICENSE`. Three files are modified for the Pocket; `docs/PORT.md` lists the changes.
- **Cheat engine** (`src/fpga/rtl/gamecom_cheat_engine.sv`, included but disabled): Jamie Blanks, following the MiSTer cheat-engine convention by Kitrinx. GPL-2.0.
- **Block RAM wrapper** (`src/fpga/rtl/Mem/bram.vhd`): a common MiSTer project file with no author recorded, shipped with GameCom_MiSTer. GPL-2.0.
- **PSRAM controller** (`src/fpga/pocket/psram.sv`, unmodified): Adam Gastineau, [agg23/openfpga-SNES](https://github.com/agg23/openfpga-SNES) at commit `ad9fed4e9cbeee56f624ffcffc6477b2908daa3d`. MIT; the notice is kept in the file.
- **openFPGA framework and core template** (`src/fpga/apf/`, `src/fpga/core/core_bridge_cmd.v`, and the template base of `core_top.v`, `core_constraints.sdc`, `ap_core.qpf` and `ap_core.qsf`): Analogue, [open-fpga/core-template](https://github.com/open-fpga/core-template). Analogue's template terms; its notice is kept in `docs/ANALOGUE_NOTICE.md`.
- **Quartus-generated IP and build-ID script** (`src/fpga/apf/mf_*`, `src/fpga/apf/build_id_gen.tcl`): Intel (Altera), supplied with the core template. Intel's license is in each file's header.
- **Pocket integration, test benches and scripts** (`src/fpga/pocket/` except `psram.sv`, the Pocket changes in `src/fpga/core/`, `sim/`, `scripts/`): Jacob Jewell, written with AI coding agents. GPL-2.0-or-later.
- **Platform image and core icon** (`dist/art/`, `dist/icon.bin`, `dist/platforms/_images/gamecom.bin`): generated with OpenAI's image model through the Codex CLI. GPL-2.0-or-later.

The upstream core's comments cite [MAME](https://github.com/mamedev/mame)'s Game.com (SM8500) driver as a hardware-behavior reference. No MAME code is included.

The combined work is distributed under the GNU General Public License, version 2; see [LICENSE](LICENSE). The BIOS and cartridge images are not included and are not covered by this license.
