# Validation record

This file records checks that were actually run, not intended capabilities.

## On a Pocket

The core is used on a Pocket from the SD card and works well there. No itemized hardware checklist is kept.

JTAG loading is the exception: openFPGALoader found the USB-Blaster (`09fb:6001`) and the Cyclone V (`5CE*A4`, IDCODE `02b050dd`, IR length 10) and loaded the RBF, but the image froze and the Pocket's log then showed an unresponsive core. Pressing A, as Analogue's procedure describes, did not continue setup.

## Simulation benches

All eight pass on the current sources (Verilator 5.052). `setup_tb` runs the real `core_top` and `core_bridge_cmd` with the PLL and data-table RAM modeled; the others drive the Pocket adapters or the upstream machine directly.

- `rom_tb`, cartridge loading and reads:
  - Two bursts totaling 1200 words cross the loader FIFO's wrap boundary into the PSRAM pin model without overflow and read back byte by byte, in both cartridge slots.
  - 3000 random-address reads with random gaps and sequential streams at and above CPU bus speed match the loaded pattern. Each address is presented one clock before readiness is checked, as the CPU does.
  - With every halfword cached, 3000 random reads wait 0 clocks, and so do reads after a Memories-style pause. A first-touch sequential stream of 1200 reads at CPU bus speed waits 7 clocks.
  - Reads during the post-reset sweep are served from PSRAM, and data reloaded over cached addresses is never returned stale, during or after the sweep.
- `bios_tb`: the SRAM model delays reads by 55 ns and checks write pulse widths. Two bursts cross the loader FIFO wrap, and 4804 byte reads, including the final BIOS word, match.
- `io_tb`:
  - The final NVRAM word is accessed from both ports in all four byte lanes.
  - Face buttons, touch movement and presses, cursor clamping through the thirteenth column, the right stick, and menu input suppression.
  - A face button produces a Power press only while the Game.com is stopped.
  - The I2S receiver reconstructs signed `1234` from offset-binary `9234`.
- `state_tb`: all 26,880 machine-state bytes round-trip through the APF staging buffer. Invalid headers and truncated transfers are rejected before any machine memory is written. A capture and a restore requested during reset are both answered with an error and never pause the machine, and a blob written during reset restores afterwards.
- `rtc_tb`: seeding from the host value, second-to-year carries, 29 February in a leap year and 28 February otherwise, and 2099 rolling to 2000.
- `setup_tb`:
  - Cartridge, BIOS and save requests are accepted or refused by slot and size, followed by the ready notification and the host reset commands.
  - Memories commands `00A0` and `00A4` sent while the host holds reset return result 3 instead of stalling the command handler.
  - Command `00B8` with the grayscale bit returns `444D` and selects the gray palette; a color mode releases it.
  - The Core Settings options are written as the Pocket writes them, byte-swapped. The palette is set, read back and restored, Power and Sound reach the key matrix, Cold Reset resets the machine and Eject Cartridge 2 ejects. A value of `0x01000000` (raw bit 0 set) triggers nothing.
- `dma_tb`: 13 transfers through the real CPU DMA, board decoding and VRAM, with all 8192 destination bytes compared against an independent pixel-copy model.
  - Cases: immediate and delayed ROM, aligned prefetch, all three unaligned source and destination phases, partial pixels, reverse X, multiple rows, VRAM-to-VRAM, RAM-to-VRAM and VRAM-to-RAM.
  - Waits covered: 120 initial-read beats, 394 next-byte beats and 120 overlapped-prefetch beats.
- `video_cadence_tb`: every native frame is numbered and every pixel carries its frame and coordinates, so mixed frames, wrong pixel order and incomplete 200 × 160 images are rejected.
  - In one second after warm-up, all 76 native frames are captured and all 60 output frames are new, with none repeated. The displayed frame number advances by one 45 times and by two 15 times.
  - Pausing and resuming the source recovers with no repeated frames after settling.
  - A presentation forced during output blanking in the same clock as a completed capture exercises the simultaneous handoff, and the three buffer roles stay distinct on every clock.
  - Both relative phases of the 20 and 30 MHz clocks pass.

## Full system in simulation

`boot_tb` runs the whole Pocket wrapper with the 55 ns SRAM model, the PSRAM pin model, the external BIOS from MAME's `gamecom` set and blank console memory. These runs predate the Core Settings fix, which changed only registers the bench does not use.

- The BIOS plays the Tiger intro and reaches the organizer menu, with every frame passing the 200 × 160 geometry check.
- Sonic Jam, Lights Out and Resident Evil 2 were each opened from the organizer menu to their copyright screen and started by pressing A. The captured frames are clean.
- Cartridge speed: in the 3 emulated seconds after pressing A, a cartridge read was not ready in 0.25% of non-halted CPU cycles in Sonic Jam, 0.61% in Lights Out and 0.39% in Resident Evil 2. These figures count the cache's one-clock lookup, which does not delay the CPU, so they overstate the waiting. With only a single halfword register in front of PSRAM the same scenes waited 5.50%, 15.70% and 13.49%.
- Memories: during Lights Out, a capture and a restore through the APF bridge restored the PC, both 8 KB VRAM banks and the 8 KB console RAM, compared while the machine was still paused. The game then continued with all frame checks passing.

Not covered:

- Playing through a game. The runs stop a few seconds after a game starts.
- Waking from STOP in the full system. With blank console memory the BIOS never executed STOP in 3 emulated seconds, at boot or at the organizer menu with Power held for 0.1, 0.6 or 2 seconds, so in simulation the wake path rests on `io_tb` and the upstream STOP-wake logic.

## Build and timing

Quartus Prime Lite 18.1.0 Build 625, device 5CEBA4F23C8. Resource use is in the [resource audit](RESOURCE_AUDIT.md).

- All 80 constrained timing groups pass across the four voltage and temperature models. Minimum slack: setup 0.540 ns, hold 0.116 ns, recovery 29.514 ns, removal 0.303 ns, pulse width 0.833 ns.
- The four mailbox net-delay bounds pass: ROM request address 2.382 ns of 5 ns, audio sample 1.523 ns of 5 ns, ROM data 2.670 ns of 20 ns, boot date and time 3.070 ns of 20 ns.
- Quartus's metastability report finds 133 synchronizer chains and a worst-case design MTBF of at least 1e9 years, with 11.3 ns worst available settling time. It could not calculate an MTBF for about a third of the chains.
- There are no illegal or unconstrained clocks. The APF bridge, scaler and audio interfaces and some memory hold paths have no external I/O constraints, so passing these checks is not board-level timing sign-off.
- The release zip contains only `Assets/gamecom/common/`, `Cores/jakesjews.GameCom/` and `Platforms/`. Nothing is placed at the SD card root.
