# Physical Link Delay Training FSM Frozen Scheme

Date: 2026-07-08

## 1. Frozen Decision

The current standalone training FSM measures trained path delay, not pure physical link propagation delay.

The selected timestamp reference points are allowed to be located at the host-controller-side training-frame boundary:

- TX reference point: the moment the training frame is accepted by the TX FIFO or TX frame adapter.
- RX reference point: the moment the RX parser identifies and presents a valid training frame to the training branch.

This scheme is accepted for the current implementation because normal traffic is frozen during training, so FIFO queueing delay is deterministic or negligible. Later synchronization compensation must use the same reference-point definition.

## 2. Delay Meaning

The measured value should be named as:

```text
trained_path_delay
```

or:

```text
host_controller_to_host_controller_delay
```

It should not be described as pure:

```text
physical_link_delay
```

because the measured path may include:

- host-controller TX FIFO/frame-adapter delay;
- frame header/address/type processing;
- CRC/FCS processing;
- MAC fixed processing delay;
- PHY fixed processing delay;
- physical link propagation delay;
- host-controller RX parsing delay.

## 3. Required Consistency Rule

The scheme is valid only if the following rules are kept:

1. The TX and RX timestamp reference points are fixed and documented.
2. Training frames and later compensated business frames use the same controller path.
3. Business traffic is frozen during training.
4. The TX FIFO/MAC arbitration delay during training is deterministic or negligible.
5. The same reference-point definition is used in later time synchronization compensation.

## 4. RTL Naming Note

The current RTL interface has been renamed to use reference-point terminology:

```verilog
train_rx_ref_time
request_tx_ref_time
response_rx_ref_time
```

In the frozen low-complexity integration, these names mean selected timestamp reference points. They do not necessarily mean physical MAC/PHY SOF timestamps.

The external FSM ports now use `train_tx_*` and `train_rx_*` names to show that the FSM connects to the host training-frame adapter boundary, not directly to the PHY.

The response node drives `train_tx_turnaround` from the actual response-frame TX adapter handshake reference point. Therefore TX adapter backpressure during training is included in the responder turnaround and is subtracted by the request node instead of being misinterpreted as link delay.

## 5. Integration Boundary

The correct system path is:

```text
Host Communication Controller FSM/TOP
  -> Training Branch FSM + Codec
  -> TX FIFO / TX Frame Adapter
  -> MAC / Media Adapter
  -> PHY
  -> adjacent node
  -> PHY
  -> MAC / Media Adapter
  -> RX Parser / RX FIFO
  -> Training Branch FSM + Codec
```

The training branch does not directly drive the PHY.

## 6. Compensation Formula Interpretation

The FSM still calculates:

```text
mean_delay = (average_RTT - responder_turnaround) / 2
```

Under this frozen scheme, `mean_delay` means the mean trained-path delay between the selected local and remote controller reference points.

It is suitable for host-controller-level synchronization compensation as long as the same path definition is used consistently.
