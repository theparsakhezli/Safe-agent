#!/usr/bin/env bash
# Run ON THE TARGET MACHINE as your normal user.
#
#   ./02-grant-temp-sudo.sh [hours]        (default: 4)
#
# Gives YOUR user passwordless sudo so an agent can run admin commands over a
# non-interactive SSH session, and removes it automatically at expiry.
#
# - the rule is checked with `visudo -cf` BEFORE it's installed, so a typo
#   can never break sudo
# - expiry is a persistent systemd timer: it survives reboots, and fires at
#   the next boot if the machine was off at expiry time
# - remove it early at any time: ./03-revoke-access.sh
set -euo pipefail

HOURS="${1:-4}"
case "$HOURS" in ''|*[!0-9]*) echo "hours must be a whole number" >&2; exit 1 ;; esac
if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root." >&2
  exit 1
fi

ME=$(id -un)
RULE=/etc/sudoers.d/90-claude-temp
UNIT=claude-sudo-expiry
EXPIRES=$(date -d "+${HOURS} hours" '+%Y-%m-%d %H:%M:%S')

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
echo "$ME ALL=(ALL) NOPASSWD:ALL" > "$TMP"

sudo visudo -cf "$TMP"                               # validate first
sudo install -m 0440 -o root -g root "$TMP" "$RULE"
sudo visudo -c >/dev/null                            # whole config still valid

sudo tee /etc/systemd/system/$UNIT.service >/dev/null <<EOF
[Unit]
Description=Remove temporary passwordless sudo (agent session)

[Service]
Type=oneshot
ExecStart=/usr/bin/rm -f $RULE
ExecStart=/usr/bin/systemctl disable $UNIT.timer
EOF

sudo tee /etc/systemd/system/$UNIT.timer >/dev/null <<EOF
[Unit]
Description=Expire temporary passwordless sudo at $EXPIRES

[Timer]
OnCalendar=$EXPIRES
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $UNIT.timer >/dev/null 2>&1
sudo systemctl restart $UNIT.timer          # re-running the script resets the expiry

echo "Passwordless sudo is ON for '$ME' until $EXPIRES."
echo "Check:        sudo -n true && echo works"
echo "Remove early: ./03-revoke-access.sh"
