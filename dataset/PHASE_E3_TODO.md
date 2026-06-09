# Phase E3: Locator Pass Results

After porting 135 mutation specs from the Linux 6.14 baseline dataset to
6.8 (Phase E1) and adding a `--timeout` cap to the taint pass (E2), the
locator (`scripts/locate-const-in-ir.py`) was run over each new tunable
to derive `<idx>.input.txt` files. Of 134 candidates:

- **114 succeeded** — `*.input.txt` files committed alongside `mutation.toml`.
- **20 failed** — listed below by failure category. These need hand-fix
  before the taint analysis (Phase E4) can run on them.

## sed_miss (14)

The `sed_pattern` in `mutation.toml` did not match any line in the 6.8
definition file. The macro was either renamed, moved, or its value
changed between 6.8 and 6.14.

- `BH_WORKER_JIFFIES`
- `BH_WORKER_RESTARTS`
- `BLK_MQ_MAX_DEPTH`
- `BLK_ZONE_WPLUG_DEFAULT_POOL_SIZE`
- `GET_PAGE_MAX_RETRY_NUM`
- `IORING_MAX_ENTRIES`
- `IO_LOCAL_TW_DEFAULT_MAX`
- `KFREE_DRAIN_JIFFIES`
- `MAX_MADVISE_GUARD_RETRIES`
- `MAX_NR_FOLIOS_PER_FREE`
- `MAX_PARTIAL_TO_SCAN`
- `PEEK_MAX_IMPORT`
- `SCHED_NR_MIGRATE_BREAK`
- `XFS_DISCARD_MAX_EXAMINE`

**Fix**: open the corresponding header in `$LINUX_WLLVM`, find the
current 6.8 definition (or note it's absent), update
`dataset/<NAME>/mutation.toml` accordingly, and re-run the locator.

## missing_source (2)

The `source_file` referenced by `mutation.toml` does not exist in 6.8:

- `BTRFS_MAX_BIO_SECTORS` — `fs/btrfs/direct-io.c` (added post-6.8)
- `BUSY_POLL_BUDGET` — `io_uring/napi.c` (added post-6.8)

**Fix**: pick a different occurrence site that exists in 6.8, or skip.

## no_diff (1)

The locator built origin-value and mutated-value `.ll` files and diffed
them, but the diff had no value-changing hunks. The most likely cause
is **dead code elimination (DCE)**: clang folded the constant into a
comparison, proved the comparison's outcome at compile time, and DCE'd
the dependent branch. With no IR site referring to the value there is
nothing for the locator to point at.

- `TCP_MAX_WSCALE` — `net/core/filter.c`

**Suggested fix**: pick a different occurrence site (or a different
`source_file`) where the constant participates in a runtime decision
that survives optimization.

## build_error (1)

The build failed in the *mutated* tree, but not because of our `sed`.
The error is a pre-existing 6.8 + clang-20 incompatibility in mptcp
headers:

```
net/mptcp/protocol.h:261:8: error: redefinition of 'mptcp_sock'
net/mptcp/protocol.h:368:53: error: no member named 'sk' in 'struct mptcp_sock'
```

`net/mptcp/protocol.h` is transitively included by tcp\_input.c, so
the same error would reproduce on the unmutated tree.

- `TCP_INIT_CWND`

**Suggested fix**: either patch the mptcp header for clang-20
compatibility, or route the mutation through a different `source_file`
that doesn't pull in mptcp.

## timeout (2)

The locator produced **thousands** of bogus `*.input.txt` files
(`1000.input.txt`, `1366.input.txt`, ...) before hitting the 600 s
wrapper timeout. Normal output is 1–13 files per tunable.

- `MAX_VMAP_RETRIES`
- `MLD_MAX_QUEUE`

**Root cause** (latent since Phase B): `_VAL_RE` in
`scripts/locate-const-in-ir.py` is a regex that scans a single IR file
for the constant value (e.g. `i32 3`). When the mutated value collides
with other compiler-introduced integers — loop indices, array sizes,
struct offsets, constant-pool entries — the regex matches all of them
and each spurious match is emitted as another input. Phase B saw a
single bad input on `BLK_MQ_RESOURCE_DELAY` (CV=0 vs baseline 3); here
the collision count exploded.

**Suggested fix**: replace the single-IR regex scan with a **token
diff** between the origin `.ll` and mutated `.ll`. Only positions whose
token actually changed between origin and mutated should be emitted.
This is a real bug in the locator, not bad mutation data.

**Fix**: investigate the diff manually; may need a more targeted
`sed_pattern` or a locator bug fix.

## Skipped earlier

The two long-running stragglers from prior porting work, which time out
even before E4's `--timeout 300` cap:

- `BLK_MQ_CPU_WORK_BATCH/2`
- `tcp_recovery/1`

See `dataset/UNSUCCESSFUL.md` for details.
