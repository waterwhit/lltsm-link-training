# Physical Link Delay Training FSM

This repository contains a reusable FPGA physical-link delay training state machine.

It is intentionally separated from the original full controller workspace. The module can be inserted into different communication controller state machines, as long as the host controller provides a fixed training-frame transmit/receive adapter.

## Scope

Included:

- Link training branch FSM RTL
- Link training branch frame codec RTL
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
  -> Link Training Branch FSM + Codec
  -> TX FIFO / TX Frame Adapter
  -> MAC / Media Adapter
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Media Adapter
  -> RX Parser / RX FIFO
  -> Link Training Branch FSM + Codec
```

The measured result is `trained_path_delay`, not pure physical propagation delay.

## Key interface groups

- TOP control: `training_enable`, `abort`, `local_start`, node/link/channel/round configuration.
- TX training-frame adapter: `train_tx_*`.
- RX training-frame adapter: `train_rx_*`, including `train_rx_ref_time`.
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
