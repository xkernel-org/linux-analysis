#!/bin/bash
#
# Integrated setup: linux-analysis as a step inside the Xkernel pipeline.
#
# Targets Linux 6.8. Reuses the GCC-built kernel that Xkernel's
# scripts/install_deps.sh already produced at $HOME/linux-6.8.0. If that
# directory or its vmlinux is missing, run Xkernel's installer first
# (or run setup-standalone.sh, which mirrors the same build steps).

LINUX_GCC=$HOME/linux-6.8.0

if [[ ! -f $LINUX_GCC/vmlinux ]]; then
    echo "Error: $LINUX_GCC/vmlinux not found."
    echo "Run Xkernel's scripts/install_deps.sh first, or use setup-standalone.sh."
    exit 1
fi

set -ex

#
# Install prerequisites
#

sudo apt update

# For building the Ubuntu kernel using the GNU toolchain (mirrors Xkernel deps)
sudo apt install -yq git fakeroot build-essential ncurses-dev xz-utils \
    libssl-dev bc flex libelf-dev bison dwarves devscripts

# Misc
sudo apt install -yq cmake bear

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
if ! grep -q "### Xkernel Linux analysis" $HOME/.ssh/config >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.ssh/config

### Xkernel Linux analysis

Host github.com
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
fi

#
# Environment variables
#

export WORKDIR=$HOME/linux-analysis-workdir
export LINUX_GCC=$HOME/linux-6.8.0
export LINUX_WLLVM=$WORKDIR/linux-6.8.0-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH

if ! grep -q "### Xkernel Linux analysis" $HOME/.bashrc >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.bashrc

### Xkernel Linux analysis

export WORKDIR=$HOME/linux-analysis-workdir
export LINUX_GCC=$HOME/linux-6.8.0
export LINUX_WLLVM=$WORKDIR/linux-6.8.0-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH
EOF
fi

mkdir -p $WORKDIR

source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

#
# Clone the analysis repository
#

if [[ ! -d $WORKDIR/linux-analysis ]]; then
    git clone git@github.com:xkernel-org/linux-analysis.git $WORKDIR/linux-analysis
    cd $WORKDIR/linux-analysis
    git fetch
    git reset --hard origin/master
fi

#
# Stage a clean kernel source tree for the wllvm build. Fetched independently
# from $LINUX_GCC (which is dirty after Xkernel's GCC build); same recipe as
# Xkernel's scripts/install_deps.sh.
#

if [[ ! -d $LINUX_WLLVM ]]; then
    apt_source_kernel "$LINUX_WLLVM"
fi

#
# Build LLVM passes
#

cd $WORKDIR/linux-analysis/passes
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

Please log out of your current shell and log back in again.

###########################################################################
EOF
