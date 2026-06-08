# Shared helpers for setup{,-standalone}.sh.

# apt_source_kernel <dest>
#
# Fetch the Ubuntu kernel source for the running kernel into <dest> using
# `apt-get source`. Mirrors scripts/install_deps.sh::install_kernel_source
# from Xkernel.
apt_source_kernel() {
    local dest="$1"
    local kver="$(uname -r)"

    # If running a custom (non -generic) kernel, fall back to the highest
    # -generic kver installed under /boot, so `apt source` still resolves.
    if [[ "$kver" != *-generic ]]; then
        local fallback
        fallback=$(ls /boot/vmlinuz-*-generic 2>/dev/null \
            | sed 's|^/boot/vmlinuz-||' \
            | sort -V | tail -1)
        if [[ -n "$fallback" ]]; then
            echo "apt_source_kernel: running $kver (non -generic); using $fallback for source lookup" >&2
            kver="$fallback"
        fi
    fi

    local src_pkg=""
    local candidate info_line
    for candidate in "linux-image-unsigned-${kver}" "linux-image-${kver}"; do
        info_line=$(apt-cache show "$candidate" 2>/dev/null | grep -m1 "^Source:" || true)
        if [[ -n "$info_line" ]]; then
            src_pkg=$(echo "$info_line" | awk '{print $2}')
            break
        fi
    done
    if [[ -z "$src_pkg" ]]; then
        echo "Cannot resolve source package for kernel $kver" >&2
        echo "Make sure linux-image-*-${kver} is installed and apt cache is current." >&2
        return 1
    fi

    if ! apt-get indextargets --format '$(CREATED_BY)' 2>/dev/null | grep -q '^Sources$'; then
        if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
            sudo sed -i '/^Types:/ s/\bdeb-src\b//g; /^Types:/ s/\bdeb\b.*/deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
        elif [[ -f /etc/apt/sources.list ]]; then
            sudo sed -i 's/^# *deb-src/deb-src/' /etc/apt/sources.list
        fi
        sudo apt update
    fi

    local pkg_ver
    pkg_ver=$(apt-cache madison "$src_pkg" 2>/dev/null \
        | awk -F'|' '/Sources/ {gsub(/ /,"",$2); print $2}' \
        | sort -V | tail -1)
    if [[ -z "$pkg_ver" ]]; then
        echo "No source version found for $src_pkg" >&2
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    pushd "$tmpdir" > /dev/null
    apt-get source "${src_pkg}=${pkg_ver}"
    local src_dir
    src_dir=$(find . -maxdepth 1 -type d -name 'linux-*' | head -1)
    if [[ -z "$src_dir" || ! -f "$src_dir/Makefile" ]]; then
        echo "Failed to extract kernel source" >&2
        popd > /dev/null
        rm -rf "$tmpdir"
        return 1
    fi
    mv "$src_dir" "$dest"
    popd > /dev/null
    rm -rf "$tmpdir"
}
