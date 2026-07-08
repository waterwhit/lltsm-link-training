# Version

Current baseline:

```text
v0.1-lltsm-branch-frozen
```

Date: 2026-07-08

Scope:

- Reusable physical-link delay training branch FSM.
- Fixed training frames carried by the host controller FIFO/MAC path.
- A/B or redundant channels trained separately by host-controller scheduling.
- Business traffic frozen by the host controller during training.
- Result interpreted as `trained_path_delay`.
- Asymmetry correction reserved for later calibration.

Verified snapshot:

- FSM behavioral testbench passed.
- FSM Vivado OOC synthesis passed for Xilinx 7K325T.
