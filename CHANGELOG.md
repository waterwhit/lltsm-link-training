# Changelog

## v0.2.0 - 2026-07-10

- Reduced the LLTSM RTL architecture to `lltsm_fsm` and `lltsm_link`.
- Defined LLTSM FSM as a communication-controller branch controlled by TOP.
- Merged fixed-frame coding, TX formatting, RX parsing, response validation,
  and timestamp latching into `lltsm_link`.
- Changed the MAC boundary to wide-side interfaces for asymmetric TX/RX FIFOs.
- Kept MAC link-header generation, padding, CRC/FCS, and PHY selection outside
  LLTSM.
- Made the training response an exact echo of frame class and 128-bit payload.
- Added a system-level test for rejection, exact echo, measurement, and abort.
- Removed legacy protocol-specific identifiers from RTL and simulation names.
