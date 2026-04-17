#!/bin/sh
#
# ============================================================
# RG35XX Plus — System Booster
# Stock Firmware Optimization Patch
#
# https://github.com/exdial/anbernic-apps
# ============================================================

set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin

[ "$(id -u)" = "0" ] || exit 1

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------

SERVICE_NAME="rg35xx-optimizer.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
RUNTIME_SCRIPT="/usr/local/sbin/rg35xx-optimizer-runtime.sh"

SYSCTL_FILE="/etc/sysctl.d/99-rg35xx.conf"

JOURNALD_DIR="/etc/systemd/journald.conf.d"
JOURNALD_FILE="$JOURNALD_DIR/99-rg35xx.conf"

NM_DIR="/etc/NetworkManager/conf.d"
NM_FILE="$NM_DIR/powersave.conf"

APT_LIST="/etc/apt/sources.list"

BACKUP_DIR="/root/rg35xx-optimizer-backup"

# ------------------------------------------------------------
# Preparation
# ------------------------------------------------------------

mkdir -p "$BACKUP_DIR"
mkdir -p /usr/local/sbin
mkdir -p /etc/sysctl.d
mkdir -p "$JOURNALD_DIR"
mkdir -p "$NM_DIR"

backup_file() {
    f="$1"
    [ -f "$f" ] || return 0
    b="$BACKUP_DIR/$(basename "$f")"
    [ -f "$b" ] || cp -a "$f" "$b"
}

# ------------------------------------------------------------
# Timezone / locale
# ------------------------------------------------------------

echo "Etc/UTC" > /etc/timezone
ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime || true

dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true
timedatectl set-ntp true >/dev/null 2>&1 || true

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
printf 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale

locale-gen en_US.UTF-8 >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 || true

# ------------------------------------------------------------
# APT repositories
# ------------------------------------------------------------

backup_file "$APT_LIST"
rm -rf /var/lib/apt/lists/* >/dev/null 2>&1 || true

cat > "$APT_LIST" <<EOF
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-backports main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOF

apt-get update >/dev/null 2>&1 || true
apt-get -y remove unattended-upgrades >/dev/null 2>&1 || true
apt-get -y purge  unattended-upgrades >/dev/null 2>&1 || true
apt-get -y clean >/dev/null 2>&1 || true
apt-get -y autoclean >/dev/null 2>&1 || true
apt-get -y autoremove >/dev/null 2>&1 || true
apt-get -y --fix-broken install >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Persistent sysctl tuning
# ------------------------------------------------------------

backup_file "$SYSCTL_FILE"

cat > "$SYSCTL_FILE" <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
kernel.nmi_watchdog=0
EOF

# ------------------------------------------------------------
# journald — volatile, minimal RAM footprint
# ------------------------------------------------------------

backup_file "$JOURNALD_FILE"

cat > "$JOURNALD_FILE" <<EOF
[Journal]
Storage=volatile
RuntimeMaxUse=4M
SystemMaxUse=4M
ForwardToSyslog=no
Compress=no
RateLimitIntervalSec=30s
RateLimitBurst=50
EOF

# ------------------------------------------------------------
# NetworkManager — Wi-Fi power save
# ------------------------------------------------------------

backup_file "$NM_FILE"

cat > "$NM_FILE" <<EOF
[connection]
wifi.powersave=3
EOF

# ------------------------------------------------------------
# tmpfs mounts
# ------------------------------------------------------------

grep -q '^tmpfs /tmp ' /etc/fstab 2>/dev/null || \
  echo "tmpfs /tmp     tmpfs defaults,noatime,nosuid,size=64m 0 0" >> /etc/fstab

grep -q '^tmpfs /var/tmp ' /etc/fstab 2>/dev/null || \
  echo "tmpfs /var/tmp tmpfs defaults,noatime,nosuid,size=32m 0 0" >> /etc/fstab

mount -a >/dev/null 2>&1 || true

# ------------------------------------------------------------
# Expand partition p7 on mmcblk0 (ext4) to full card size
# ------------------------------------------------------------
# Steps:
#   1. Check that mmcblk0 and mmcblk0p7 exist.
#   2. Compare partition end vs disk size — skip if already full.
#   3. parted resizepart 7 100% — extend the partition table entry.
#   4. partprobe — tell the kernel about the new layout.
#   5. e2fsck (offline only) + resize2fs — grow the ext4 filesystem.
#   Exits silently on any missing device or tool.
# ------------------------------------------------------------

expand_p7() {
  DISK="mmcblk0"
  PART_NUM="7"
  PART_DEV="/dev/${DISK}p${PART_NUM}"
  DISK_DEV="/dev/${DISK}"

  # Abort if the devices don't exist
  [ -b "$DISK_DEV" ] || return 0
  [ -b "$PART_DEV" ] || return 0

  # Abort if required tools are missing
  command -v parted >/dev/null 2>&1 || return 0
  command -v resize2fs >/dev/null 2>&1 || return 0

  # Compare partition end sector with total disk sectors
  DISK_SECTORS=$(cat /sys/block/${DISK}/size 2>/dev/null || echo 0)
  PART_START=$(cat /sys/block/${DISK}/${DISK}p${PART_NUM}/start 2>/dev/null || echo 0)
  PART_SIZE=$(cat /sys/block/${DISK}/${DISK}p${PART_NUM}/size 2>/dev/null || echo 0)
  PART_END=$((PART_START + PART_SIZE))

  # Skip if less than 2048 free sectors remain (~1 MiB slack)
  AVAILABLE=$((DISK_SECTORS - PART_END))
  [ "$AVAILABLE" -gt 2048 ] || return 0

  # Extend the partition table entry
  parted -s "$DISK_DEV" resizepart "$PART_NUM" 100% >/dev/null 2>&1 || return 0

  # Inform the kernel of the updated layout
  # partprobe is preferred; fall back to blockdev --rereadpt if absent
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "$DISK_DEV" >/dev/null 2>&1 || true
  else
    blockdev --rereadpt "$DISK_DEV" >/dev/null 2>&1 || true
  fi

  # Run fsck only when the partition is not currently mounted
  if ! grep -q "^${PART_DEV} " /proc/mounts 2>/dev/null; then
    e2fsck -f -p "$PART_DEV" >/dev/null 2>&1 || true
  fi

  # Grow the filesystem to fill the new partition size
  resize2fs "$PART_DEV" >/dev/null 2>&1 || true
}

expand_p7

# ------------------------------------------------------------
# Disable unnecessary services
# ------------------------------------------------------------

for svc in \
  ModemManager.service \
  rsyslog.service \
  cron.service \
  systemd-timesyncd.service \
  NetworkManager-wait-online.service \
  apt-daily.service \
  apt-daily.timer \
  apt-daily-upgrade.service \
  apt-daily-upgrade.timer \
  motd-news.service \
  motd-news.timer \
  unattended-upgrades.service
do
  systemctl disable --now "$svc" >/dev/null 2>&1 || true
done

# ------------------------------------------------------------
# Runtime optimization script
# ------------------------------------------------------------

cat > "$RUNTIME_SCRIPT" <<'EOF'
#!/bin/sh
set -eu

PATH=/usr/sbin:/usr/bin:/sbin:/bin

# CPU governor: prefer schedutil > ondemand > interactive > powersave
set_governor() {
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -f "$p/scaling_available_governors" ] || continue
    GOVS=$(cat "$p/scaling_available_governors")
    for g in schedutil ondemand interactive powersave; do
      echo "$GOVS" | grep -qw "$g" || continue
      echo "$g" > "$p/scaling_governor" 2>/dev/null || true
      break
    done
  done
}

# I/O scheduler: prefer mq-deadline > deadline > noop
set_scheduler() {
  for d in /sys/block/mmcblk0 /sys/block/mmcblk1; do
    [ -f "$d/queue/scheduler" ] || continue
    SCH=$(cat "$d/queue/scheduler")
    for s in mq-deadline deadline noop; do
      echo "$SCH" | grep -qw "$s" || continue
      echo "$s" > "$d/queue/scheduler" 2>/dev/null || true
      break
    done
    echo 128 > "$d/queue/read_ahead_kb" 2>/dev/null || true
  done
}

# Give the launcher normal priority (avoids UI lag)
tune_launcher() {
  PID=$(pgrep -f dmenu.bin 2>/dev/null | head -n 1 || true)
  [ -n "$PID" ] && renice 0 -p "$PID" >/dev/null 2>&1 || true
}

# Wi-Fi power save via iw (in addition to NetworkManager config)
wifi_ps() {
  if command -v iw >/dev/null 2>&1; then
    iw dev wlan0 set power_save on >/dev/null 2>&1 || true
  fi
}

# Drop page cache to free memory after boot
trim_memory() {
  sync
  echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
}

set_governor
set_scheduler
tune_launcher
wifi_ps
trim_memory

exit 0
EOF

chmod 755 "$RUNTIME_SCRIPT"

# ------------------------------------------------------------
# systemd unit
# ------------------------------------------------------------

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=RG35XX Plus Runtime Optimizer
After=local-fs.target systemd-sysctl.service
Before=multi-user.target

[Service]
Type=oneshot
ExecStart=$RUNTIME_SCRIPT
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------------------------
# Apply and reboot
# ------------------------------------------------------------

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true

systemctl restart systemd-journald >/dev/null 2>&1 || true
systemctl restart NetworkManager >/dev/null 2>&1 || true

sysctl --system >/dev/null 2>&1 || true
systemctl start "$SERVICE_NAME" >/dev/null 2>&1 || true

sync
sleep 2
reboot
