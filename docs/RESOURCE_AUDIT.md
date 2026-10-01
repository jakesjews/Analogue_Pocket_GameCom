# Memory and register audit

First 0.1.3 fit, 2026-09-09: 16,592 ALMs, 6,031 flip-flops, 107 M10Ks, 813,056 stored RAM bits. The DMA-ready change added no registers or RAM blocks compared with 0.1.2. These counts describe the first placement, which failed timing and was not installed.

| Storage | Physical implementation | M10Ks |
| --- | --- | ---: |
| Two 8 KB video RAM banks | Block RAM | 16 |
| Two 32K x 3-bit video framebuffers | Block RAM | 24 |
| Power-off logo ROM | Block RAM | 4 |
| 1 KB CPU internal RAM | Block RAM | 1 |
| Banked CPU general registers | Eight block RAM lanes | 8 |
| BIOS loading FIFO | Block RAM | 5 |
| Cartridge loading FIFO | Block RAM | 6 |
| 8 KB console save RAM | Block RAM | 8 |
| 32 KB Memories staging buffer | Block RAM | 32 |
| Board I/O RAM | Block RAM | 1 |
| APF data table | Block RAM | 2 |

The external 256 KB BIOS occupies Pocket SRAM. Cartridge data occupies PSRAM. Neither is replicated into FPGA flip-flops.

Post-fit register-name queries found 1024 registers for the CPU low-IRAM shadow, 128 for each sound waveform, and 128 for the active general-register shadow. The low-IRAM shadow supplies seven parallel combinational reads; a block-RAM replacement would require scheduling those reads and the multi-byte writes differently. The sound tables and active-register shadow also provide parallel access in the existing datapath.

The debug-only `reg_bank_q`, `sfr_shadow_q`, and `lowmem_q` arrays have zero fitted registers. `gp_shadow_q` is combinational wiring, also with zero registers. `SYNTHESIS` is explicitly set in the Quartus project.

The unused MiSTer cheat engine did retain 226 registers and 97 ALMs despite its constant input bus. Pocket now sets `ENABLE_CHEATS=0`, removing the engine at elaboration. The repeated puzzle-screen simulation produced a byte-identical framebuffer and full 26,912-byte machine-state blob after the cleanup. The final fit confirms that the cleanup removes exactly 226 flip-flops.

Most logic use belongs to the CPU: its own hierarchy uses 14,066.6 ALMs and 2,923 registers, excluding child modules. The area pressure is primarily combinational CPU decode, multiplexing and execution logic. Bulk memory has not expanded into registers. Intel memory-editor support also retains a small JTAG control/metadata path in the supplied single-port RAM wrapper; that is instrumentation rather than emulated-memory storage.

Local evidence: `build/fitter-ram-summary.json`, `build/fitter-resource-utilization-by-entity.json`, `build/register-array-audit-before.txt`, and `build/memory-resource-audit-before.json`.

Final 0.1.3 fit: **16,456 ALMs, 5,805 flip-flops, 107 M10Ks, 813,056 RAM bits**. The cleanup removed exactly 226 flip-flops; bulk RAM usage is unchanged. All 80 constrained timing groups pass, including the tighter GP-store minimum delay.

Version 0.1.4 frame-pacing fit: **16,401 ALMs, 5,804 flip-flops, 119 M10Ks, 911,360 RAM bits**. Compared with 0.1.3, this uses 55 fewer ALMs and one fewer flip-flop. The third 32K × 3-bit framebuffer adds exactly 98,304 stored bits and 12 M10Ks. All three framebuffers use 12 M10Ks each and zero MLABs; bulk storage has not expanded into flip-flops. The three buffer roles use a few control registers on the video clock and replace the previous cross-clock acknowledgement state.
The 0.1.4 fit passes all 80 constrained timing checks without changing the 0.1.3 timing constraints. Detailed final RAM placement and timing evidence are retained in `build/frame-pacing-resources.json`, `build/frame-pacing-ram-summary.json` and `build/frame-pacing-timing.json`.

Version 0.2.0 fit: **16,645 ALMs, 5,922 flip-flops, 119 M10Ks, 911,360 RAM bits**. Compared with 0.1.4 this is 244 more ALMs and 118 more flip-flops, for the second ROM entry and prefetch control, the running RTC, the synchronizer check stages and the registered crossing flags. RAM use is unchanged. Timing needed the GP-store hold reservation extended to write port A; see the validation record.

Version 0.2.1 fit: **16,709 ALMs, 5,962 flip-flops, 169 M10Ks, 1,320,960 RAM bits**. The cartridge ROM cache adds exactly 409,600 bits in 50 M10Ks (16,384 entries of valid, 8-bit tag and 16-bit data); the whole build uses 64 more ALMs and 40 more flip-flops than 0.2.0. The cache is block RAM with no MLABs or register arrays.
