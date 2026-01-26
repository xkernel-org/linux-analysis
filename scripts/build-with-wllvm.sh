#!/bin/bash

set -ex

cd $LINUX_WLLVM

if [[ ! -f $LINUX_WLLVM/.wllvm-patched ]]; then
    git apply - << 'EOF'
diff --git a/arch/x86/boot/compressed/vmlinux.lds.S b/arch/x86/boot/compressed/vmlinux.lds.S
index 083ec6d77..264d77981 100644
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
index 0deb4887d..ad7377de3 100644
--- a/arch/x86/kernel/vmlinux.lds.S
+++ b/arch/x86/kernel/vmlinux.lds.S
@@ -441,6 +441,8 @@ SECTIONS
 	.llvm_bb_addr_map : { *(.llvm_bb_addr_map) }
 #endif

+	.llvm_bc 0 : { *(.llvm_bc) }
+
 	ELF_DETAILS

 	DISCARDS
EOF
    touch $LINUX_WLLVM/.wllvm-patched
fi

if [[ $DEV_MODE == "1" ]]; then
    true
else
    if [[ ! -f $LINUX_WLLVM/vmlinux-full.bc ]]; then
        cp $WORKDIR/linux-analysis/scripts/config-6.14.0-xkernel .config
        make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig
        ./scripts/config -e LTO_CLANG
        ./scripts/config -d CONFIG_KVM_WERROR
        ./scripts/config -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
        make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig
        sed -i 's/=m/=y/g' .config
        make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig

        # Using -j$(nproc) can hang the system on c6420...
        # 1h18m on c6420
        /usr/bin/time -v make CC=wllvm AR=llvm-ar HOSTCC=clang -j32
        # 40min on c6420
        /usr/bin/time -v extract-bc vmlinux
        # 15min on c6420
        /usr/bin/time -v llvm-dis vmlinux.bc -o vmlinux.ll
        # $ du -sh vmlinux{,.bc,.ll}
        # 2.5G    vmlinux
        # 4.7G    vmlinux.bc
        # 23G     vmlinux.ll

        # An Ubuntu config with all "m" replaced with "y" is super expensive. We
        # may consider a loosened alternative by defconfig and setting "y" for
        # components where some constants from our dataset reside.

        mv vmlinux.bc vmlinux-full.bc
        mv vmlinux.ll vmlinux-full.ll
    fi

    if [[ ! -f $LINUX_WLLVM/vmlinux-defconfig.bc ]]; then
        make CC=wllvm AR=llvm-ar HOSTCC=clang defconfig
        ./scripts/config -e LTO_CLANG
        ./scripts/config -d CONFIG_KVM_WERROR
        ./scripts/config -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
        make CC=wllvm AR=llvm-ar HOSTCC=clang olddefconfig

        # 5min on c6420
        /usr/bin/time -v make CC=wllvm AR=llvm-ar HOSTCC=clang -j32
        # 30s on c6420
        /usr/bin/time -v extract-bc vmlinux
        # 12s on c6420
        /usr/bin/time -v llvm-dis vmlinux.bc -o vmlinux.ll
        # $ du -sh vmlinux{,.bc,.ll}
        # 53M     vmlinux
        # 79M     vmlinux.bc
        # 265M    vmlinux.ll

        mv vmlinux.bc vmlinux-defconfig.bc
        mv vmlinux.ll vmlinux-defconfig.ll
    fi
fi

if [[ ! -f $LINUX_WLLVM/vmlinux-xk-dataset.bc ]]; then
    make CC=wllvm AR=llvm-ar HOSTCC=clang defconfig
    ./scripts/config -e LTO_CLANG
    ./scripts/config -d CONFIG_KVM_WERROR
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

    # 6min on c6420
    /usr/bin/time -v make CC=wllvm AR=llvm-ar HOSTCC=clang -j32
    # 45s on c6420
    /usr/bin/time -v extract-bc vmlinux
    # 16s on c6420
    /usr/bin/time -v llvm-dis vmlinux.bc -o vmlinux.ll
    # $ du -sh vmlinux{,.bc,.ll}
    # 64M     vmlinux
    # 97M     vmlinux.bc
    # 333M    vmlinux.ll

    mv vmlinux.bc vmlinux-xk-dataset.bc
    mv vmlinux.ll vmlinux-xk-dataset.ll
fi
