#!/usr/bin/env bash
# Run ON THE TARGET MACHINE (the one Claude will SSH into), as your normal user.
#
#   ./01-enable-ssh.sh "<your public key line>" [--key-only]
#
# - installs and starts openssh-server
# - adds your public key to ~/.ssh/authorized_keys
# - if ufw is active: allows SSH only from the local network you're on
# - --key-only: also turns off password logins for SSH (keep a keyboard nearby)
set -euo pipefail

PUBKEY="${1:-}"
KEY_ONLY="${2:-}"

if [ -z "$PUBKEY" ]; then
  echo "usage: $0 \"ssh-ed25519 AAAA... you@your-pc\" [--key-only]" >&2
  exit 1
fi
case "$PUBKEY" in
  ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-ed25519@openssh.com\ *) ;;
  *) echo "That doesn't look like a public key line (did you paste the private key?)." >&2; exit 1 ;;
esac
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root." >&2
  exit 1
fi

echo "==> Installing and starting the SSH server"
sudo apt-get update -q
sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh

echo "==> Adding your key"
install -d -m 700 "$HOME/.ssh"
touch "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
grep -qxF "$PUBKEY" "$HOME/.ssh/authorized_keys" || echo "$PUBKEY" >> "$HOME/.ssh/authorized_keys"

if [ "$KEY_ONLY" = "--key-only" ]; then
  echo "==> Turning off SSH password logins"
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' \
    | sudo tee /etc/ssh/sshd_config.d/10-key-only.conf >/dev/null
  sudo sshd -t                      # refuse to restart with a broken config
  sudo systemctl restart ssh
fi

DEV=$(ip route show default | awk '{print $5; exit}')
if [ -z "$DEV" ]; then
  echo "No network connection found. Connect to the same Wi-Fi/router as your PC and run this again." >&2
  exit 1
fi
NET=$(ip -4 route show dev "$DEV" scope link proto kernel | awk '{print $1; exit}')
IP=$(ip -o -4 addr show dev "$DEV" | awk '{print $4; exit}' | cut -d/ -f1)

if [ -n "$NET" ] && command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  echo "==> Firewall: allowing SSH only from $NET"
  sudo ufw allow from "$NET" to any port 22 proto tcp comment 'ssh from LAN (agent session)'
else
  echo "==> ufw is not active: SSH is reachable from anything that can reach this machine."
  echo "    That's usually fine on a home LAN. Never port-forward 22 on your router for this."
fi

echo
echo "Give these to Claude:"
echo "  user: $(whoami)"
echo "  ip:   $IP"
echo
echo "Next: ./02-grant-temp-sudo.sh 4    (temporary sudo that removes itself)"
