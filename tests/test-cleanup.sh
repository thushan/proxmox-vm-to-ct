#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

run_case() {
    mode=$1
    case_dir=$tmp/$mode
    mkdir -p "$case_dir/bin"

    awk '
        /^    cat > "\$cleanup_bin" <<'\''CLEANUP_SCRIPT'\''$/ { copying = 1; next }
        /^CLEANUP_SCRIPT$/ { copying = 0 }
        copying
    ' "$repo/proxmox-vm-to-ct.sh" > "$case_dir/cleanup"

    cat > "$case_dir/bin/dpkg-query" <<'EOF'
#!/bin/sh
printf '%s\n' linux-image-amd64
EOF
    cat > "$case_dir/bin/apt-get" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > /case/apt.args
test "$APT_MODE" = fail && exit 100
grep -q -- '-o DPkg::Lock::Timeout=600' /case/apt.args || exit 64
EOF
    cat > "$case_dir/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod 0755 "$case_dir/cleanup" "$case_dir/bin/"*

    docker run --rm -e APT_MODE="$mode" -v "$case_dir:/case" debian:13-slim sh -c '
        set -e
        mkdir -p /boot/efi /etc/systemd/system/multi-user.target.wants
        : > /boot/efi/marker
        printf "%s\n" "PARTUUID=deadbeef / ext4 defaults 0 1" > /etc/fstab
        : > /etc/systemd/system/proxmox-vm-to-ct-cleanup.service
        ln -s ../proxmox-vm-to-ct-cleanup.service \
            /etc/systemd/system/multi-user.target.wants/proxmox-vm-to-ct-cleanup.service

        set +e
        PATH=/case/bin:$PATH /case/cleanup
        rc=$?
        set -e

        grep -q "^# proxmox-vm-to-ct: PARTUUID=" /etc/fstab
        test ! -d /boot/efi
        grep -q -- "-o DPkg::Lock::Timeout=600" /case/apt.args

        if test "$APT_MODE" = fail; then
            test "$rc" -eq 100
            test -e /case/cleanup
            test -e /etc/systemd/system/proxmox-vm-to-ct-cleanup.service
            test -L /etc/systemd/system/multi-user.target.wants/proxmox-vm-to-ct-cleanup.service
        else
            test "$rc" -eq 0
            test ! -e /case/cleanup
            test ! -e /etc/systemd/system/proxmox-vm-to-ct-cleanup.service
            test ! -e /etc/systemd/system/multi-user.target.wants/proxmox-vm-to-ct-cleanup.service
        fi
    '
}

run_case fail
run_case succeed
