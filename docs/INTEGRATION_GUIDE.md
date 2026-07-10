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
- a MAC/link-frame layer that can send LLTSM payloads on the selected PHY/channel;
- a MAC/link-frame layer that checks received training frames and reports clean LLTSM payloads;
- a local timestamp counter.

## Required host integration path

```text
Host Communication Controller FSM/TOP
  -> ttp_lltsm_branch_fsm
  -> lltsm_tx_payload_formatter
  -> MAC / Link Frame Processing
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Link Frame Processing
  -> lltsm_rx_payload_parser
  -> ttp_lltsm_branch_fsm
```

The FSM must not be wired directly to raw PHY pins. The formatter/parser also do
not implement link adaptation. They only translate between the FSM `train_*`
fields and a fixed, link-independent LLTSM payload stream.

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

### TX payload path

The FSM drives `train_tx_*` fields into `lltsm_tx_payload_formatter`.

`lltsm_tx_payload_formatter` emits an 8-word, 16-bit LLTSM payload stream:

- `lltsm_tx_payload_valid`
- `lltsm_tx_payload_ready`
- `lltsm_tx_payload_start`
- `lltsm_tx_payload_last`
- `lltsm_tx_payload_word`
- `lltsm_tx_payload_words`

It also forwards metadata for the MAC/link-frame layer:

- `lltsm_tx_payload_frame_type`
- `lltsm_tx_payload_src_node_id`
- `lltsm_tx_payload_dst_node_id`
- `lltsm_tx_payload_link_id`
- `lltsm_tx_payload_channel_id`
- `lltsm_tx_payload_training_round_id`
- `lltsm_tx_payload_sequence`

The MAC/link-frame layer uses this metadata to select the current training PHY or
channel, then performs its own framing, padding, address/type mapping, FIFO
arbitration, and CRC/FCS generation. LLTSM does not generate Ethernet FCS,
RS-485 CRC, custom-link CRC, or PHY-specific framing.

`train_tx_ready` is asserted when the final LLTSM payload word is accepted by the
MAC/link-frame layer. Use this point consistently as the TX timestamp reference
or compensate for any later buffering in the host controller.

### RX payload path

The MAC/link-frame layer receives the physical frame, performs address/type
filtering, frame-length checks, SOF/EOF handling, CRC/FCS checking, and timestamp
capture. It then passes only the LLTSM payload into `lltsm_rx_payload_parser`:

- `lltsm_rx_payload_valid`
- `lltsm_rx_payload_ready`
- `lltsm_rx_payload_start`
- `lltsm_rx_payload_last`
- `lltsm_rx_payload_word`
- `lltsm_rx_payload_frame_complete`
- `lltsm_rx_payload_crc_ok`
- `lltsm_rx_payload_ref_time`

`lltsm_rx_payload_parser` decodes this stream and drives the FSM `train_rx_*`
fields, including `train_rx_protocol_ok`, `train_rx_crc_ok`, and
`train_rx_ref_time`.

`train_rx_ref_time` must be the documented RX reference timestamp. In the
low-complexity integration, this can be the MAC/link-frame parser output
boundary timestamp.

## Result meaning

The FSM result is:

```text
trained_path_delay = (average_RTT - responder_turnaround) / 2
```

It is not pure cable/PHY propagation delay unless the host controller deliberately places both timestamp reference points at PHY-level boundaries.

## Reuse rule

When integrating into a new communication controller, keep the LLTSM RTL unchanged if possible. Add controller-specific mapping only in the MAC/link-frame layer:

- PHY/channel selection from LLTSM metadata;
- frame header/address/type mapping;
- Ethernet FCS or RS-485/custom link CRC insertion/checking;
- fixed-frame padding or payload stripping required by the host link;
- FIFO arbitration;
- timestamp capture point;
- delay-register storage.

For example, if an existing link frame has a 10-word payload slot but LLTSM uses
8 payload words, the MAC/link-frame layer should pad two words on TX and strip or
ignore those two words on RX. The reusable LLTSM payload formatter/parser should
remain 8-word modules.