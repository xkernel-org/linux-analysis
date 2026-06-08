#!/bin/bash
#
# Standalone setup: linux-analysis run independently of Xkernel.
#
# Targets Linux 6.8. Mirrors the GCC build steps from Xkernel's
# scripts/install_deps.sh so the resulting $LINUX_GCC tree is byte-compatible
# with what an integrated run would have used.

set -ex

KERNEL_RELEASE=$(uname -r)
case "$KERNEL_RELEASE" in
    6.8.*) ;;
    *)
        echo "Warning: running kernel ($KERNEL_RELEASE) is not 6.8.x."
        echo "linux-analysis currently targets Linux 6.8 only. Aborting."
        exit 1
        ;;
esac

#
# Install prerequisites
#

sudo apt update

# Kernel-build deps (mirrors Xkernel scripts/install_deps.sh)
sudo apt install -yq git fakeroot build-essential ncurses-dev xz-utils \
    libssl-dev bc flex libelf-dev bison dwarves devscripts dpkg-dev

# Misc
sudo apt install -yq cmake bear wget

# LLVM
wget https://apt.llvm.org/llvm.sh -O /tmp/llvm.sh
chmod +x /tmp/llvm.sh
sudo /tmp/llvm.sh 20

# wllvm
sudo apt install -yq python3-pip
PIP_OPTS="--break-system-packages"
if grep -q "no such option: --break-system-packages" <<< $(pip install --break-system-packages 2>&1) >/dev/null 2>&1; then
    PIP_OPTS=""
fi
pip install $PIP_OPTS wllvm==1.3.1

#
# Eliminate SSH interaction in the middle of setup
#

mkdir -p $HOME/.ssh
touch $HOME/.ssh/config
if ! grep -q "### Linux analysis" $HOME/.ssh/config >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.ssh/config

### Linux analysis

Host github.com
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
fi

#
# Environment variables
#

LINUX_GCC=$HOME/linux-6.8.0
LINUX_WLLVM=$HOME/linux-6.8.0-wllvm
export LINUX_GCC LINUX_WLLVM

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH

if ! grep -q "### Linux analysis" $HOME/.bashrc >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.bashrc

### Linux analysis

export LINUX_GCC=$HOME/linux-6.8.0
export LINUX_WLLVM=$HOME/linux-6.8.0-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH
EOF
fi


source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# This script lives at <linux-analysis>/scripts/setup-standalone.sh, so
# the repo root is the parent directory. No clone here -- the user is
# already running from a checkout.
LINUX_ANALYSIS_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#
# Fetch a clean kernel source tree, then materialize $LINUX_WLLVM and
# $LINUX_GCC from it. The wllvm copy is taken before the GCC build dirties
# the tree, so a plain `cp -r` is sufficient (no artifact filtering).
#

if [[ ! -f $LINUX_GCC/vmlinux || ! -d $LINUX_WLLVM ]]; then
    STAGING=$(mktemp -d)/linux-src
    apt_source_kernel "$STAGING"

    if [[ ! -d $LINUX_WLLVM ]]; then
        cp -r "$STAGING" "$LINUX_WLLVM"
    fi

    if [[ ! -f $LINUX_GCC/vmlinux ]]; then
        if [[ ! -d $LINUX_GCC ]]; then
            mv "$STAGING" "$LINUX_GCC"
        fi
        rm -rf "$(dirname "$STAGING")"

        pushd $LINUX_GCC
        if [[ -f /boot/config-${KERNEL_RELEASE} ]]; then
            cp /boot/config-${KERNEL_RELEASE} .config
            scripts/config -d CONFIG_SYSTEM_TRUSTED_KEYS || true
            scripts/config -d CONFIG_SYSTEM_REVOCATION_KEYS || true
            make olddefconfig
        fi
        /usr/bin/time -v make -j$(nproc)
        chmod +x ./debian/scripts/sign-module 2>/dev/null || true
        sudo make modules_install -j$(nproc)
        sudo make install
        popd
    else
        rm -rf "$(dirname "$STAGING")"
    fi
fi

#
# Build LLVM passes
#

cd "$LINUX_ANALYSIS_REPO/passes"
rm -rf build
mkdir build
cd build
cmake .. -DLLVM_DIR=/lib/llvm-20/lib/cmake/llvm
bear -- make -j

#
# Finish setup
#

cat << EOF

###########################################################################

Setup summary:

* Dependencies for building and analyzing the Linux kernel are installed.
* Environment variables are set in ~/.bashrc.
* GCC kernel built at $LINUX_GCC.
* wllvm source tree staged at $LINUX_WLLVM.

Please log out of your current shell and log back in again.

###########################################################################
EOF
