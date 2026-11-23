#!/usr/bin/env bash
# Run ON THE TARGET MACHINE when the session is over (works over SSH too).
#
#   ./03-revoke-access.sh                                  remove temporary sudo
#   ./03-revoke-access.sh --remove-key "you@your-pc"       ...and the SSH key(s) whose line contains that text
#   ./03-revoke-access.sh --remove-key "you@your-pc" --disable-ssh   ...and stop the SSH server
#
# The sudo rule is deleted LAST, so every earlier step still runs without a password.
set -euo pipefail

REMOVE_KEY=""
DISABLE_SSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --remove-key) REMOVE_KEY="${2:?--remove-key needs the key comment, e.g. you@your-pc}"; shift 2 ;;
    --disable-ssh) DISABLE_SSH=1; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$REMOVE_KEY" ]; then
  AK="$HOME/.ssh/authorized_keys"
  if [ -f "$AK" ]; then
    N=$(grep -cF -- "$REMOVE_KEY" "$AK" || true)
    cp -a "$AK" "$AK.bak"
    grep -vF -- "$REMOVE_KEY" "$AK.bak" > "$AK" || true
    chmod 600 "$AK"
    echo "==> Removed $N key line(s) matching '$REMOVE_KEY' (backup: $AK.bak)"
  fi
fi

echo "==> Removing the expiry timer"
sudo systemctl disable --now claude-sudo-expiry.timer 2>/dev/null || true
sudo rm -f /etc/systemd/system/claude-sudo-expiry.service /etc/systemd/system/claude-sudo-expiry.timer
sudo systemctl daemon-reload

if [ "$DISABLE_SSH" -eq 1 ]; then
  echo "==> Disabling the SSH server (your current session stays open until you log out)"
  sudo systemctl disable ssh ssh.socket 2>/dev/null || true
  sudo systemctl stop ssh.socket 2>/dev/null || true
fi

echo "==> Removing the temporary sudo rule"
sudo rm -f /etc/sudoers.d/90-claude-temp

sudo -k                                   # forget any cached sudo credentials
if sudo -n true 2>/dev/null; then
  echo "WARNING: passwordless sudo STILL works. Another rule grants it. Check: sudo -l"
  exit 2
fi
echo "OK: sudo asks for a password again."
[ "$DISABLE_SSH" -eq 1 ] && echo "SSH is disabled from the next boot (run 'sudo systemctl stop ssh' at the keyboard to stop it now)."
exit 0
