#!/usr/bin/env bash
#
# https://github.com/exdial/anbernic-apps

appdir=$(dirname -- "$0")

# Install OpenSSH server if it doesn't exist
if ! systemctl list-units --full --all | grep -Fqi "ssh.service"; then
  echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
  DEBIAN_FRONTEND="noninteractive" apt-get update -y --fix-missing \
    &>/tmp/anbernic-apt-update.log
  DEBIAN_FRONTEND="noninteractive" apt-get install -y openssh-server \
    &>/tmp/anbernic-apt-install.log
fi

# Install the new OpenSSH server configuration
if [ -f /etc/ssh/sshd_config ]; then
  mv -f /etc/ssh/sshd_config /etc/ssh/sshd_config.vendor-backup
  cp -f "$appdir/SSH-Enabler/sshd_config" /etc/ssh/sshd_config
else
  cp -f "$appdir/SSH-Enabler/sshd_config" /etc/ssh/sshd_config
fi

# Enable and start the server
systemctl enable ssh &>/tmp/anbernic-ssh-service.log
systemctl start ssh &>/tmp/anbernic-ssh-service.log

# Set root password to "root"
echo "root:root" | chpasswd

# Switch application entrypoint
rm -f "$appdir/EnableSSH.sh"
cp -f "$appdir/SSH-Enabler/DisableSSH.sh.src" "$appdir"/DisableSSH.sh
chmod +x "$appdir/DisableSSH.sh"

# Ensure the changes are written to disk
sync

# Restart OpenSSH server to apply the changes
systemctl restart ssh

exit 0
