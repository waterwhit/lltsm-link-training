# Changelog

## v0.1-lltsm-branch-frozen - 2026-07-08

- Created standalone LLTSM-only repository layout.
- Froze simplified host-controller-controlled link training branch architecture.
- Defined MAC/FIFO-based training-frame adapter boundary.
- Standardized interface naming:
  - `train_tx_*`
  - `train_rx_*`
  - `train_rx_ref_time`
- Defined result as `trained_path_delay`.
- Fixed `train_tx_turnaround` semantics so TX adapter backpressure is included in responder turnaround.
- Declared `E:\aaworkspace\lltsm-link-training` as the active standalone local repository path.
