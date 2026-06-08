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

The mutated build produced no value-changing diff hunks. Likely the
constant got constant-folded or DCE'd in 6.8 in ways that hide it.

- `TCP_MAX_WSCALE` — `net/core/filter.c`

## build_error (1)

Unrelated 6.8 build failure in mutated tree (mptcp redefinition):

- `TCP_INIT_CWND`

## timeout (2)

The locator produced runaway diffs (>600 s, thousands of bogus
`input.txt` files). Likely a `_VAL_RE`/`occurrence_of` regression
combined with a wide-impact mutation.

- `MAX_VMAP_RETRIES`
- `MLD_MAX_QUEUE`

**Fix**: investigate the diff manually; may need a more targeted
`sed_pattern` or a locator bug fix.

## Skipped earlier

The two long-running stragglers from prior porting work, which time out
even before E4's `--timeout 300` cap:

- `BLK_MQ_CPU_WORK_BATCH/2`
- `tcp_recovery/1`

See `dataset/UNSUCCESSFUL.md` for details.
