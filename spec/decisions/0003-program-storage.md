# 0003 — Program storage: SPI-flash copy-boot at reset, flash pins become GPIO

- **Status**: proposed — flips to `RATIFIED` in this PR after the two
  independent reviews (engineering and market) required by the repo
  instructions.
- **Supersedes**: the README draft row "Program storage: boot from external
  SPI flash / Stretch: optional mask ROM"; the mask-ROM stretch is dropped
  with its cost stated.
- **Superseded by**: none.
- **Spec rows**: `spec/target-spec.md` row 6 (Program storage).

## Context

The open sky130 PDK has no on-chip non-volatile memory (README § Status, and
record 0002's `libs.ref/` listing shows no ROM library), so program storage
is either external or a synthesized read-only array. The draft chose
"boot from external SPI flash" with a mask-ROM stretch, but did not fix the
protocol, the boot mechanism, or the mask-ROM cost. Facts read
**2026-11-19** unless noted.

| Fact | Value | Source |
|---|---|---|
| sky130 ROM macro | none shipped | `libs.ref/` listing, PDK commit `c6d73a35…` (record 0002) |
| Synthesized ROM cost | A 256 B ROM represents 2,048 constants. Its area depends on the image and logic minimization. A numerical area comparison requires synthesis with a named image. | Record 0002 gives measured cell areas for writable storage only. |
| Reference flash | Winbond W25Q16JWSNJQ, standard SPI, 1.65–1.95 V. `03h` takes a 24-bit address and streams bytes MSB first. With CS# high the outputs are high impedance after at most 7 ns. | [Winbond W25Q16JW Rev H](https://www.winbond.com/resource-files/W25Q16JW%20RevH%2005262026%20Plus.pdf), Pin Descriptions, Read Data, Power-Up Timing, AC Characteristics and Ordering Information, read 2026-11-25 |
| Flash busy across MCU reset | A powered flash accepts Read Status Register-1 (`05h`) during an erase or program. It ignores Read Data (`03h`) while BUSY is set. A 4 KiB sector erase can take 400 ms. | [Winbond W25Q16JW Rev H](https://www.winbond.com/resource-files/W25Q16JW%20RevH%2005262026%20Plus.pdf), Status Register-1 bit S0, Read Status Register, Read Data and AC Electrical Characteristics, read 2026-11-26 |
| Board interface | MCU I/O and flash share a nominal 1.8 V rail. Provide a CS# pull-up to that rail. Keep unused IO2/IO3 pulled high for single-SPI operation. | Flash thresholds and timing from the same datasheet. Integration must check pad VOH/VOL, VIH/VIL, load and delays. The 1.60 V internal STA corner is outside the flash supply range. |
| Precedent for a tiny boot FSM | the sibling SoC uses a 4 KB boot ROM whose firmware copies/receives code into SRAM (`spec/soc.md` § Memory map, read 2026-11-19); this block has no room for a firmware ROM, so the copy is hardware | 2AMLogic/sky130-riscv-soc @ `e1135913b57ebf0cd57a7882772545fedb7291d0` |

The external flash supplies persistent storage. Copying the program frees
the SPI controller after boot. The board wiring still limits independent
GPIO use (record 0005).

## Decision

1. **SPI copy.** A high RX at strap sample (0005) selects SPI mode 0.
   On every SPI boot, assert CS#, send `05h` and clock complete status
   bytes from CIPO until bit 0 (BUSY) reads zero. Keep SERV in reset
   and inhibit RAM writes and fetches for the entire wait, however long
   the flash stays busy. Raise CS# for at least 10 ns (read deselect time),
   then assert it for a new `03h` transaction at address `0x000000`.
   Read with no dummy cycles. The loader writes the
   112 returned bytes in ascending order to `0x00–0x6F`. A raw image is
   little-endian RV32 code at offset zero, followed by its link-defined
   contents and zero padding to 112 bytes. There is no header. At the
   fastest qualified ring speed, the SPI divider must meet the part's
   50 MHz READ limit and all setup, hold and output-valid times including
   board delay. The board's reset timing covers the 20 µs minimum from
   flash VCC(min) to first CS# assertion (record 0005).
2. **Handoff on either path.** The loader owns RAM exclusively through
   the edge that writes byte 111 at `0x6F`. Keep SERV reset, RF writes
   disabled and instruction requests gated through that edge. Deselect
   flash, set SCLK low and leave CIPO an input. On a subsequent ROSC edge
   transfer RAM to the CPU and release its reset. The first instruction
   fetch is a little-endian word at `RESET_PC=0`. There are no writes to
   the RF region during loading. GPIO starts in the safe state in 0005.
   An interrupted load restarts at byte zero on reset.
3. **UART fallback.** A low RX at strap sample selects the hardware loader.
   Keep CS# high throughout. The host holds RX low through strap sample
   (allow reset synchronization and the 256-cycle count at the slowest
   characterized ROSC), then drives idle high for at least one 8N1 frame
   and at least 16 ROSC edges. The loader arms only after 16 consecutive
   synchronized high samples. The next falling edge starts a fresh `0x55`
   frame. Count to its first rising edge (one bit), validate the alternating
   bits and stop bit, then receive 112 raw bytes, 8N1, LSB first per byte.
   Invalid training returns to idle qualification. The training byte is
   excluded from RAM. A framing error during payload discards the partial
   load and restarts training at offset zero with the core held. Record
   the supported baud/drift envelope before claiming a host rate (0004).
4. **Mask ROM.** A synthesized ROM adds image-dependent decode/storage
   area and fixes one program per mask revision. The open PDK inventory
   in 0002 contains no ROM macro. Retain the reprogrammable external
   store and disclose the extra component in board comparisons.
5. **Blank flash.** Once a ready flash supplies all 112 bytes, the loader
   releases the core even if the image is all `FF`. The raw image format
   has no integrity check.

## Alternatives considered

- **XIP from SPI flash** (fetch every instruction over SPI, Servant-style).
  Rejected: the four flash pins are then never free, so GPIO = 0 and the
  8-pin part loses its only general-purpose I/O; fetch latency also
  multiplies SERV's cycle counts.
- **Mask ROM** (draft stretch). Dropped — costed and rejected above.
- **Firmware boot loader in a small ROM** (the sibling SoC's pattern).
  Rejected: the RAM is 256 B total (record 0002); a loader firmware living
  beside the user program would consume the program budget. The loader is
  hardware here.
- **UART boot as the only mode** (no flash). Rejected: no persistent
  program — the part stops being usable untethered, which is the point of
  an MCU.
- **QSPI / fast-read commands (`0Bh`, dual/quad).** Rejected for the
  target: wider buses cost pins this package does not have; `03h` is the
  standard read command on the selected part.

## Consequences

- The boot FSM, the strap mux and the pin mux (record 0005) are one
  coherent RTL unit; their combined area is measured in the flow reports.
- SPI boot takes 8 clocks for `05h` and 8 per status byte, then 32 for
  the read command/address and 896 for the payload. Startup also includes
  board reset, the 256-cycle strap delay, CS timing and handoff.
- The cocotb boot test must exercise both loaders and GPIO handoff. For
  warm reset, preload a known 112-byte boot image, start a sector erase
  outside the boot image and pulse MCU reset with the flash still powered.
  Model `03h` as ignored while busy and keep BUSY set past strap sample
  for several status bytes. Check that the loader polls without issuing
  `03h`, writing RAM or releasing SERV. After BUSY clears, check the new
   read transaction, compare all 112 RAM writes with the image and assert
   that SERV stays in reset through the last write at `0x6F`. Observe
   the first fetch at zero on a later edge and the firmware's expected result.
