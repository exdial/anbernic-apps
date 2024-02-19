#!/usr/bin/env bash
#
# Theme: https://github.com/exdial/anbernic-apps
# Art: Aron Visuals
#      Ash Edmonds
#      Jr Korpa
#      Lorenzo Herrera
#      Mohammad Alizade

appdir=$(dirname -- "$0")

# Install the new Anbernic theme
if [ -d "/mnt/vendor" ]; then
  cp -rf "$appdir"/TheRealRetro-Theme/* /mnt/vendor/
  find /mnt/vendor -name .DS_Store -delete
  find /mnt/vendor -name ._* -delete
  sync
fi

# Install boot logo
if [ ! -d "/mnt/bootlogomount" ]; then
  # Mount boot partition
  mkdir /mnt/bootlogomount
  mount /dev/mmcblk0p2 /mnt/bootlogomount

  # Copy logo file itself
  cp "$appdir/TheRealRetro-Theme/res1/boot/bootlogo.bmp" \
    /mnt/bootlogomount/bootlogo.bmp
  find /mnt/bootlogomount -name .DS_Store -delete
  find /mnt/bootlogomount -name ._* -delete

  # Ensure changes are written to disk
  sync

  # Umount boot partition
  umount /mnt/bootlogomount
  rmdir /mnt/bootlogomount
fi

exit 0