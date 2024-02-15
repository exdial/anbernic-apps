#!/usr/bin/env bash
#
# https://github.com/exdial/anbernic-apps

appdir=$(dirname -- "$0")

if [ -d "/etc/ssh" ]; then
  # save original config
  mv -f /etc/ssh/sshd_config /etc/ssh/sshd_config.vendor-backup

  # install openssh-server
  echo 'debconf debconf/frontend select Noninteractive' | \
  debconf-set-selections
  DEBIAN_FRONTEND="noninteractive" apt-get update -y --fix-missing \
    &>/tmp/enable-ssh-update.log
  DEBIAN_FRONTEND="noninteractive" apt-get install -y openssh-server \
    &>/tmp/enable-ssh-install.log
  systemctl enable ssh &>/tmp/enable-ssh-service.log

  # install the new config
  cp -f "$appdir/EnableDisableSSHd/sshd_config" \
    /etc/ssh/sshd_config

  # switch app entrypoint
  rm -f "$appdir/EnableSSH.sh"
  cp -f "$appdir/EnableDisableSSHd/DisableSSH.sh" "$appdir"
  chmod +x "$appdir/DisableSSH.sh"

  # ensure changes are written to disk
  sync

  # reset root password to "root"
  echo "root:root" | chpasswd

  # restarting SSHD to apply changes
  systemctl restart sshd
fi
exit 0
