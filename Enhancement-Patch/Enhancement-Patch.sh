#!/usr/bin/env bash
#
# https://github.com/exdial/anbernic-apps

# Configure timezone
echo "Etc/UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
timedatectl set-ntp true

# Configure locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Disable unused services
systemctl stop ModemManager
systemctl disable ModemManager

# We don't want to waste CPU time updating Ubuntu packages
apt -y remove unattended-upgrades
apt -y purge unattended-upgrades

# Configure apt sources
SRCLIST="/etc/apt/sources.list"
mv "${SRCLIST}" "${SRCLIST}.vendor-backup"
rm "${SRCLIST}.back" &>/dev/null
rm -rf /var/lib/apt/lists/* &>/dev/null

echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse" > "${SRCLIST}"
echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse" >> "${SRCLIST}"
echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-backports main restricted universe multiverse" >> "${SRCLIST}"
echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse" >> "${SRCLIST}"

apt-get update
apt-get -y clean
apt-get -y autoclean
apt-get -y autoremove
apt-get -y --fix-broken install

# Apply the changes
reboot
