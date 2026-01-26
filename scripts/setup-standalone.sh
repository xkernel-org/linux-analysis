#!/bin/bash

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
if ! grep -q "### Linux analysis" $HOME/.ssh/config >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.ssh/config

### Linux analysis

Host github.com
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
fi

#
# Install Docker
#

# Add Docker's official GPG key:
sudo apt update
sudo apt install -yq ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker $USER

#
# Environment variables
#

export WORKDIR=$HOME/linux-analysis-workdir
export LINUX_SOURCE=$WORKDIR/linux-source
export LINUX_GCC=$WORKDIR/linux-gcc
export LINUX_WLLVM=$WORKDIR/linux-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH

if ! grep -q "### Linux analysis" $HOME/.bashrc >/dev/null 2>&1; then
    cat << 'EOF' >> $HOME/.bashrc

### Linux analysis

export WORKDIR=$HOME/linux-analysis-workdir
export LINUX_SOURCE=$WORKDIR/linux-source
export LINUX_GCC=$WORKDIR/linux-gcc
export LINUX_WLLVM=$WORKDIR/linux-wllvm

export LLVM_COMPILER=clang
export PATH=/lib/llvm-20/bin:$PATH
EOF
fi

mkdir -p $WORKDIR

#
# Clone this repository
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
    TMPDIR=$(mktemp -d)
    mkdir -p $TMPDIR
    cd $TMPDIR
    dget -u https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/linux/6.14.0-15.15/linux_6.14.0-15.15.dsc
    cp -r linux-6.14.0 $LINUX_SOURCE
    cp -r linux-6.14.0 $LINUX_GCC
    cp -r linux-6.14.0 $LINUX_WLLVM
    cd $WORKDIR
    rm -r $TMPDIR

    touch $WORKDIR/.linux-source-done
fi

#
# Build the Docker image for GCC build
#
# This is particularly containerized (Ubuntu 24.04 base) to achieve the
# best binary reproducibility as the deployed kernel.
#

cd $WORKDIR/linux-analysis/docker
sudo docker build -t kernel-builder:24.04 .

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

Setup summary:

* Dependencies for building and analyzing the Linux kernel are installed.
* Docker is installed. "$USER" is added to "docker" group.
* Environment variables are set in ~/.bashrc.
* Source code of Linux and our analysis tools are downloaded.
* A Docker image for building the Linux kernel is created.

Please log out of your current shell and log back in again.

###########################################################################
EOF
