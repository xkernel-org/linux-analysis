#!/bin/bash
#
# scripts/ss-gen.sh - End-to-end SS analysis driver.
#
# Pipeline (per <name>.input.txt):
#   1. scripts/ss-analysis.sh    -> <name>.output.txt (taint-tracker pass)
#   2. scripts/ir_to_assembly.py -> <name>.func_offset.json (asm offsets)
#
# Two modes:
#   bash ss-gen.sh [options] <input.txt>
#       Run the pipeline for one input file.
#
#   bash ss-gen.sh [options] --tunable NAME [--dataset DIR]
#       Run the pipeline for every <DIR>/<NAME>/*.input.txt.
#       <DIR> defaults to <repo>/dataset.
#
# Common options (forwarded to the underlying scripts):
#   --linux-wllvm DIR     wllvm tree (default: $LINUX_WLLVM)
#   --vmlinux-bc PATH     bitcode for stage 1 (default: derived from --linux-wllvm)
#   --plugin PATH         libTaintTrackerPass.so (default: <repo>/passes/build/...)
#   --vmlinux PATH        ELF kernel for stage 2 (default: $VMLINUX or
#                         $LINUX_GCC/vmlinux)
#   --modules-dir PATH    .ko modules for stage 2 (default: /lib/modules/$(uname -r))
#
# Stage 1 flags:
#   --interproc, --no-upward-interproc, --indirect-call

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LINUX_WLLVM_ARG=""
VMLINUX_BC_ARG=""
PLUGIN_ARG=""
VMLINUX_ARG=""
MODULES_DIR_ARG=""
TUNABLE=""
DATASET_DIR_ARG=""
STAGE1_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --linux-wllvm)         LINUX_WLLVM_ARG="$2"; shift 2 ;;
        --vmlinux-bc)          VMLINUX_BC_ARG="$2";  shift 2 ;;
        --plugin)              PLUGIN_ARG="$2";      shift 2 ;;
        --vmlinux)             VMLINUX_ARG="$2";     shift 2 ;;
        --modules-dir)         MODULES_DIR_ARG="$2"; shift 2 ;;
        --tunable)             TUNABLE="$2";         shift 2 ;;
        --dataset)             DATASET_DIR_ARG="$2"; shift 2 ;;
        --interproc|--no-upward-interproc|--indirect-call)
                               STAGE1_FLAGS+=("$1"); shift ;;
        --) shift; break ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

DATASET_DIR="${DATASET_DIR_ARG:-$REPO_ROOT/dataset}"

# Build forwarded option lists
STAGE1_OPTS=()
[[ -n "$LINUX_WLLVM_ARG" ]] && STAGE1_OPTS+=(--linux-wllvm "$LINUX_WLLVM_ARG")
[[ -n "$VMLINUX_BC_ARG"  ]] && STAGE1_OPTS+=(--vmlinux-bc  "$VMLINUX_BC_ARG")
[[ -n "$PLUGIN_ARG"      ]] && STAGE1_OPTS+=(--plugin      "$PLUGIN_ARG")
STAGE1_OPTS+=("${STAGE1_FLAGS[@]}")

STAGE2_OPTS=()
[[ -n "$VMLINUX_ARG"     ]] && STAGE2_OPTS+=(--vmlinux     "$VMLINUX_ARG")
[[ -n "$MODULES_DIR_ARG" ]] && STAGE2_OPTS+=(--modules-dir "$MODULES_DIR_ARG")

run_one() {
    local input_abs output func_offset_json
    input_abs="$(readlink -f "$1")"
    output="${input_abs%.input.txt}.output.txt"
    func_offset_json="${output%.output.txt}.func_offset.json"

    if [[ "$output" == "$input_abs" ]]; then
        echo "Input file must end with .input.txt: $input_abs" >&2
        return 1
    fi

    echo "[ss-gen] (1/2) dataflow analysis: $input_abs -> $output"
    bash "$SCRIPT_DIR/ss-analysis.sh" "${STAGE1_OPTS[@]}" "$input_abs" >"$output" 2>&1

    echo "[ss-gen] (2/2) IR -> assembly mapping: $output -> $func_offset_json"
    python3 "$SCRIPT_DIR/ir_to_assembly.py" "${STAGE2_OPTS[@]}" "$output"
}

if [[ -n "$TUNABLE" ]]; then
    if [[ $# -ne 0 ]]; then
        echo "--tunable cannot be combined with a positional <input.txt>" >&2
        exit 2
    fi
    tunable_dir="$DATASET_DIR/$TUNABLE"
    if [[ ! -d "$tunable_dir" ]]; then
        echo "Tunable directory not found: $tunable_dir" >&2
        exit 1
    fi
    inputs=( "$tunable_dir"/[0-9]*.input.txt )
    if [[ ! -f "${inputs[0]}" ]]; then
        echo "No input.txt files in $tunable_dir" >&2
        exit 1
    fi
    rc=0
    for input in "${inputs[@]}"; do
        run_one "$input" || rc=$?
    done
    exit "$rc"
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [options] <input.txt>" >&2
    echo "       $0 [options] --tunable NAME [--dataset DIR]" >&2
    exit 2
fi

run_one "$1"
