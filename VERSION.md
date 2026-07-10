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
- Training response preserves the 128-bit LLTSM payload bit-for-bit.
- LLTSM_LINK recognizes training frames from payload fields.
- MAC supplies CRC/FCS status and does not inspect LLTSM payload fields.
- Optional fixed responder-delay compensation for the trained path result.

Verified snapshot:

- Vivado 2019.2 SystemVerilog compile and elaboration passed.
- Two-node system simulation passed bad-CRC rejection, non-training payload
  rejection inside LLTSM_LINK, exact echo,
  repeated RTT measurement, result reporting, and controller-owned abort.
