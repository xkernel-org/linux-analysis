#!/bin/bash

# scripts/ss-gen.sh - End-to-end SS analysis for a single input file.
#
# Pipeline:
#   1. scripts/ss-analysis.sh    - dataflow analysis on vmlinux IR (LLVM bitcode)
#   2. scripts/ir_to_assembly.py - map IR locations to assembly addresses
#
# This works in both modes the repo supports:
#   a) standalone (run independently)
#   b) embedded in the parent xkernel-org/linux-analysis repo
#
# Step 1 reads $VMLINUX_BC (defaults to $LINUX_WLLVM/vmlinux-xk-dataset.bc).
# Step 2 reads $VMLINUX and $MODULES_DIR (defaults to $LINUX_GCC/vmlinux,
# i.e. $HOME/linux-6.8.0/vmlinux, and /lib/modules/$(uname -r)).
#
# Usage:
#   bash scripts/ss-gen.sh <path/to/X.input.txt>
#
# Produces, alongside the input file:
#   <path/to/X.output.txt>          - dataflow analysis log (stage 1)
#   <path/to/X.func_offset.json>    - resolved {function, offset, source_*}
#                                     entries (stage 2)

set -e

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <input.txt>"
    exit 1
fi

INPUT=$1

if [[ ! -f $INPUT ]]; then
    echo "Input file $INPUT does not exist"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_ABS="$(readlink -f "$INPUT")"
OUTPUT="${INPUT_ABS%.input.txt}.output.txt"

if [[ "$OUTPUT" == "$INPUT_ABS" ]]; then
    echo "Input file must end with .input.txt: $INPUT_ABS"
    exit 1
fi

echo "[ss-gen] (1/2) dataflow analysis: $INPUT_ABS -> $OUTPUT"
# ss-analysis.sh runs `opt` whose pass output goes to stderr; capture both.
bash "$SCRIPT_DIR/ss-analysis.sh" "$INPUT_ABS" >"$OUTPUT" 2>&1

FUNC_OFFSET_JSON="${OUTPUT%.output.txt}.func_offset.json"
echo "[ss-gen] (2/2) IR -> assembly mapping: $OUTPUT -> $FUNC_OFFSET_JSON"
python3 "$SCRIPT_DIR/ir_to_assembly.py" "$OUTPUT"
