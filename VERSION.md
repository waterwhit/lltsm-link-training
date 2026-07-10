# Version

Current release:

```text
v0.2.0
```

Date: 2026-07-10

Scope:

- Two-module LLTSM architecture: `lltsm_fsm` and `lltsm_link`.
- Communication-controller TOP owns entry to and exit from the LLTSM branch.
- Fixed 128-bit training payload carried through asymmetric TX/RX FIFOs.
- Training response preserves the MAC frame class and payload bit-for-bit.
- MAC owns link headers, padding, CRC/FCS, and PHY/channel selection.
- Optional fixed responder-delay compensation for the trained path result.

Verified snapshot:

- Vivado 2019.2 SystemVerilog compile and elaboration passed.
- Two-node system simulation passed bad-frame rejection, exact echo,
  repeated RTT measurement, result reporting, and controller-owned abort.
