# Changelog

## v0.2.0 - 2026-07-10

- Reduced the LLTSM RTL architecture to `lltsm_fsm` and `lltsm_link`.
- Defined LLTSM FSM as a communication-controller branch controlled by TOP.
- Merged fixed-frame coding, TX formatting, RX parsing, response validation,
  and timestamp latching into `lltsm_link`.
- Changed the MAC boundary to wide-side interfaces for asymmetric TX/RX FIFOs.
- Moved training-frame recognition from MAC to `lltsm_link`: protocol magic,
  reserved bits, fixed pattern, addressing, and expected-response matching.
- Removed TX/RX training-frame-class sidebands; MAC now supplies only CRC/FCS
  status and timestamp alongside the received payload.
- Made the training response an exact echo of the 128-bit payload.
- Added a system-level test for rejection, exact echo, measurement, and abort.
- Removed legacy protocol-specific identifiers from RTL and simulation names.
