# Port architecture

The Game.com itself (SM8521 CPU, board, sound and LCD) is the upstream MiSTer RTL. The MiSTer `emu` wrapper, HPS I/O, DDR3 save-state storage, scandoubler, SDRAM controller, UART routing and OS menu are replaced by the Analogue template's `core_top` and the adapters in `src/fpga/pocket/`.

## Clocks

- 20 MHz system clock, with alternating 5 MHz phi0/phi1 enables for the CPU. The CPU's native LCD fetch runs unchanged.
- 30 MHz video clock. The buffered raster runs at 30 MHz / 5 = 6 MHz, and the 90-degree pixel clock is a PLL output.
- 74.25 MHz APF bridge clock, which also runs the loaders, the PSRAM controller and the audio serializer.

## Address map

| APF bridge bytes | Contents | Backing storage |
| --- | --- | --- |
| `00000000–001fffff` | Cartridge 1, max 2 MB | PSRAM `000000–1fffff` |
| `10000000–1003ffff` | External BIOS, 256 KB | SRAM, 256 KB |
| `20000000–201fffff` | Cartridge 2, max 2 MB | PSRAM `200000–3fffff` |
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

The bridge operates little-endian, so file bytes arrive in order. The same setting byte-swaps every number the Pocket writes or reads, so the `400000xx` registers are swapped back in the wrapper, as Analogue's command handler does for host commands.

## Loading the BIOS and cartridges

Cartridges go to PSRAM and the BIOS to the dedicated asynchronous SRAM. Both cartridges fit in the first die of PSRAM bank 0; die 1, the second PSRAM chip and SDRAM are unused. The 256 KB BIOS exactly fills the 128K × 16 SRAM.

- Each 32-bit bridge write is queued and split into low then high 16-bit writes. APF has no write backpressure, so a 1024-word synchronous FIFO absorbs bursts.
- A FIFO overflow latches a fault and holds the CPU in reset. Reset exit waits for the loader to drain.
- Transfers are serviced independently of host reset, which is asserted while assets load.
- The BIOS loader supplies separate setup, 81 ns WE pulse, hold and bus turnaround periods while the CPU is in reset.

For CPU addresses below 256 KB the board selects the external BIOS. Above that, P3 selects a cartridge slot, and an empty slot reads as FF. Each cartridge is mirrored with its own power-of-two size mask. The BIOS window is not subtracted from cartridge addresses.

## Reading the BIOS and cartridges

The BIOS address and read data follow the CPU bus directly, so BIOS reads keep upstream timing.

The asynchronous PSRAM controller runs at 74.25 MHz with a conservative 100 ns access setting, and requests and data cross between 20 and 74.25 MHz through a bundled-data toggle handshake. A PSRAM read takes seven 20 MHz clocks (350 ns) against a 200 ns CPU bus cycle, so cartridge reads are served at three levels:

1. Two halfword registers hold the halfword the CPU is using and a prefetched next one.
2. A direct-mapped block-RAM cache of 16,384 halfwords (32 KB of ROM) stores every PSRAM response.
3. Only a halfword in neither goes to PSRAM.

The CPU launches an address two 20 MHz clocks before it samples the data. The cache RAM is read on the first of those clocks and its entry is compared on the second, so a cache hit costs no wait, like a register hit. When the cache read port is not looking up a missing CPU address it looks one halfword ahead of the CPU, and the prefetcher asks PSRAM only for a next halfword that is not cached.

What keeps the data correct:

- Each register and cache entry is filled only by a completed read of its own address, and only one request is in flight. A demand miss waits for a prefetch already in flight.
- The CPU's ROM-ready input stalls CPU and DMA ROM sample cycles on a miss, so no data is read from a previous address while a request is pending.
- Cartridge contents can change only while the machine is in reset, so every reset is followed by a sweep that empties the cache (0.8 ms). Until the sweep finishes, lookups miss and nothing is stored, however short the reset was.
- A lookup that reads an entry in the clock it is written is discarded.
- A Memories pause drops the two registers but keeps the cache.

The cache size comes from replaying three games' cartridge access traces: at 2^14 entries only the first touch of each halfword still misses, and 2^15 gained nothing.

### DMA from cartridge ROM

The Pocket build enables the `DMA_ROM_WAIT` parameter, which defaults off for upstream-compatible timing. With it, the ROM-ready input also gates the initial DMA source sample, the unaligned next-byte sample and the overlapped ROM prefetch sample. Without it, a DMA copies stale bytes whenever the ROM is not ready, which corrupts game graphics.

- Physical DMA reads bypass the CPU MMU, so the wait condition uses the DMA mode and external access class.
- During a prefetch wait the simultaneous VRAM write stays at the same address and data. Transfer counters advance only after ROM ready.
- BIOS and non-ROM DMA are not stalled.

The PSRAM path has different latency from the MiSTer SDRAM controller, so cartridge execution timing is not claimed to be identical.

## Video

All pixels, sync levels and framebuffer swaps originate from `gamecom_video`. The LCD refreshes at about 75 Hz and the Pocket is driven at 60 Hz, so the converter uses three 32K × 3-bit block-RAM framebuffers: one being written, the latest complete frame, and the one on display. The roles are managed on the video clock, which clocks both RAM ports.

- Every complete native frame becomes the latest candidate. If the display has not taken the previous candidate, that one becomes the next write buffer.
- At output vblank the display takes the latest candidate and releases its old buffer. If a frame completes at the same moment, that frame is the one shown.
- The three roles always refer to distinct buffers, and the displayed buffer never changes during active output.

Every output frame is a whole source frame, and a new one as long as the source keeps producing them. Going from 75 Hz to 60 Hz still skips some source frames; it does not change the emulated CPU or LCD rate.

The video adapter emits one VS pulse per frame, one HS pulse per line at least three clocks after VS, continuous DE per active line, and SKIP on the four unused 30 MHz cycles between pixels. Blanking RGB is zero, which prevents accidental APF scaler commands.

`video.json` offers the Grayscale LCD (`0x20`), Reflective Color LCD (`0x30`) and Backlit Color LCD (`0x40`) display modes. Host command `00B8` reports the selected mode; when its grayscale bit is set, `core_bridge_cmd` replies `444D` and the wrapper forces the pure-gray palette until another mode is chosen.

## Audio

Upstream offset-binary PCM is converted to signed 16-bit samples. A request/ack mailbox captures coherent samples once per 48 kHz stereo frame. All serializer logic uses 74.25 MHz clock enables; no internally generated audio clock clocks FPGA registers.

## Console save

NVRAM is four 2048-byte dual-port banks: APF reads and writes all four byte lanes at 74.25 MHz, and the CPU reads or writes one byte at 20 MHz. Data slot table entry 3 is updated with the 8192-byte save size on reset exit. APF keeps the file at `Saves/gamecom/common/gamecom.sav`.

## Memories

A Memory is a 26,912-byte blob: a 32-byte versioned header, 8 KB console RAM, 256 bytes of board I/O RAM, two 8 KB VRAM banks and 2 KB of CPU and peripheral state. The format is specific to this port; MiSTer save states do not load.

- Capture waits for the upstream CPU safe-pause handshake, and the wrapper freezes phi0/phi1 after acknowledgement. Restore writes the same memory ports before releasing the CPU.
- APF transfers the restore blob before issuing its load command. Invalid headers and truncated or out-of-order transfers fail before any machine memory changes.
- APF holds each Memories request until it is acknowledged and processes no other host command meanwhile, so every request gets an answer: one that arrives during an operation is served afterwards, and one that arrives while the machine is held in reset is refused with an error.
- Restore-blob tracking follows only APF's writes, so a blob written during reset still restores later.

## Clock and power

APF sends the date and time once at boot. `pocket_rtc` keeps them running in BCD on the 20 MHz clock and presents them in the MiSTer RTC layout. The CPU loads the organizer clock from that value after each reset, so a cold reset or cartridge eject picks up the current time.

The CPU's STOP state is brought out of the upstream board as `cpu_stopped_o`. While the Game.com is stopped (turned off), a new press of A, B, X, Y or Start produces the same 100 ms Power press as the menu action, which the upstream board already treats as a STOP wake source. STOP itself stays accurate (`stop_disable_i` is 0).

## Clock crossings

- Configuration, palette and Memories status cross as buses that are accepted only after two equal consecutive samples, so a multi-bit change is never seen half-updated.
- Bridge-clock flags such as the Power and Sound presses and the reset request are registered before they cross. The right-stick thresholds are evaluated on the bridge clock and cross as four independent bits.
- The mailboxes whose data rides a synchronized toggle (ROM request and data, audio sample, boot-time date) have `set_net_delay` bounds in `core_constraints.sdc`. The asynchronous clock groups cut ordinary path analysis for these buses, and in Quartus 18.1 they cut `set_max_skew` too, but net-delay checks still apply. Each bound is well under the destination clock period that the two-flop synchronizer guarantees.
- The synchronizer registers carry `SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS` so that Quartus reports their MTBF; it ignores the Xilinx-style `async_reg` attribute. Each synchronizer's first stage is fed directly from a register.

## Synthesis and fit

- The QSF defines `SYNTHESIS`, matching upstream, which leaves out the debug-only register-bank, SFR and low-memory mirrors.
- The CPU is built with area optimization and multiplexer restructuring to fit the Pocket's smaller device.
- `ENABLE_CHEATS=0` removes the MiSTer cheat engine at elaboration. Tying its load bus low is not enough: Quartus still fitted 226 flip-flops and 97 ALMs for it. The parameter defaults on upstream.
- Bulk memories are M10K block RAM. A few CPU arrays stay in registers on purpose; see the [resource audit](RESOURCE_AUDIT.md).
- The fitter runs Standard Fit with seed 2 and router LCELL insertion off. The SDC adds a Fitter-only 300 ps hold guard band on the CPU's GP-store RAM inputs, which have the smallest hold margin in the design; sign-off analysis checks the real requirement.

## Changes to upstream code

Three upstream files are modified; the other upstream files in `src/fpga/rtl/` are byte-identical to GameCom_MiSTer commit `96ed90ec865302d5eb5a0aa8336844dbfb4a5342`.

- `gamecom.v` passes three new parameters (`VIDEO_DIV`, `DMA_ROM_WAIT`, `ENABLE_CHEATS`) down to the CPU and video blocks. Their defaults preserve upstream behavior. It also exposes the CPU's STOP state as `cpu_stopped_o`.
- `sm8521.v` adds the optional DMA ROM-ready waits (`DMA_ROM_WAIT`) and lets the cheat engine be compiled out (`ENABLE_CHEATS`).
- `gamecom_video.v` parameterizes the buffered video divider (30 MHz / 5 on Pocket instead of 60 MHz / 10) and replaces the two-buffer handoff with three framebuffers. The three-framebuffer change is not behind a parameter.

## Reference specifications

Analogue's [APF bus](https://www.analogue.co/developer/docs/bus-communication), [memory hardware](https://www.analogue.co/developer/docs/external-hardware), [data slots](https://www.analogue.co/developer/docs/core-definition-files/data-json), [host commands](https://www.analogue.co/developer/docs/host-target-commands) and [packaging](https://www.analogue.co/developer/docs/getting-started).
