#!/bin/bash

# This script is used within the container

set -ex

reproducibility_issue() {
    cat << EOF

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

$1

This may result in reproducibility issue and different addresses.

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

EOF
    exit 1
}

cp ../scripts/config-6.8.0-71-generic .config

make olddefconfig

# Disable Ubuntu-specific keys
scripts/config -d CONFIG_SYSTEM_TRUSTED_KEYS
scripts/config -d CONFIG_SYSTEM_REVOCATION_KEYS

# Give an identifiable name
scripts/config --set-str CONFIG_LOCALVERSION "-xkernel"

make olddefconfig

# Tolerate such diffs for now... we will need a more robust solution to lock it
# in apt perhaps.
#
# $ diff .config ../linux-analysis/scripts/config-6.14.0-xkernel
# 5c5
# < CONFIG_CC_VERSION_TEXT="gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0"
# ---
# > CONFIG_CC_VERSION_TEXT="gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0"
if ! diff <(cat .config | sed -E 's|gcc \(Ubuntu 13\.3\.0-6ubuntu2~24\.04\.[0-9]+\) 13\.3\.0|gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0|g') \
          <(cat ../scripts/config-6.14.0-xkernel) \
          >/dev/null 2>&1; then
    reproducibility_issue \
        "The Xkernel config is different from what's expected."
fi

## Some statistics
# 29:25.19 on c6320
# 28:01.91 on c6420
`#/usr/bin/time -v` make -j$(nproc)

nm vmlinux > vmlinux.nm.txt
objdump -d vmlinux > vmlinux.disas.txt

NM1=vmlinux.nm.txt
NM2=../scripts/xkernel.vmlinux.nm.txt
if ! diff \
        <(grep -e ' t ' -e ' T ' $NM1 | sort) \
        <(grep -e ' t ' -e ' T ' $NM2 | sort) \
        > /dev/null 2>&1; then
    reproducibility_issue \
        "The produced vmlinux has t/T symbols with different addresses."
fi

chmod +x ./debian/scripts/sign-module
make INSTALL_MOD_PATH=mods modules_install -j$(nproc)

cd mods
find . -type f -name '*.ko' -print0 |
    while IFS= read -r -d '' ko_file; do
        disas_file="${ko_file}.disas.txt"
        nm_file="${ko_file}.nm.txt"
        echo "Disassembling: $ko_file"
        objdump -d "$ko_file" > "$disas_file"
        nm "$ko_file" > "$nm_file"
    done
