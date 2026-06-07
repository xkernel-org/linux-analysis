# Unsuccessful tunables (Phase C, Linux 6.8)

Tunables whose `*.input.txt` is in the tree but whose taint-tracker pass
did not complete in a reasonable wall-clock budget on the 6.8
`vmlinux-xk-dataset.bc`. They are intentionally missing `*.output.txt`
and `*.func_offset.json`; revisit when investigating the pass on 6.8.

| Tunable / input            | Pass parameters                                              | Symptom                                                                                              |
| -------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `BLK_MQ_CPU_WORK_BATCH/2`  | `blk_mq_delay_run_hw_queue;store;8;…;upward=true;occ=1`      | Ran >55 min, partial `output.txt` already ~140 KB (baseline-6.14 finished at ~8 KB / 2095 lines).    |
| `tcp_recovery/1`           | `tcp_rack_detect_loss;lshr;2;…;upward=true;occ=1`            | Ran >55 min, partial `output.txt` already ~124 KB (baseline-6.14 finished at ~4 KB / 1180 lines).    |

Same pass flags (downward-interproc OFF, upward ON, indirect-call OFF)
that the 6.14 baseline used. The runs were killed manually; the
parallel driver reported them as `exit code -15` (SIGTERM).

## Suspected cause

Upward-interproc taint propagation explores a much larger caller set
on 6.8 than on 6.14 for these two source instructions. Likely a
combination of:

- different inlining decisions in 6.8 clang / LTO config exposing more
  call sites,
- different `align` / `unnamed_addr` attributes on adjacent functions
  changing what `TaintTrackerPass` considers reachable,
- possibly a pass-internal cycle that only manifests on these IR
  shapes (no termination cutoff is currently enforced).

## What to try

1. Run a single straggler with `-mllvm -debug-only=taint-tracker`
   (after rebuilding the plugin with `LLVM_ENABLE_ASSERTIONS=ON`) to
   see whether the upward walker is making progress or revisiting the
   same callers.
2. Bisect: rerun with `--no-upward-interproc` — confirms the issue
   really is in the upward walk.
3. Add a hop-count / visited-set cap to `TaintTrackerPass` so
   pathological cases at least time out cleanly.
4. Cross-check against `dataset-baseline-6.14/BLK_MQ_CPU_WORK_BATCH/2.output.txt`
   and `dataset-baseline-6.14/tcp_min_rtt/1.output.txt` — which
   call sites does the 6.14 walker visit? Where does the 6.8 walker
   diverge?
