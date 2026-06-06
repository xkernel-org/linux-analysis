#!/bin/bash
#
# Build the analysis-target wllvm bitcode (Linux 6.8, vmlinux-xk-dataset.bc).
#
# Source comes from $LINUX_WLLVM, which is staged by setup{,-standalone}.sh as
# a copy of $LINUX_GCC (Xkernel's GCC-built kernel tree). The config recipe is
# the dataset config: defconfig + LTO_CLANG + DWARF + 28 Kconfig enables that
# pull in the modules where the Xkernel tunable dataset's perf-consts live.

set -ex

cd $LINUX_WLLVM

if [[ ! -f $LINUX_WLLVM/.wllvm-patched ]]; then
    git apply - << 'EOF'
diff --git a/arch/x86/boot/compressed/vmlinux.lds.S b/arch/x86/boot/compressed/vmlinux.lds.S
--- a/arch/x86/boot/compressed/vmlinux.lds.S
+++ b/arch/x86/boot/compressed/vmlinux.lds.S
@@ -74,6 +74,9 @@ SECTIONS
 
 	STABS_DEBUG
 	DWARF_DEBUG
+
+	.llvm_bc 0 : { *(.llvm_bc) }
+
 	ELF_DETAILS
 
 	DISCARDS
diff --git a/arch/x86/kernel/vmlinux.lds.S b/arch/x86/kernel/vmlinux.lds.S
--- a/arch/x86/kernel/vmlinux.lds.S
+++ b/arch/x86/kernel/vmlinux.lds.S
@@ -441,6 +441,9 @@ SECTIONS
 
 	STABS_DEBUG
 	DWARF_DEBUG
+
+	.llvm_bc 0 : { *(.llvm_bc) }
+
 	ELF_DETAILS
 
 	DISCARDS
EOF
    touch $LINUX_WLLVM/.wllvm-patched
fi

if [[ ! -f $LINUX_WLLVM/vmlinux-xk-dataset.bc ]]; then
    make CC=wllvm AR=llvm-ar HOSTCC=clang defconfig
    ./scripts/config -e LTO_CLANG
    ./scripts/config -d CONFIG_KVM_WERROR
    ./scripts/config -d WERROR
    ./scripts/config -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig
    ./scripts/config -e INFINIBAND
    ./scripts/config -e SMC
    ./scripts/config -e RDS
    ./scripts/config -e RDS_RDMA
    ./scripts/config -e NET_SCH_PIE
    ./scripts/config -e AMT
    ./scripts/config -e IP_VS
    ./scripts/config -e NFS_V4_1
    ./scripts/config -e PNFS_FLEXFILE_LAYOUT
    ./scripts/config -e MEMORY_FAILURE
    ./scripts/config -e XFS_FS
    ./scripts/config -e BLK_DEV_NVME
    ./scripts/config -e NETFILTER_ADVANCED
    ./scripts/config -e IP_NF_TARGET_SYNPROXY
    ./scripts/config -e TCP_CONG_DCTCP
    ./scripts/config -e TCP_CONG_BBR
    ./scripts/config -e IP_DCCP
    ./scripts/config -e TMPFS_QUOTA
    ./scripts/config -e F2FS_FS
    ./scripts/config -e F2FS_FS_COMPRESSION
    ./scripts/config -e BLK_DEV_ZONED
    ./scripts/config -e NUMA_BALANCING
    ./scripts/config -e TRANSPARENT_HUGEPAGE
    ./scripts/config -e IOSCHED_BFQ
    ./scripts/config -e BTRFS_FS
    ./scripts/config -e MTD
    ./scripts/config -e MTD_UBI
    ./scripts/config -e UBIFS_FS
    ./scripts/config -e NFSD
    make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig

    /usr/bin/time -v make CC=wllvm AR=llvm-ar HOSTCC=clang -j$(nproc)
    /usr/bin/time -v extract-bc vmlinux
    /usr/bin/time -v llvm-dis vmlinux.bc -o vmlinux.ll

    mv vmlinux.bc vmlinux-xk-dataset.bc
    mv vmlinux.ll vmlinux-xk-dataset.ll
fi
