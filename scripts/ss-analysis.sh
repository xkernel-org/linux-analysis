#!/bin/bash
#
# scripts/ss-analysis.sh - Stage 1 of the SS pipeline.
#
# Run the TaintTrackerPass plugin (an LLVM `opt` pass) on a vmlinux
# bitcode file using parameters loaded from a `<name>.input.txt` file
# produced by Phase B (`scripts/locate-const-in-ir.py`). The pass output
# is written to stdout; callers (e.g. `scripts/ss-gen.sh`) typically
# capture it into `<name>.output.txt`.
#
# Usage:
#   bash scripts/ss-analysis.sh [options] <input.txt>
#
# Options:
#   --linux-wllvm DIR   wllvm tree (default: $LINUX_WLLVM)
#   --vmlinux-bc PATH   bitcode to analyse
#                       (default: <linux-wllvm>/vmlinux-xk-dataset.bc,
#                        or $VMLINUX_BC if set)
#   --plugin PATH       libTaintTrackerPass.so
#                       (default: <repo>/passes/build/libTaintTrackerPass.so)
#   --no-upward-interproc
#                       turn off upward interproc taint walk (default: on)
#   --interproc         turn on downward interproc (default: off)
#   --indirect-call     turn on indirect-call taint (default: off)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LINUX_WLLVM_ARG=""
VMLINUX_BC_ARG=""
PLUGIN_ARG=""
INTERPROC=false
UPWARD_INTERPROC=true
INDIRECT_CALL=false
TIMEOUT_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --linux-wllvm)         LINUX_WLLVM_ARG="$2"; shift 2 ;;
        --vmlinux-bc)          VMLINUX_BC_ARG="$2";  shift 2 ;;
        --plugin)              PLUGIN_ARG="$2";      shift 2 ;;
        --interproc)           INTERPROC=true;       shift ;;
        --no-upward-interproc) UPWARD_INTERPROC=false; shift ;;
        --indirect-call)       INDIRECT_CALL=true;   shift ;;
        --timeout)             TIMEOUT_ARG="$2";     shift 2 ;;
        --) shift; break ;;
        --*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

LINUX_WLLVM="${LINUX_WLLVM_ARG:-${LINUX_WLLVM:-}}"
VMLINUX_BC="${VMLINUX_BC_ARG:-${VMLINUX_BC:-${LINUX_WLLVM:+$LINUX_WLLVM/vmlinux-xk-dataset.bc}}}"
PLUGIN="${PLUGIN_ARG:-$REPO_ROOT/passes/build/libTaintTrackerPass.so}"

if [[ -z "$VMLINUX_BC" || ! -f "$VMLINUX_BC" ]]; then
    echo "vmlinux bitcode not found: '$VMLINUX_BC'" >&2
    echo "Pass --vmlinux-bc PATH or set \$LINUX_WLLVM (containing vmlinux-xk-dataset.bc)." >&2
    exit 1
fi

if [[ ! -f "$PLUGIN" ]]; then
    echo "TaintTrackerPass plugin not found: '$PLUGIN'" >&2
    echo "Pass --plugin PATH or build it: cmake -S passes -B passes/build && cmake --build passes/build" >&2
    exit 1
fi

if ! command -v opt >/dev/null 2>&1; then
    export PATH=/usr/lib/llvm-20/bin:$PATH
    if ! command -v opt >/dev/null 2>&1; then
        echo "opt not found in PATH" >&2
        exit 1
    fi
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [options] <input.txt>" >&2
    exit 2
fi

INPUT="$1"
if [[ ! -f "$INPUT" ]]; then
    echo "Input file $INPUT does not exist" >&2
    exit 1
fi

# input.txt is bash-sourced (KEY=value lines).
# shellcheck disable=SC1090
source "$INPUT"

TIMEOUT_CMD=()
if [[ -n "$TIMEOUT_ARG" ]]; then
    TIMEOUT_CMD=(timeout --kill-after=10 "$TIMEOUT_ARG")
fi

"${TIMEOUT_CMD[@]}" \
opt -load-pass-plugin="$PLUGIN" \
    -passes="taint-tracker<$FUNCTION_NAME;$SOURCE_OP;$CONSTANT_VALUE;false;$INTERPROC;$INDIRECT_CALL;$UPWARD_INTERPROC;$OCCURENCE;true>" \
    -disable-output \
    "$VMLINUX_BC"
