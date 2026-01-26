#!/bin/bash

set -ex

cd $LINUX_GCC

sudo docker run --name kernel-builder-24.04 --rm \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    -v "$LINUX_GCC:/work/linux" \
    -v "$WORKDIR/linux-analysis/scripts:/work/scripts" \
    -w /work/linux \
    kernel-builder:24.04 \
    bash ../scripts/build-with-gcc-inner.sh
