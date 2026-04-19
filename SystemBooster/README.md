# 🎮 RG35XX Plus — System Booster

![SystemBooster](Imgs/SystemBooster.png)

The RG35XX Plus OFW ships with a misconfigured timezone, broken package repositories, unnecessary background services draining CPU and battery, and an undersized userdata partition. System Booster addresses all of it in a single run - no terminal, no manual steps.

[System Booster](https://github.com/exdial/anbernic-apps/tree/master/SystemBooster) builds on the [Enhancement Patch](https://github.com/exdial/anbernic-apps/tree/master/Enhancement-Patch) - taking its core fixes as a baseline and going much further. Kernel parameters, I/O scheduling, memory management, and service configuration are all tuned based on production Linux experience from high-load systems, rethought for the hardware constraints of a handheld.

---

## 📋 Requirements

- Anbernic RG35XX Plus
- Stock firmware (OFW)
- Active internet connection on the device

---

## 🚀 Installation

Download [System Booster](https://github.com/exdial/anbernic-apps/tree/master/SystemBooster) and place it in the apps directory on your SD card. It will appear in the Anbernic app menu automatically. Launch it from the menu - the app will apply all optimizations and reboot the device.

> ⚠️ **The device will reboot automatically upon completion.**

---

<details>
<summary>📖 What it does — full breakdown</summary>

---

### 🌍 Timezone and locale

The stock firmware ships with region-specific timezone and locale settings. The app resets both to universally accepted defaults, ensuring consistent behavior across all regions and tools.

- Sets timezone to `Etc/UTC`
- Sets locale to `en_US.UTF-8`
- Enables NTP synchronization via `timedatectl`

---

### 📦 APT repository fix

The OFW `sources.list` points to broken or vendor-specific mirrors that are either unavailable or misconfigured for the `arm64` architecture. The app replaces it with the official Ubuntu Jammy ports repositories.

```sh
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-backports main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
```

`unattended-upgrades` is removed and purged - it runs background package downloads that waste I/O bandwidth and battery on a handheld device.

---

### ⚙️ Kernel tuning (sysctl)

Written to `/etc/sysctl.d/99-rg35xx.conf` and applied on every boot via `sysctl --system`.

| Parameter                   | Value | Rationale                                       |
| --------------------------- | ----- | ----------------------------------------------- |
| `vm.swappiness`             | `10`  | Prefer RAM over swap; reduce SD card writes     |
| `vm.vfs_cache_pressure`     | `50`  | Retain VFS metadata cache longer                |
| `vm.dirty_ratio`            | `15`  | Defer writeback until 15% of RAM is dirty       |
| `vm.dirty_background_ratio` | `5`   | Start background writeback at 5%                |
| `kernel.nmi_watchdog`       | `0`   | Disable NMI watchdog; reduce interrupt overhead |

---

### 📋 journald tuning

System logs are redirected to RAM, eliminating unnecessary write pressure on the SD card.

- `Storage=volatile` - logs exist in RAM only, cleared on reboot
- `RuntimeMaxUse=4M` / `SystemMaxUse=4M` - hard cap on log memory usage
- `ForwardToSyslog=no` - no duplicate forwarding to rsyslog
- `Compress=no` - compression overhead is not worth it at this log volume
- `RateLimitBurst=50` / `RateLimitIntervalSec=30s` - prevent log flooding

---

### 📡 Wi-Fi power saving

NetworkManager is configured to enable Wi-Fi power save mode (`wifi.powersave=3`). The runtime script additionally calls `iw dev wlan0 set power_save on` on each boot to ensure the setting is applied at the driver level regardless of NetworkManager state.

---

### 💾 tmpfs mounts

`/tmp` and `/var/tmp` are mounted as `tmpfs` to keep temporary file I/O off the SD card entirely.

| Mount point | Size  |
| ----------- | ----- |
| `/tmp`      | 64 MB |
| `/var/tmp`  | 32 MB |

Both entries are appended to `/etc/fstab` only if not already present.

---

### 📂 Partition expansion (p7)

The Anbernic OFW uses the following partition layout on the internal SD card (`mmcblk0`):

| Partition | Type               | Purpose               |
| --------- | ------------------ | --------------------- |
| p1        | FAT32              | Boot                  |
| p2        | FAT16              | Additional boot / env |
| p3        | raw                | Env / config          |
| p4        | Android boot image | Kernel + initramfs    |
| p5        | ext4 (linuxrootfs) | Root filesystem       |
| p6        | ext4 (appfs)       | Apps / overlay        |
| p7        | ext4               | User data             |

Boot sequence: `u-boot → boot.img → initramfs → rootfs`

Flash images are written with a fixed-size p7 that does not fill the entire card. On a 64 GB card this partition may occupy only 8-16 GB, leaving the rest as unallocated space.

The app reclaims this space automatically:

1. Verifies that `/dev/mmcblk0` and `/dev/mmcblk0p7` exist as block devices
2. Reads sector counts from `/sys/block` and computes available unallocated space - skips if less than 2048 sectors (~1 MiB) remain
3. Extends the partition table entry with `parted -s resizepart 7 100%`
4. Notifies the kernel via `partprobe`, falling back to `blockdev --rereadpt` if `partprobe` is unavailable
5. Runs `e2fsck -f -p` (only when the partition is not mounted) followed by `resize2fs`

Exits silently if any required block device or tool is absent - safe to run on firmware variants with a different partition layout.

---

### 🚫 Service cleanup

Services that serve no purpose on a dedicated gaming handheld and contribute to slower boot times, unnecessary background I/O, or wasted RAM:

| Service                           | Reason                                               |
| --------------------------------- | ---------------------------------------------------- |
| `ModemManager`                    | No cellular modem present                            |
| `rsyslog`                         | Redundant with journald                              |
| `cron`                            | Not needed in stock use case                         |
| `systemd-timesyncd`               | Replaced by NTP via `timedatectl`                    |
| `NetworkManager-wait-online`      | Adds several seconds to boot time                    |
| `apt-daily` / `apt-daily-upgrade` | Background package downloads waste I/O and bandwidth |
| `motd-news`                       | Fetches news over the network on terminal login      |
| `unattended-upgrades`             | Silently installs updates without user consent       |

All services are stopped and disabled via `systemctl disable --now`.

---

### ⚡ Runtime booster (runs on every boot)

Installed as a `oneshot` systemd service (`rg35xx-system-booster.service`) that executes once early in the boot sequence, before `multi-user.target`.

**CPU governor** - iterates over all `cpufreq` policy nodes and applies the best available governor in priority order:

```text
schedutil → ondemand → interactive → powersave
```

**I/O scheduler** - applied to `mmcblk0` and `mmcblk1`. Priority order:

```text
mq-deadline → deadline → noop
```

`read_ahead_kb` is set to `128` on each block device to improve sequential read throughput for ROM loading.

**Launcher priority** - `dmenu.bin` (the stock UI process) is reniced to priority `0` to prevent UI stutter under background load.

**Wi-Fi power save** - `iw dev wlan0 set power_save on` is called as a driver-level enforcement in addition to the NetworkManager config.

**Memory trim** - `sync` followed by `echo 1 > /proc/sys/vm/drop_caches` frees the page cache accumulated during the boot process.

---

### 💾 Backup

Before overwriting any configuration file, the original is saved to:

``` text
/root/rg35xx-system-booster-backup/
```

Backups are written once - subsequent runs do not overwrite existing backup files.

---

### 📁 Files installed

| Path                                                | Description                 |
| --------------------------------------------------- | --------------------------- |
| `/usr/local/sbin/rg35xx-system-booster-runtime.sh`  | Runtime optimization script |
| `/etc/systemd/system/rg35xx-system-booster.service` | systemd unit                |
| `/etc/sysctl.d/99-rg35xx.conf`                      | Kernel parameters           |
| `/etc/systemd/journald.conf.d/99-rg35xx.conf`       | journald configuration      |
| `/etc/NetworkManager/conf.d/powersave.conf`         | Wi-Fi power save config     |

</details>

---

<details>
<summary>🔬 Firmware internals — for developers and researchers</summary>

The OFW is based on Ubuntu Jammy (22.04 LTS), ARM64. The internal SD card is exposed as `mmcblk0`.

---

### Partition layout

```sh
lsblk /dev/loop0
NAME      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop0       7:0    0 14.4G  0 loop
├─loop0p1 259:0    0    2G  0 part
├─loop0p2 259:1    0   32M  0 part
├─loop0p3 259:2    0   16M  0 part
├─loop0p4 259:3    0   64M  0 part
├─loop0p5 259:4    0    7G  0 part
├─loop0p6 259:5    0    4G  0 part
└─loop0p7 259:6    0  1.3G  0 part
```

---

### Mount firmware images as loop devices

To inspect or modify firmware images on a Linux host, set them up as loop devices with automatic partition detection:

```sh
losetup -Pf stock.img
losetup -Pf mod.img
```

Verify the result:

```sh
losetup
NAME       SIZELIMIT OFFSET AUTOCLEAR RO BACK-FILE               DIO LOG-SEC
/dev/loop0         0      0         0  0 /mnt/anbernic/stock.img   0     512
/dev/loop1         0      0         0  0 /mnt/anbernic/mod.img     0     512
```

---

### Fix broken partition table

Some modified firmware images ship with a broken partition table - `p7` may be missing or have incorrect sector boundaries. Fix it with `sgdisk` before trying to access the filesystem.

First, get the correct sector boundaries from the stock image:

```sh
sgdisk -p /dev/loop0
```

Find the `p7` entry in the output - note the start sector (first column) and end sector (second column). Then delete the broken `p7` entry on the mod image and recreate it using those values:

```sh
lsblk /dev/loop1
NAME  MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
loop1   7:1    0 13.3G  0 loop
```

```sh
sudo sgdisk -d 7 /dev/loop1
sudo sgdisk -n 7:26773504:27822000 /dev/loop1
```

Here `26773504` is the start sector of `p7` taken from the stock partition table, and `27822000` is the last usable sector of the mod image. Use `0` as the end sector to extend `p7` to the end of the image:

```sh
sudo sgdisk -n 7:26773504:0 /dev/loop1
```

---

### Diff two firmware images

Mount both images and run a recursive diff:

```sh
diff -urN /mnt/stock /mnt/mod > diff.txt
```

---

### Extract and unpack p4 (kernel + initramfs)

`p4` is an Android boot image containing the kernel and initramfs. Extract and unpack it:

```sh
dd if=/dev/loop1p4 of=mod-p4.bin bs=4M
abootimg -x mod-p4.bin
mv initrd.img initrd.gz
gunzip initrd.gz
cpio -idmv < initrd
```

</details>

---

## 🤝 Contributing

Pull requests and issue reports are welcome.
Please test changes on actual hardware before submitting.

---

## 🔗 Links

- [Suggestions and improvements](https://github.com/exdial/anbernic-apps/issues)
