#!/usr/bin/env bash
#
# https://github.com/exdial/anbernic-apps

appdir=$(dirname -- "$0")

# Restore the original configuration if available
if [ -f "/etc/ssh/sshd_config.vendor-backup" ]; then
  mv -f /etc/ssh/sshd_config.vendor-backup /etc/ssh/sshd_config
fi

# Disable and stop the server
systemctl disable ssh &>/tmp/anbernic-ssh-service.log
systemctl stop ssh &>/tmp/anbernic-ssh-service.log

# Switch application entrypoint
rm -f "$appdir/DisableSSH.sh"
cp -f "$appdir/SSH-Enabler/EnableSSH.sh" "$appdir"
chmod +x "$appdir/EnableSSH.sh"

# Ensure the changes are written to disk
sync

exit 0
