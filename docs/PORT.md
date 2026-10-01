# Port architecture

The MiSTer `emu`, HPS I/O, DDR3 save-state storage, scandoubler, SDRAM controller, UART routing, and OS menu are replaced by the Analogue template's `core_top` and the adapters in `src/fpga/pocket/`.

The SM8521 CPU and Game.com board use upstream RTL with the optional DMA wait adaptation described below; the display converter has the framebuffer handoff adaptation described here. The 20 MHz system clock provides alternating 5 MHz phi0/phi1 enables. The CPU's native LCD fetch runs unchanged; the buffered raster uses 30 MHz / 5 = 6 MHz. All pixels, sync levels and framebuffer swaps originate from `gamecom_video`.

The 60 Hz converter uses three 32K × 3-bit block-RAM framebuffers. Their write, latest-complete and display roles are managed entirely on the video clock, which already clocks both RAM ports. Every complete native frame becomes the latest candidate; if the display has not taken the previous candidate, that old candidate becomes the next write buffer. At output vblank the display takes the latest complete candidate and releases its old buffer. Simultaneous completion and presentation select the just-completed frame. The three roles always refer to distinct buffers, and presentation never changes the buffer during active output.

This removes the two-buffer acknowledgement stall, which delivered only 44 fresh frames across 60 output frames in the one-second regression. The revised converter delivers 60 fresh frames, capturing all 76 native frames that ended in that measurement window. Conversion from approximately 75 Hz to 60 Hz still skips some source frames; it does not change the emulated CPU/LCD rate or increase a game's own animation rate.

| APF bridge bytes | Contents | Backing storage |
| --- | --- | --- |
| `00000000–001fffff` | Cartridge 1, max 2 MB | `000000–1fffff` |
| `10000000–1003ffff` | External BIOS, 256 KB | SRAM, 256 KB |
| `20000000–201fffff` | Cartridge 2, max 2 MB | `200000–3fffff` |
| `30000000–30001fff` | Shared console NVRAM | FPGA RAM, 8 KB |
| `40000000` | Palette, 0–2 | Register |
| `40000004` | Power button pulse | Register |
| `40000008` | Sound button pulse | Register |
| `4000000c` | Cold reset | Register |
| `40000010` | Eject slot 2 and reset | Register |
| `40000020` | Loader/core status | Register |
| `40000024` | Signature `47434f4d` | Register |
| `50000000–5000691f` | Pocket Memories buffer | FPGA RAM, 32 KB |
| `f8xxxxxx` | Framework commands | APF |

The bridge operates little-endian. Cartridges use PSRAM; the BIOS uses dedicated asynchronous SRAM. Each 32-bit ROM write is queued and split into low then high 16-bit writes. A 1024-word synchronous FIFO absorbs bursts because APF does not expose write backpressure. An overflow latches a fault and holds the CPU in reset. Reset exit waits for the loader to drain. Hardware transfers are serviced independently from host reset, which is asserted while assets are loaded.

The first die of PSRAM bank 0 holds both cartridges. Die 1, the second PSRAM chip and SDRAM are unused. The 256 KB BIOS exactly fills the 128K × 16 SRAM. Its CPU address and read data follow the CPU bus directly, so BIOS reads retain upstream timing. The loader supplies separate setup, 81 ns WE pulses, hold and bus turnaround periods while the CPU is in reset. The asynchronous PSRAM controller runs at 74.25 MHz with a conservative 100 ns access setting. CPU requests and data use a bundled-data toggle handshake between 20 and 74.25 MHz; a miss takes seven 20 MHz clocks (350 ns) against a 200 ns CPU bus cycle. Reads are served at three levels. Two halfword registers hold the halfword the CPU is using and a prefetched next one. Behind them is a direct-mapped block-RAM cache of 16,384 halfwords (32 KB of ROM) that every PSRAM response is stored in. Only a halfword in neither goes to PSRAM. The CPU launches an address two 20 MHz clocks before it samples the data; the cache RAM is read on the first of those clocks and its entry is compared on the second, so a cache hit costs no wait, like a register hit. When the cache read port is not looking up a missing CPU address, it looks one halfword ahead of the CPU, and the prefetcher asks PSRAM only for a next halfword that is not cached. Each register and cache entry is filled only by a completed read of its own address, and only one request is in flight. A demand miss waits for any prefetch already in flight.

Cartridge contents can change only while the machine is in reset, so after every reset the cache is emptied by a sweep of all entries (0.8 ms). Until the sweep finishes, lookups miss and nothing is stored, however short the reset was. A lookup that reads an entry in the clock it is written is discarded. A Memories pause drops the two registers but keeps the cache.

The CPU's ROM-ready input stalls CPU and DMA ROM sample cycles on misses. No cartridge data is read from a previous address while a request is pending.

For CPU addresses below 256 KB, the board selects the external BIOS. Above that, P3 selects a cartridge slot; absence reads as FF. Each cartridge is mirrored with its own power-of-two size mask. There is no subtraction of the BIOS window from cartridge addresses.

NVRAM is four 2048-byte dual-port banks: APF reads and writes all four lanes at 74.25 MHz; the CPU reads/writes one byte at 20 MHz. Data slot table entry 3 is updated with the 8192-byte save size on reset exit. APF manages persistence under `Saves/gamecom/common/gamecom.sav`.

The video adapter emits one VS pulse per frame, one HS pulse per line at least three clocks after VS, continuous DE per active line, and SKIP on the four unused 30 MHz cycles between pixels. Blanking RGB is zero, preventing accidental APF scaler commands. The 90-degree pixel clock is a PLL output.

Configuration, palette and Memories status cross clocks as buses that are accepted only after two equal consecutive samples, so a multi-bit change is never seen half-updated. Bridge-clock flags such as the Power and Sound presses and the reset request are registered before they cross. The right-stick thresholds are evaluated on the bridge clock and cross as four independent bits. The mailboxes whose data rides a synchronized toggle (ROM request and data, audio sample, boot-time date) have `set_net_delay` bounds in `core_constraints.sdc`. The asynchronous clock groups cut ordinary path analysis for these buses, and in Quartus 18.1 they also cut `set_max_skew`, but net-delay checks still apply. Each bound is well under the destination clock period that the two-flop synchronizer guarantees. The synchronizer registers carry Quartus's `SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS` attribute, the form Intel's own synchronizer primitive uses, so Quartus treats them as synchronizers and reports their MTBF. The Xilinx-style `async_reg` attribute used before is ignored by Quartus, and its default `AUTO` identification only lists likely chains. Each synchronizer's first stage is fed directly from a register.

Audio converts upstream offset-binary PCM to signed 16-bit samples. A request/ack mailbox captures coherent samples once per 48 kHz stereo frame. All serializer logic uses 74.25 MHz clock enables; no internally generated audio clock clocks FPGA registers.

Reference specifications: [APF bus](https://www.analogue.co/developer/docs/bus-communication), [memory hardware](https://www.analogue.co/developer/docs/external-hardware), [data slots](https://www.analogue.co/developer/docs/core-definition-files/data-json), [host commands](https://www.analogue.co/developer/docs/host-target-commands), [packaging](https://www.analogue.co/developer/docs/getting-started).

Pocket enables the new `DMA_ROM_WAIT` parameter, which defaults off for upstream-compatible timing. The existing ROM-ready input now also gates the initial DMA source sample, unaligned next-byte sample, and overlapped ROM prefetch sample. Physical DMA reads bypass the CPU MMU, so the wait condition uses the DMA mode and external access class. During a prefetch wait the simultaneous VRAM write remains at the same address and data; transfer counters advance only after ROM ready. BIOS and non-ROM DMA remain unstalled. The PSRAM mailbox has different latency from the MiSTer SDRAM controller, so cartridge execution timing is not asserted to be identical.

Pocket Memories use a 26,912-byte blob: a 32-byte versioned header, 8 KB console RAM, 256 bytes board I/O RAM, two 8 KB VRAM banks, and 2 KB CPU/peripheral state. APF holds each Memories request until it is acknowledged and processes no other host command meanwhile, so every request is acknowledged: one that arrives during an operation is served afterwards, and one that arrives while the machine is held in reset is refused with an error. Restore-blob tracking follows only APF's writes, so a blob written during reset still restores later. Capture waits for the upstream CPU safe-pause handshake. The wrapper freezes phi0/phi1 after acknowledgement; restore writes the same memory ports before releasing the CPU. APF transfers the restore blob before issuing its load command. Invalid headers and truncated or out-of-order transfers fail before changing machine memory. Save files are specific to this port's format, not MiSTer save states.

The QSF defines `SYNTHESIS`, matching upstream, to exclude debug-only arrays. The 20 MHz CPU is built with area optimization and multiplexer restructuring for the smaller Pocket device.

Pocket sets `ENABLE_CHEATS=0` to bypass the MiSTer cheat engine at elaboration; tying its load bus low had still retained 226 fitted flip-flops and 97 ALMs. The parameter defaults on upstream. Bulk memories are M10K-backed. The CPU retains its 128-byte low-IRAM shadow for seven parallel combinational reads, its 16-byte active GP shadow, and two 16-byte sound wave tables; these are intentional register arrays. The debug-only register-bank/SFR/low-memory mirrors are excluded by `SYNTHESIS`.

APF sends the date and time once at boot. `pocket_rtc` keeps them running in BCD on the 20 MHz clock and presents them in the MiSTer RTC layout. The CPU loads the organizer clock from that value after each reset, so a cold reset or cartridge eject picks up the current time.

`video.json` offers the Grayscale LCD (`0x20`), Reflective Color LCD (`0x30`) and Backlit Color LCD (`0x40`) display modes. Host command `00B8` reports the selected mode; when its grayscale bit is set, `core_bridge_cmd` replies `444D` and the wrapper forces the pure-gray palette until another mode is chosen.

The CPU's STOP state is brought out of the upstream board as `cpu_stopped_o`. While the Game.com is stopped (turned off), a new press of A, B, X, Y or Start produces the same 100 ms Power press as the menu action, which the upstream board already treats as a STOP wake source. STOP itself stays accurate (`stop_disable_i` is 0).

## Changes to upstream code

Three upstream files are modified; the other upstream files in `src/fpga/rtl/` are byte-identical to GameCom_MiSTer commit `96ed90ec865302d5eb5a0aa8336844dbfb4a5342`.

- `gamecom.v` passes three new parameters (`VIDEO_DIV`, `DMA_ROM_WAIT`, `ENABLE_CHEATS`) down to the CPU and video blocks. Their defaults preserve upstream behavior. It also exposes the CPU's STOP state as `cpu_stopped_o`, so the Pocket buttons can turn the Game.com back on.
- `sm8521.v` adds optional DMA ROM-ready waits for Pocket PSRAM (`DMA_ROM_WAIT`) and lets the unused MiSTer cheat engine be compiled out (`ENABLE_CHEATS=0` on Pocket).
- `gamecom_video.v` parameterizes the buffered video divider (30 MHz / 5 on Pocket instead of 60 MHz / 10) and replaces the two-buffer handoff with three framebuffers. The three-framebuffer change is not behind a parameter.
