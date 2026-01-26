#!/bin/bash

set -ex

VMLINUX_BC=${VMLINUX_BC:-$LINUX_WLLVM/vmlinux-xk-dataset.bc}

if [[ ! -f $VMLINUX_BC ]]; then
    echo "VMLINUX_BC not set or does not exist"
    exit 1
fi

if ! command -v opt >/dev/null 2>&1; then
    export PATH=/usr/lib/llvm-20/bin:$PATH
    if ! command -v opt >/dev/null 2>&1; then
        echo "opt not found"
        exit 1
    fi
fi

# Pass options:
INTERPROC=false
UPWARD_INTERPROC=true
INDIRECT_CALL=false

if [[ $# -ne 1 ]]; then
    echo "No input file provided. Use DFR_MAX as example. "
    SOURCE_FILE=net/sunrpc/cache.c
    FUNCTION_NAME=cache_check_rcu
    SOURCE_OP=icmp
    CONSTANT_VALUE=301
    OCCURENCE=1
else
    if [[ ! -f $1 ]]; then
        echo "Input file $1 does not exist"
        exit 1
    fi
    source $1
fi

# FIXME this can be found relative to the current file
opt -load-pass-plugin=$WORKDIR/linux-analysis/passes/build/libTaintTrackerPass.so \
    -passes="taint-tracker<$FUNCTION_NAME;$SOURCE_OP;$CONSTANT_VALUE;false;$INTERPROC;$INDIRECT_CALL;$UPWARD_INTERPROC;$OCCURENCE;true>" \
    -disable-output \
    $VMLINUX_BC
