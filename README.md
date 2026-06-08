# linux-analysis

LLVM-based taint analysis that derives Safe Spans (SS) for Xkernel
tunables, plus the dataset of inputs (`dataset/<NAME>/*.input.txt`)
that drives it.

**Targeting Linux 6.8.** Both setup modes assume the host is running a
6.8.x kernel with `/boot/config-$(uname -r)` available.

## Setup

There are two ways to set up the analysis tree:

* **Integrated with Xkernel** (the kernel is already built by Xkernel's
  `scripts/install_deps.sh` at `~/linux-6.8.0`):

  ```shell
  bash scripts/setup.sh
  ```

* **Standalone** (no Xkernel checkout; mirrors Xkernel's GCC kernel-build
  steps to produce `~/linux-6.8.0` itself):

  ```shell
  bash scripts/setup-standalone.sh
  ```

As prompted, log out of the current shell and log back in again.

Both modes stage `$LINUX_WLLVM = ~/linux-analysis-workdir/linux-6.8.0-wllvm`
as a copy of `$LINUX_GCC = ~/linux-6.8.0`. Build the wllvm bitcode for
analysis:

```shell
bash scripts/build-with-wllvm.sh
```

## Running the analysis

The single entry point is `scripts/ss-gen.sh`. It runs both stages
(LLVM taint pass → IR-to-assembly translation) and caches the
intermediate `*.output.txt` and final `*.func_offset.json` next to each
input file.

Run for one named tunable (iterates every `dataset/<NAME>/*.input.txt`):

```shell
bash scripts/ss-gen.sh --tunable BLK_MAX_REQUEST_COUNT
```

Run for one explicit input file:

```shell
bash scripts/ss-gen.sh dataset/BLK_MAX_REQUEST_COUNT/1.input.txt
```

Run for the whole dataset in parallel:

```shell
python scripts/ss-analysis-parallel.py --linux-wllvm "$LINUX_WLLVM"
```

### Flags

`ss-gen.sh` (and the underlying `ss-analysis.sh` / `ir_to_assembly.py`)
take only flags — no `$WORKDIR` is required.

| Flag                  | Default                                          |
|-----------------------|--------------------------------------------------|
| `--linux-wllvm DIR`   | `$LINUX_WLLVM`                                   |
| `--vmlinux-bc PATH`   | `<linux-wllvm>/vmlinux-xk-dataset.bc`            |
| `--plugin PATH`       | `<repo>/passes/build/libTaintTrackerPass.so`     |
| `--vmlinux PATH`      | `$VMLINUX`, `$LINUX_GCC/vmlinux`, `~/linux-6.8.0/vmlinux` |
| `--modules-dir PATH`  | `/lib/modules/$(uname -r)`                       |
| `--dataset DIR`       | `<repo>/dataset`                                 |
| `--tunable NAME`      | (mode flag; see above)                           |

Pass-tuning flags forwarded to the LLVM taint pass: `--interproc`,
`--no-upward-interproc`, `--indirect-call`. Defaults match the
6.14 baseline used to bootstrap the dataset.

## Output

For each `dataset/<NAME>/<N>.input.txt`, `ss-gen.sh` writes:

* `<N>.output.txt` — raw IR-level taint report (stage 1).
* `<N>.func_offset.json` — list of
  `{function, offset: "0xNN - 0xMM", source_start, source_end}`
  entries (stage 2). This is what Xkernel consumes.

## Integration with Xkernel

Xkernel discovers this checkout via the sibling-of-Xkernel convention
(`<xkernel_parent>/linux-analysis`), with an in-tree fallback for
development layouts. When invoked with `--run-analysis`,
`xkernel-tool build` shells out to `scripts/ss-gen.sh --tunable <NAME>`
and parses the resulting JSON directly. See
[Xkernel's `docs/ss-analysis.md`](../docs/ss-analysis.md) for the full
flow.

## Stragglers

A small number of inputs currently time out the LLVM pass on 6.8 IR
(>55 minutes). They are listed in
[`dataset/UNSUCCESSFUL.md`](dataset/UNSUCCESSFUL.md) and skipped by
Xkernel's auto-SS fallback.
