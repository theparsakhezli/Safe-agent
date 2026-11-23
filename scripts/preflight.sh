#!/usr/bin/env bash
# READ-ONLY diagnostics for "the newest kernel won't boot" and pre-upgrade checks.
# Changes nothing. Run on the target, or let the agent run it over SSH:
#
#   ssh user@host 'bash -s' < scripts/preflight.sh
set -uo pipefail

section(){ printf '\n===== %s =====\n' "$1"; }

section "System"
lsb_release -ds 2>/dev/null; uname -r; uptime -p

section "Installed kernel packages (ii = installed, iF/iU = broken, rc = removed)"
dpkg -l 'linux-image-*' 'linux-modules-*' 2>/dev/null | awk '/^[a-zA-Z][a-zA-Z] /{print $1, $2, $3}' | grep -v '^un'

section "/boot: every vmlinuz needs a matching initrd.img"
ls -la /boot | grep -E 'vmlinuz|initrd'
for k in /boot/vmlinuz-*; do
  v=${k#/boot/vmlinuz-}
  [ -e "/boot/initrd.img-$v" ] && echo "ok       $v" || echo "MISSING  initrd for $v   <-- will not boot"
done

section "Half-installed or broken packages"
dpkg --audit
apt-get check 2>&1 | tail -2

section "DKMS modules (third-party kernel modules: VirtualBox, NVIDIA, ...)"
dkms status 2>&1 || echo "(dkms not installed)"

section "Graphics"
lspci -nnk 2>/dev/null | grep -A3 -Ei 'vga|3d|display'

section "Secure Boot"
mokutil --sb-state 2>/dev/null || echo "(mokutil not available)"

section "Boot history"
journalctl --list-boots --no-pager 2>/dev/null | tail -6

section "Errors from the previous boot (needs adm/systemd-journal group, or sudo)"
journalctl -b -1 -p err --no-pager 2>/dev/null | tail -25

section "GRUB defaults"
grep -E '^GRUB_(DEFAULT|TIMEOUT|TIMEOUT_STYLE|CMDLINE_LINUX)' /etc/default/grub

section "Disk space"
df -h / /boot /boot/efi 2>/dev/null | awk '!seen[$0]++'

section "Third-party package sources (most likely to break an upgrade)"
ls /etc/apt/sources.list.d/ 2>/dev/null

section "Failed services"
systemctl --failed --no-legend --no-pager
