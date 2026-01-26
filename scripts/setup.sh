#!/bin/bash

if [[ ! -d $HOME/linux-6.14.0-src || ! -d $HOME/linux-6.14.0-xkernel ]]; then
    echo "Error: Linux source code or GCC build directory not found."
    echo "Please run Xkernel setup first, or run 'setup-standalone.sh' to setup analysis individually."
    exit 1
fi

set -ex

#
# Install prerequisites
#

sudo apt update

# For building Ubuntu kernel using GNU toolchain
sudo apt install -yq git fakeroot build-essential ncurses-dev xz-utils \
    libssl-dev bc flex libelf-dev bison rsync dwarves devscripts

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
export LINUX_SOURCE=$HOME/linux-6.14.0-src
export LINUX_GCC=$HOME/linux-6.14.0-xkernel
export LINUX_WLLVM=$WORKDIR/linux-6.14.0-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH

if ! grep -q "### Xkernel Linux analysis" $HOME/.bashrc >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.bashrc

### Xkernel Linux analysis

export WORKDIR=$HOME/linux-analysis-workdir
export LINUX_SOURCE=$HOME/linux-6.14.0-src
export LINUX_GCC=$HOME/linux-6.14.0-xkernel
export LINUX_WLLVM=$WORKDIR/linux-6.14.0-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH
EOF
fi

mkdir -p $WORKDIR

#
# Clone the analysis repository
#

if [[ ! -d $WORKDIR/linux-analysis ]]; then
    git clone git@github.com:xkernel-org/linux-analysis.git $WORKDIR/linux-analysis
fi

cd $WORKDIR/linux-analysis
git fetch
git reset --hard origin/master

#
# Get Linux source code
#

if [[ ! -f $WORKDIR/.linux-source-done ]]; then
    cp -r $LINUX_SOURCE $LINUX_WLLVM
    touch $WORKDIR/.linux-source-done
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
