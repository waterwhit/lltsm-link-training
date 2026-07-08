# Integration Guide

This repository is now the active standalone workspace for the physical-link delay training FSM:

```text
E:\aaworkspace\lltsm-link-training
```

The old full-controller workspace is no longer the active development location for this module.

## Design intent

The module is a reusable branch FSM that can be inserted into different communication controllers.

It assumes the host controller provides:

- training enable/abort/start control;
- selected local node, adjacent node, link ID, channel ID and training round ID;
- exclusive training-window scheduling;
- normal-traffic freeze during training;
- a TX training-frame adapter;
- an RX training-frame adapter;
- a local timestamp counter.

## Required host integration path

```text
Host Communication Controller FSM/TOP
  -> ttp_lltsm_branch_fsm
  -> ttp_lltsm_branch_codec
  -> TX FIFO / TX Frame Adapter
  -> MAC / Media Adapter
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Media Adapter
  -> RX Parser / RX FIFO
  -> ttp_lltsm_branch_codec
  -> ttp_lltsm_branch_fsm
```

The FSM must not be wired directly to raw PHY pins.

## Interface contract

### Control side

The host controller drives:

- `training_enable`
- `abort`
- `time_now`
- `local_start`
- `local_node_id`
- `local_neighbor_node_id`
- `local_link_id`
- `local_channel_id`
- `local_training_round_id`

The FSM returns:

- `local_start_ready`
- `busy`
- `done`
- `result_valid`
- `result_ok`
- `result_rtt_average`
- `result_mean_delay`
- `branch_state`

### TX training-frame adapter

The FSM drives `train_tx_*` fields.

The adapter asserts `train_tx_ready` at the documented TX reference point. In the low-complexity integration, this can be the cycle when the fixed training frame is accepted by the TX FIFO/frame adapter, provided that this reference point is also used consistently in later compensation.

### RX training-frame adapter

The adapter drives `train_rx_*` fields after frame parsing and CRC/protocol checks.

`train_rx_ref_time` must be the documented RX reference timestamp. In the low-complexity integration, this can be the RX parser/FIFO boundary timestamp.

## Result meaning

The FSM result is:

```text
trained_path_delay = (average_RTT - responder_turnaround) / 2
```

It is not pure cable/PHY propagation delay unless the host controller deliberately places both timestamp reference points at PHY-level boundaries.

## Reuse rule

When integrating into a new communication controller, keep the RTL unchanged if possible. Add controller-specific mapping only in the host adapter layer:

- frame header mapping;
- CRC/FCS insertion/checking;
- MAC/PHY selection;
- FIFO arbitration;
- timestamp capture point;
- delay-register storage.
