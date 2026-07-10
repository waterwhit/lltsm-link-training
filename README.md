# Physical Link Delay Training FSM

This repository contains a reusable FPGA physical-link delay training state machine.

It is intentionally separated from the original full controller workspace. The module can be inserted into different communication controller state machines, as long as the host controller provides a fixed training-frame transmit/receive adapter.

## Scope

Included:

- Link training branch FSM RTL
- Link training branch frame codec RTL
- Reusable LLTSM TX payload formatter RTL
- Reusable LLTSM RX payload parser RTL
- FSM and codec testbenches
- LLTSM interface/design documents
- Architecture diagrams

Excluded:

- Full communication-controller RTL unrelated to link training
- Vivado generated files
- Bitstreams and implementation outputs
- Project reports and customer delivery archives

## Active RTL

```text
rtl/ttp_lltsm_branch_fsm.sv
rtl/ttp_lltsm_branch_codec.sv
rtl/lltsm_tx_payload_formatter.sv
rtl/lltsm_rx_payload_parser.sv
```

## Testbenches

```text
sim/tb_ttp_lltsm_branch_fsm.sv
sim/tb_ttp_lltsm_branch_codec.sv
```

## Integration rule

The training FSM does not directly drive PHY signals.

The intended integration path is:

```text
Host Communication Controller FSM/TOP
  -> Link Training Branch FSM
  -> LLTSM TX Payload Formatter
  -> MAC / Link Frame Processing
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Link Frame Processing
  -> LLTSM RX Payload Parser
  -> Link Training Branch FSM
```

LLTSM only formats and parses the fixed training payload. PHY selection,
link-frame adaptation, padding, address filtering, SOF/EOF handling, and
CRC/FCS insertion/checking are MAC/link-frame-layer responsibilities.

The measured result is `trained_path_delay`, not pure physical propagation delay.

## Key interface groups

- TOP control: `training_enable`, `abort`, `local_start`, node/link/channel/round configuration.
- TX training semantic fields from FSM: `train_tx_*`.
- TX payload stream to MAC/link-frame layer: `lltsm_tx_payload_*`.
- RX payload stream from MAC/link-frame layer: `lltsm_rx_payload_*`.
- RX training semantic fields to FSM: `train_rx_*`, including `train_rx_ref_time`.
- Result output: `result_valid`, `result_ok`, `result_rtt_average`, `result_mean_delay`.

## Active local repository path

```text
E:\aaworkspace\lltsm-link-training
```

The old full-controller workspace is now only a source-history/reference location for this module. New link-training development should happen in this standalone GitHub local repository.

## Baseline tag

```text
v0.1-lltsm-branch-frozen
```