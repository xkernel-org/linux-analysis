# SS/CS Mismatch Notes

Findings from end-to-end sanity check run on 2026-06-09 using
`xkernel-tool build tunables/all.toml --run-analysis` (Linux 6.8,
`vmlinux-xk-dataset.bc`). For three tunables, one or more `func_offset.json`
spans land in a function that Xkernel's CS analysis did **not** identify as a
Critical Span function. Xkernel emits a `⚠ SS function … is NOT among CS
functions` warning and still commits them as manual SS entries.

These are over-approximate but safe. They are filed here for follow-up triage.

---

## tcp_recovery — zero-width span in non-CS function

| Input | Function | Offset | Source |
|-------|----------|--------|--------|
| `1.input.txt` | `tcp_identify_packet_loss` | `0x50 - 0x50` | `net/ipv4/tcp_input.c:3060` |

**CS function (Xkernel):** `tcp_rack_detect_loss`

Two issues:
1. `tcp_identify_packet_loss` is not a CS function.
2. `0x50 - 0x50` is a **zero-width span** — covers no instructions. This
   arises because the taint report only finds the constant at a single
   source line, and the debug-info for that site resolves to a single
   instruction. `ir_to_assembly.py` reports it as a degenerate range;
   `_parse_func_offset_json` swaps `start >= end` but cannot widen it.

**Suggested fix:** investigate whether `tcp_identify_packet_loss` genuinely
observes the tainted value at runtime, or whether it is a spurious
propagation. If spurious, remove `1.input.txt` and regenerate; if real,
file a separate Xkernel issue to extend CS coverage to include
`tcp_identify_packet_loss`.

---

## BLK_MAX_REQUEST_COUNT — span in non-CS function

| Input | Function | Offset | Source |
|-------|----------|--------|--------|
| `1.input.txt` | `blk_start_plug_nr_ios` | `0x2a - 0x53` | `block/blk-core.c:1105` |
| `2.input.txt` | `blk_add_rq_to_plug` | `0x118 - 0x11c` | `block/blk-mq.c:1383` |

**CS function (Xkernel):** `blk_add_rq_to_plug`

Input `1` seeds in `blk_start_plug_nr_ios` (value=32, opcode=`call`) — a
separate compiler occurrence of `BLK_MAX_REQUEST_COUNT` in a different
function. Xkernel found no CS in `blk_start_plug_nr_ios`, so that span is
from a non-CS context. Input `2` matches the CS function correctly.

**Suggested fix:** remove `1.input.txt` (the `blk_start_plug_nr_ios`
occurrence) if `blk_start_plug_nr_ios` is not considered a tunable
observation site, leaving only the CS-matching input.

---

## BLK_MQ_CPU_WORK_BATCH — 10 of 12 spans in non-CS functions

**CS functions (Xkernel):** `blk_mq_delay_run_hw_queue`, `blk_mq_map_swqueue`

The taint walker for `2.input.txt` (`blk_mq_delay_run_hw_queue; store; 8`)
propagates via the `BLK_MQ_CPU_WORK_BATCH` constant through the NVMe/virtio
driver stack (upward-interproc walk). Only `virtblk_poll` is in the output of
input `2`; the remaining 10 spans (all `nvme_*` functions, `hmb_store`) appear
to be interprocedural over-reach.

| Non-CS span | Offset | Source file |
|-------------|--------|-------------|
| `hmb_store` | `0xc5 - 0xcd` | `drivers/nvme/host/pci.c:2202` |
| `nvme_pr_read_keys` | `0x51 - 0xe8` | `drivers/nvme/host/pr.c:218–241` |
| `nvme_pr_read_reservation` | `0x96 - 0xaf` | `drivers/nvme/host/pr.c:256–303` |
| `nvme_probe` | `0x7f4 - 0x812` | `drivers/nvme/host/pci.c:3176–3181` |
| `nvme_report_zones` | `0x6 - 0xd` | `drivers/nvme/host/core.c:2242` |
| `nvme_reset_work` | `0xbd - 0xd9` | `drivers/nvme/host/pci.c:2842–2847` |
| `nvme_resume` | `0x42 - 0x58` | `drivers/nvme/host/pci.c:3304` |
| `nvme_scan_ns` | `0x1ef - 0x5c6` | `drivers/nvme/host/core.c` |
| `nvme_suspend` | `0xd9 - 0xe3` | `drivers/nvme/host/pci.c:3352–3353` |
| `nvme_update_ns_info_block` | `0x6af - 0x6ba` | `drivers/nvme/host/core.c:2127–2128` |

**Suggested fix:** rerun input `2` with `--no-upward-interproc` to check
whether the NVMe functions disappear (confirming they are upward-walk
artefacts). If so, the dataset entry should either use
`--no-upward-interproc` or the input should be narrowed to seed at a deeper
call site closer to the actual storage path.
