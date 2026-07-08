# LLTSM Link Training

This repository contains only the simplified link training state machine for the FPGA TTP/TTE controller project.

It is intentionally separated from the full Vivado controller workspace so that the LLTSM function can be versioned, reviewed, and tested independently.

## Scope

Included:

- LLTSM branch FSM RTL
- LLTSM branch frame codec RTL
- FSM and codec testbenches
- LLTSM interface/design documents
- Architecture diagrams

Excluded:

- Full TTP controller RTL unrelated to link training
- Vivado generated files
- Bitstreams and implementation outputs
- Project reports and customer delivery archives

## Active RTL

```text
rtl/ttp_lltsm_branch_fsm.sv
rtl/ttp_lltsm_branch_codec.sv
```

## Testbenches

```text
sim/tb_ttp_lltsm_branch_fsm.sv
sim/tb_ttp_lltsm_branch_codec.sv
```

## Frozen design rule

The LLTSM does not directly drive PHY signals.

The intended integration path is:

```text
Controller TOP
  -> LLTSM Branch FSM + Codec
  -> TX FIFO / TX Frame Adapter
  -> MAC / Media Adapter
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Media Adapter
  -> RX Parser / RX FIFO
  -> LLTSM Branch FSM + Codec
```

The measured result is `trained_path_delay`, not pure physical propagation delay.

## Key interface groups

- TOP control: `training_enable`, `abort`, `local_start`, node/link/channel/round configuration.
- TX training-frame adapter: `train_tx_*`.
- RX training-frame adapter: `train_rx_*`, including `train_rx_ref_time`.
- Result output: `result_valid`, `result_ok`, `result_rtt_average`, `result_mean_delay`.

## Recommended repository name

```text
lltsm-link-training
```

## Baseline tag

```text
v0.1-lltsm-branch-frozen
```
