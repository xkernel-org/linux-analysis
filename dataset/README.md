# Tunables in Linux 6.8

Difference than Linux 6.14 dataset

|Tunable|Diff|Reason|
|-------|----|------|
|`hystart_delay_max`|+|not in Gist|
|`process_backlog_threshold`|+|not in Gist|
|`BH_WORKER_JIFFIES`|-|not in 6.8|
|`BH_WORKER_RESTARTS`|-|not in 6.8|
|`BLK_ZONE_WPLUG_DEFAULT_POOL_SIZE`|-|not in 6.8|
|`GET_PAGE_MAX_RETRY_NUM`|-|not in 6.8|
|`IO_LOCAL_TW_DEFAULT_MAX`|-|not in 6.8|
|`MAX_MADVISE_GUARD_RETRIES`| |not in 6.8, huge IR diff|
|`MAX_NR_FOLIOS_PER_FREE`|-|not in 6.8|
|`MAX_PARTIAL_TO_SCAN`|-|not in 6.8|
|`MAX_VMAP_RETRIES`| |huge IR diff|
|`MLD_MAX_QUEUE`| |huge IR diff|
|`PEEK_MAX_IMPORT`|-|not in 6.8|
|`XFS_DISCARD_MAX_EXAMINE`|-|not in 6.8|
|`BLK_MQ_MAX_DEPTH`| |definition change|
|`BTRFS_MAX_BIO_SECTORS`| |reference change|
|`BUSY_POLL_BUDGET`| |reference change|
|`IORING_MAX_ENTRIES`| |definition change|
|`KFREE_DRAIN_JIFFIES`| |definition change, reference change|
|`SCHED_NR_MIGRATE_BREAK`| |definition change|
|`TCP_MAX_WSCALE`| |reference change|
|`TCP_INIT_CWND`| |an object would fail to build without `CONFIG_MPTCP`, although it's unclear why we didn't need it in 6.14|
|`TCP_DELACK_MAX`| |huge IR diff (the new `locate-const-in-ir.py` accepted such diff and produced some bogus `*.input.txt` files)|

- "not in Gist": wasn't in the original GitHub Gist
- "not in 6.8": the identifier cannot be found in Linux 6.8
- "huge IR diff": the constant cannot be clearly located in IR thus not
  included in 6.14 dataset in the first place
- "reference change": the macro is used in a different set of files or
  filename has changed, `sed` exactly from 6.14 couldn't work
- "definition change": the macro is defined in a different file or the
  definition line has changed, `sed` exactly from 6.14 couldn't work
