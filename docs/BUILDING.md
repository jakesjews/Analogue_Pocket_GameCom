# Building and testing

## Requirements

- Quartus Prime Lite 18.1 with Cyclone V support. A native `quartus_sh` on `PATH` is used if present; otherwise the build script runs Quartus in CrossOver's `Quartus` bottle on macOS. `CX_WINE`, `QUARTUS_BOTTLE` and `QUARTUS_EXE` override the paths.
- Verilator for the simulation benches.
- Python 3. `scripts/make_images.py` also needs Pillow.

## Simulation

```sh
for tb in rom_tb bios_tb io_tb state_tb rtc_tb setup_tb dma_tb video_cadence_tb; do
    bash sim/run.sh $tb
done
bash sim/run.sh boot_tb +BIOS=/absolute/path/boot.rom +CART=/absolute/path/game.tgc
```

What each bench covers is in the [validation record](VALIDATION.md).

`boot_tb` runs the whole Pocket wrapper with a real BIOS and cartridge. Its options:

- `+SAVE=file` loads an 8 KB console save.
- `+RUN_MS=n` sets the emulated run time, and `+OUT=file.ppm` the final frame.
- `+STATE_OUT=file` saves a Memories checkpoint at the end; `+STATE_IN=file` resumes one.
- `+LAUNCH_CART` opens Cartridge from the organizer menu; `+PRESS_KEY=hex` presses Pocket buttons.
- `+MEMORIES` captures and restores a live Memory and checks the result.
- `+FRAME_PREFIX=path` writes a frame each emulated second.
- `+TRACE=file` lists every cartridge access as a halfword address.

It prints the share of CPU cycles spent waiting for cartridge ROM. With blank console memory the BIOS needs about nine emulated seconds to reach its menu, so game tests are built from checkpoints.

## Build and package

```sh
bash scripts/build.sh
```

This compiles the project and, only if the fit and every timing check pass, creates `release/` (ready to copy to an SD card) and `build/jakesjews.GameCom_<version>.zip`. Build outputs and user-provided files are not in Git, and Quartus regenerates `apf/build_id.mif` in its pre-flow script.

The packager reverses the bits within each byte of Quartus's RBF to produce `bitstream.rbf_r`. It refuses to package if the sources changed during the compile, or if `author` and `shortname` in `core.json` do not match the `jakesjews.GameCom` core folder, because the Pocket derives its launch path from those fields.

Other scripts:

- `scripts/report_timing.tcl` writes the worst setup and hold paths, unconstrained paths and the mailbox net-delay results. Run it from `src/fpga` with `quartus_sta -t ../../scripts/report_timing.tcl`.
- `scripts/audit_registers.tcl` counts the register arrays listed in the [resource audit](RESOURCE_AUDIT.md). Run it the same way.
- `scripts/make_images.py` rebuilds the platform image and core icon from the PNGs in `dist/art/`.

## Install to an SD card

```sh
python3 scripts/install.py /Volumes/Untitled --assets ~/Downloads/gamecom
```

The script copies the core and platform files, verifies each by hash, and backs up any file it replaces under `build/sd-backup/`. The optional `--assets` directory should contain `boot.rom`, `ROMS.zip`, and `memory.sav` or `boot1.vhd`; existing saves and ROM files on the card are never replaced.

## Debugging on a Pocket

Enable **Tools → Developer → Pause Core Boot** and **Debug Logging** on the Pocket. Logs are saved in `/System/Logs/` on the SD card. See Analogue's [debugging options](https://www.analogue.co/developer/docs/debugging-aids). With USB SD Access enabled, Analogue + X attaches the SD card to the computer and Analogue + Y detaches it.

`src/fpga/output_files/ap_core.rbf` can be loaded over JTAG with openFPGALoader, which takes the RBF rather than the SOF:

```sh
openFPGALoader -c usb-blaster --detect
openFPGALoader -c usb-blaster --write-sram src/fpga/output_files/ap_core.rbf
```

**JTAG is not a way to test the running core.** It does not install the core's JSON metadata or assets, and in the one attempt made, programming succeeded but the image froze and the Pocket's bridge commands timed out. Install to the SD card and launch the core from the menu instead.
