# Standalone Link Training State Machine

This repository contains a reusable two-module LLTSM implementation for FPGA
communication controllers.

## RTL architecture

Only two LLTSM RTL modules are required:

```text
rtl/lltsm_fsm.sv
rtl/lltsm_link.sv
```

- `lltsm_fsm` is a branch state machine of the communication-controller FSM.
  The controller TOP owns the transition into and out of this branch through
  `train_enable`, `train_start`, `train_abort`, and `train_done`.
- `lltsm_link` builds the fixed 128-bit `TRAIN_FRAME`, writes one complete frame
  to the wide side of a width-converting TX FIFO, recognizes and validates
  returned training frames from their payload fields, and latches the
  MAC-supplied RX timestamp.

The previous standalone codec, TX formatter, and RX parser are intentionally
merged into `lltsm_link`; they are internal link-engine duties, not additional
architecture layers.

## Integration boundary

```text
Communication-controller TOP/FSM
  -> lltsm_fsm
  -> lltsm_link
  -> TX width-converting FIFO (128-bit write / MAC-width read)
  -> MAC: generic link transport, CRC/FCS, PHY selection
  -> PHY and adjacent node
  -> MAC: CRC/FCS check and RX timestamp
  -> RX width-converting FIFO (MAC-width write / 128-bit read)
  -> lltsm_link
  -> lltsm_fsm
  -> Communication-controller TOP/FSM
```

FIFO primitives and MAC logic are integration infrastructure and are not extra
LLTSM modules. The repository deliberately does not instantiate a vendor FIFO
IP, because FIFO clocking and the MAC-side data width belong to the host design.

## Fixed response rule

The response is an exact echo:

- the complete 128-bit LLTSM payload remains unchanged;
- the MAC generates/checks CRC/FCS but does not inspect LLTSM payload fields.

Because the response payload is immutable, it cannot carry a measured remote
turnaround field. `RSP_COMPENSATION_CYCLES` must therefore match a fixed,
system-characterized responder delay when a compensated one-way result is
required. With the default value `0`, `result_mean_delay` is half of the trained
round-trip delay and includes half of the responder processing delay.

## Verification

```text
sim/tb_lltsm_system.sv
```

The test verifies bad-frame rejection, exact payload echo, repeated RTT
measurement, result reporting, and controller-owned branch abort.

## Active repository

```text
E:\aaworkspace\lltsm-link-training
```
