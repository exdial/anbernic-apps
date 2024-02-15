#!/usr/bin/env bash
#
# https://github.com/exdial/anbernic-apps

appdir=$(dirname -- "$0")

if [ -d "/etc/ssh" ]; then
  # restore original config
  mv -f /etc/ssh/sshd_config.vendor-backup /etc/ssh/sshd_config

  # switch app entrypoint
  rm -f "$appdir/DisableSSH.sh"
  cp -f "$appdir/EnableDisableSSHd/EnableSSH.sh" "$appdir"
  chmod +x "$appdir/EnableSSH.sh"

  # ensure changes are written to disk
  sync

  # restarting SSHD to apply changes
  systemctl restart sshd
fi
