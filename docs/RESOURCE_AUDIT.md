# FPGA resource use

The fit uses 16,695 of 18,480 ALMs (90%), 5,962 flip-flops, 169 of 308 M10K blocks and 1,320,960 block-RAM bits. No memory is built from MLABs or logic cells.

## Block RAM

| Storage | M10Ks |
| --- | ---: |
| Cartridge ROM cache, 16,384 × 25 bits (valid, 8-bit tag, 16-bit data) | 50 |
| Three 32K × 3-bit video framebuffers | 36 |
| 32 KB Memories staging buffer | 32 |
| Two 8 KB video RAM banks | 16 |
| 8 KB console save RAM | 8 |
| Banked CPU general registers, eight lanes | 8 |
| Cartridge loading FIFO | 6 |
| BIOS loading FIFO | 5 |
| Power-off logo ROM | 4 |
| APF data table | 2 |
| 1 KB CPU internal RAM | 1 |
| Board I/O RAM | 1 |

The 256 KB BIOS is in the Pocket's SRAM and cartridge data is in PSRAM. Neither is replicated into flip-flops.

## Register arrays

`scripts/audit_registers.tcl` counts these in the fitted design:

- CPU low-IRAM shadow: 1024 registers. It supplies seven parallel combinational reads; moving it to block RAM would mean rescheduling those reads and the multi-byte writes.
- Two sound waveform tables: 128 registers each.
- Active general-register shadow: 128 registers.
- Debug-only `reg_bank_q`, `sfr_shadow_q` and `lowmem_q`: none, because the project defines `SYNTHESIS`. `gp_shadow_q` is combinational wiring, also with none.
- Cheat engine: none, because the Pocket build sets `ENABLE_CHEATS=0`.

The sound tables and the general-register shadow also provide parallel access in the existing datapath.

## Logic

Most of the logic is the CPU: its own hierarchy, excluding child modules, uses 14,027 ALMs and 2,923 registers. The pressure is combinational decode, multiplexing and execution logic, not memory expanded into registers.

Intel's memory-editor support keeps a small JTAG control path in the supplied single-port RAM wrapper. That is instrumentation, not emulated storage.
