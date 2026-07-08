# Version

Current baseline:

```text
v0.1-lltsm-branch-frozen
```

Date: 2026-07-08

Scope:

- Simplified TOP-controlled LLTSM branch FSM.
- Fixed training frames carried by the existing controller FIFO/MAC path.
- A/B channels trained separately by TOP scheduling.
- Business traffic frozen during training.
- Result interpreted as `trained_path_delay`.
- Asymmetry correction reserved for later calibration.

Verified snapshot:

- FSM behavioral testbench passed.
- FSM Vivado OOC synthesis passed for Xilinx 7K325T.
