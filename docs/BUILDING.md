# Building and testing

## Requirements

- Quartus Prime Lite 18.1 with Cyclone V support. On macOS the build script uses CrossOver's `Quartus` bottle; `CX_WINE`, `QUARTUS_BOTTLE` and `QUARTUS_EXE` override the installation paths. A native `quartus_sh` on `PATH` is used if present.
- Verilator for the simulation benches.
- Python 3. `scripts/make_images.py` also needs Pillow.

## Simulation

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
```

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

This compiles the project and, only if the fit and every timing check pass, creates `release/` (ready to copy to an SD card) and `build/jacob.GameCom_<version>.zip`. A fresh clone contains source and metadata only. Build outputs, generated build timestamps and user-provided files are excluded from Git, and Quartus regenerates `apf/build_id.mif` through its pre-flow script.

The packager reverses the bits within each byte of Quartus's RBF to produce `bitstream.rbf_r`. It refuses to package if the sources changed during the compile, or if `author.shortname` in `core.json` does not match the `jacob.GameCom` core folder, because the Pocket derives its launch path from those fields.

`scripts/report_timing.tcl` writes the worst setup and hold paths, unconstrained paths and the mailbox net-delay results. Run it from `src/fpga` with `quartus_sta -t ../../scripts/report_timing.tcl`.

`scripts/make_images.py` rebuilds the platform image and core icon from the PNGs in `dist/art/`.

## Install to an SD card

```sh
python3 scripts/install.py /Volumes/Untitled --assets ~/Downloads/gamecom
```

The script copies the core and platform files, verifies each by hash, and backs up any file it replaces under `build/sd-backup/`. The optional `--assets` directory should contain `boot.rom`, `ROMS.zip`, and `memory.sav` or `boot1.vhd`; existing saves and ROM files on the card are never replaced.

## Debugging on a Pocket

Enable **Tools → Developer → Pause Core Boot** and **Debug Logging** on the Pocket. Debug logs are saved in `/System/Logs/` on the SD card. See Analogue's [debugging options](https://www.analogue.co/developer/docs/debugging-aids). With USB SD Access enabled, Analogue + X attaches the SD card to the computer and Analogue + Y detaches it.

`src/fpga/output_files/ap_core.rbf` can be loaded over JTAG with openFPGALoader (the SOF is for Intel's programmer):

```sh
openFPGALoader -c usb-blaster --detect
openFPGALoader -c usb-blaster --write-sram src/fpga/output_files/ap_core.rbf
```

JTAG programming does not install the core's JSON metadata or assets, so install the SD package first. In the one attempt recorded in the [validation record](VALIDATION.md), programming succeeded but the core did not resume: the image froze and later OS bridge commands timed out. Pressing A after programming, as Analogue's procedure describes, did not continue setup. Use an SD installation and a fresh core launch for runtime testing.
