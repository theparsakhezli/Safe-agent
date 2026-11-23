# Case study: an unbootable Ubuntu laptop, fixed and upgraded by Claude over SSH

The real session, step by step, with the commands that ran and the output that mattered. Personal details (IP, username, host name, key) are replaced with placeholders.

- **Hardware:** Lenovo laptop, Intel UHD 620, 8 threads, 7 GB RAM, 937 GB disk (73% used)
- **Start:** Ubuntu 24.04.5 LTS. Kernels 7.0.0-38 and 7.0.0-43 wouldn't boot; 6.14.0-36 would
- **End:** Ubuntu 26.04.1 LTS on kernel 7.0.0-43, plus a DevOps toolchain
- **Agent:** Claude Code on a Windows PC on the same Wi-Fi, connecting with `ssh you@<laptop-ip>`

---

## Timeline

| Time | Step |
|---|---|
| 17:07 | Laptop booted on the older kernel (6.14) from GRUB → *Advanced options* |
| 17:07–17:18 | SSH enabled with the PC's key; temporary sudo rule added **with a typo** (`NO PASSWD`) and fixed after `visudo -c`; read-only diagnosis finds 7.0 kernels half-configured with **no initrd.img**; root cause: `virtualbox-dkms` 7.0.16 fails to build for kernel 7.0 |
| 17:19 | VirtualBox packages removed (VMs kept), both kernels configured, initrds generated, GRUB menu set to show for 5 s, reboot. **7.0.0-43 boots.** |
| 17:20–17:24 | Pending 24.04 updates installed; geo-blocked sources (403) disabled; `/etc` backed up |
| 17:24 | `do-release-upgrade` started as a `systemd-run` unit |
| ~17:48 | Downloads finished (~2,300 packages), install phase starts |
| 17:48–18:05 | SSH dropped while `openssh-server` was replaced. The upgrade kept running. |
| 18:16 | Upgrade finished: `Result=success` |
| 18:17 | Reboot. **Ubuntu 26.04.1 LTS**, `systemctl is-system-running` = `running` |
| later | Oracle VirtualBox 7.2.22, Docker mirror, Kubernetes/IaC/CI tools installed |

---

## 1. Getting in

On the laptop:

```bash
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo '<public key of the PC running Claude>' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
hostname -I; whoami
```

From the PC, the first connection:

```text
$ ssh you@<laptop-ip> 'uname -r; lsb_release -ds; sudo -n true'
6.14.0-36-generic
Ubuntu 24.04.5 LTS
/etc/sudoers.d/90-claude-temp:1:20: syntax error
you ALL=(ALL) NO PASSWD:ALL
                 ^~~~~~~
sudo: a password is required
```

The sudo rule had a space in `NOPASSWD`. sudo 1.9 skips the broken line and keeps working. Older versions refuse to run, and then you're locked out of sudo. The fix was to rewrite the file and check it:

```bash
echo "you ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-claude-temp && sudo visudo -c
```

This is why [`02-grant-temp-sudo.sh`](../scripts/02-grant-temp-sudo.sh) validates the rule *before* installing it.

## 2. Diagnosis (read-only)

```text
== kernels installed
ii linux-image-6.14.0-36-generic   6.14.0-36.36~24.04.1
ii linux-image-generic-hwe-24.04   7.0.0-43.43~24.04.1
ii linux-modules-7.0.0-38-generic  ...
ii linux-modules-7.0.0-43-generic  ...

== /boot
initrd.img-6.14.0-36-generic          <- the only initrd
vmlinuz-6.14.0-36-generic
vmlinuz-7.0.0-38-generic              <- no initrd
vmlinuz-7.0.0-43-generic              <- no initrd

== broken pkgs (dpkg --audit)
unpacked but not configured:  virtualbox, virtualbox-qt
half configured:              linux-image-7.0.0-38-generic
                              linux-image-7.0.0-43-generic
                              virtualbox-dkms

== dkms
virtualbox/7.0.16, 6.14.0-36-generic, x86_64: installed
```

A kernel without an initrd can't mount the root filesystem. Retrying the configuration showed why the initrd was never built:

```text
$ sudo dpkg --configure -a
Building module:
make -j8 KERNELRELEASE=7.0.0-43-generic ... (bad exit status: 2)
run-parts: /etc/kernel/postinst.d/dkms exited with return code 11
dpkg: error processing package linux-image-7.0.0-43-generic (--configure)

$ tail /var/lib/dkms/virtualbox/7.0.16/build/make.log
ERROR: modpost: module vboxdrv uses symbol kvm_enable_virtualization from namespace module:kvm-amd,kvm-intel, but does not import it.
ERROR: modpost: module vboxdrv uses symbol kvm_disable_virtualization from namespace module:kvm-amd,kvm-intel, but does not import it.
ERROR: modpost: module vboxdrv uses symbol cr4_update_irqsoff from namespace module:kvm,kvm-amd,kvm-intel, but does not import it.
ERROR: modpost: module vboxdrv uses symbol cr4_read_shadow from namespace module:kvm,kvm-amd,kvm-intel, but does not import it.
```

**Chain of failure:** VirtualBox 7.0.16's kernel module doesn't build on Linux 7.0 → the DKMS hook fails → the kernel's post-install script exits early → `update-initramfs` never runs → no `initrd.img` → the kernel can't boot.

## 3. Fix

Before removing anything, Claude checked what depended on it:

```text
$ ls ~/"VirtualBox VMs"; du -sh ~/"VirtualBox VMs"
CentOS_7.6_minimal  LingomoOS  ubuntu-server  lingmo-os-...iso
4.6G
```

`dpkg --remove` (not purge) leaves VMs and VirtualBox settings in place:

```bash
sudo dpkg --remove virtualbox-qt virtualbox virtualbox-dkms
sudo dpkg --configure -a        # kernels now configure, initramfs gets built
```

```text
Found linux image: /boot/vmlinuz-7.0.0-43-generic
Found initrd image: /boot/initrd.img-7.0.0-43-generic
Found linux image: /boot/vmlinuz-7.0.0-38-generic
Found initrd image: /boot/initrd.img-7.0.0-38-generic
```

Make the boot menu reachable next time, then reboot and test:

```bash
sudo sed -i -e 's/^GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' \
            -e 's/^GRUB_TIMEOUT=0/GRUB_TIMEOUT=5/' /etc/default/grub
sudo update-grub && sudo systemctl reboot
```

```text
7.0.0-43-generic
running
```

## 4. Upgrade 24.04 → 26.04.1 LTS

Pre-flight:

```text
$ sudo do-release-upgrade -c
New release '26.04.1 LTS' available.

$ sudo apt-get update
E: Failed to fetch https://download.docker.com/linux/ubuntu/dists/noble/InRelease  403  Forbidden
E: The repository 'https://apt.releases.hashicorp.com noble Release' no longer has a Release file.
```

Those two sources were geo-blocked on that network. They were renamed to `*.disabled` (not deleted) and `/etc` was backed up:

```bash
cd /etc/apt/sources.list.d && sudo mv docker.list docker.list.disabled && sudo mv hashicorp.list hashicorp.list.disabled
sudo cp -a /etc /root/etc-backup-pre-26.04
```

The upgrade ran as a systemd unit, so it doesn't depend on the SSH session:

```bash
sudo systemd-run --unit=release-upgrade \
  --setenv=DEBIAN_FRONTEND=noninteractive \
  /usr/bin/do-release-upgrade -f DistUpgradeViewNonInteractive
```

Progress was measured, not guessed:

```text
Download  [##############......] 73%   1694/2299 packages, 1.6 GB   (17:42)
Install   [###############.....] 75%   2297 unpacked, 1182/2299 configured   (18:05)
```

About 40 minutes in, the monitoring connection died:

```text
ssh: connect to host <laptop-ip> port 22: Connection refused
```

The upgrade was replacing `openssh-server`. A minute later SSH was back, and the unit was still running. It finished on its own:

```text
release-upgrade.service: Deactivated successfully.
Consumed 11min 18s CPU time over 51min 27s wall clock time, 4.9G memory peak.
Result=success
```

After the reboot:

```text
Ubuntu 26.04.1 LTS
7.0.0-43-generic
running                    # systemctl is-system-running
docker: active (28.3.1)    # docker-ce from the old source was kept
```

## 5. Post-upgrade surprises

**Python from a PPA survived the upgrade.** `pipx` wouldn't install:

```text
pipx : Depends: python3-venv
python3-venv : Depends python3.14-venv (>= 3.14.3)
python3.14            Installed: 3.14.10-1+noble1     <- deadsnakes build for 24.04
python3.14-minimal    Installed: 3.14.4-1ubuntu0.2    <- Ubuntu's build
```

On 26.04, Python 3.14 is the system Python, so a mixed install can break OS tools. The fix was to move back to Ubuntu's build and give the PPA a lower priority so it can't take over again:

```bash
sudo apt-get install --allow-downgrades python3.14=3.14.4-1ubuntu0.2 libpython3.14-stdlib=3.14.4-1ubuntu0.2
printf 'Package: *\nPin: release o=LP-PPA-deadsnakes\nPin-Priority: 100\n' | sudo tee /etc/apt/preferences.d/deadsnakes-low
```

**A truncated binary.** `kubectl` crashed with a segfault:

```text
$ file /usr/local/bin/kubectl
ELF 64-bit LSB executable, x86-64, statically linked, too large section header offset 58597376
$ ls -la /usr/local/bin/kubectl
-rwxr-xr-x 1 root root 1473779 Jan 29 2026 /usr/local/bin/kubectl     # 1.4 MB, should be ~58 MB
```

It was replaced with a checksum-verified download:

```bash
K=$(curl -sL https://dl.k8s.io/release/stable.txt)
curl -sSfLO https://dl.k8s.io/release/$K/bin/linux/amd64/kubectl
curl -sSfL https://dl.k8s.io/release/$K/bin/linux/amd64/kubectl.sha256 | sed 's/$/  kubectl/' | sha256sum -c -
sudo install -m755 kubectl /usr/local/bin/kubectl
```

## 6. Making it DevOps-ready on a restricted network

Docker Hub, Oracle's VirtualBox site and some vendor package sources returned `403` from the laptop's network. The PC running Claude could reach them. So the pattern was:

1. download on the PC,
2. **verify the vendor's SHA256**,
3. `scp` to the laptop and install from the local file.

```text
Oracle_VirtualBox_Extension_Pack-7.2.22.vbox-extpack: OK
virtualbox-7.2_7.2.22-175245~Ubuntu~resolute_amd64.deb: OK
```

Docker pulls go through a regional registry mirror:

```json
{ "registry-mirrors": ["https://<your-registry-mirror>"] }
```

```text
$ docker run --rm hello-world
Hello from Docker!
```

Installed and version-checked:

| Area | Tools |
|---|---|
| Virtualization | VirtualBox 7.2.22 + Extension Pack, Vagrant 2.4.9 |
| Containers | Docker 28.3.1, lazydocker, hadolint, trivy |
| Kubernetes | kubectl 1.37, helm 4, k9s, kind, k3d, minikube, kubectx/kubens, stern |
| IaC | Terraform 1.15, Ansible 2.20 |
| CI / Git | gh, glab, lazygit, act, pre-commit |
| Cloud | AWS CLI v2 |
| Shell | tmux, yq (Go), shellcheck, fzf, ripgrep, fd, bat, btop, direnv, httpie, nmap, mtr, wireguard-tools, pipx |

**Not finished:** a `kind` test cluster came up, but its pods couldn't pull images. kind runs its own containerd, which **doesn't use the host Docker's mirror**. The fix is a containerd `hosts.toml` mirror config mounted into the kind node (and `--registry-config` for k3d). I stopped the session partway through applying it, so it's **not verified** here.

## 7. Being interrupted

I stopped Claude in the middle of that last step. It stopped, didn't retry, and listed what might be half-applied: two test clusters that might still be running, a possibly half-edited `~/.bashrc`, and the temporary sudo rule still active. It also gave me the exact commands to clean up. That's the behaviour you want from an agent with root: when you say stop, it stops, and you know what state it left things in.
