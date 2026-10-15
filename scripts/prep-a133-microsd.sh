#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  I_UNDERSTAND_DEVICE_WILL_BE_ERASED=1 prep-a133-microsd.sh \
    --device /dev/sdX \
    --uboot /path/to/u-boot-sunxi-with-spl.bin \
    --rootfs-tar /path/to/debian-bookworm-arm64-rootfs.tar

Creates a simple clean boot MicroSD layout for the Joyhong T-2 / A133 frame:
  - MBR partition table at sector 0
  - U-Boot SPL+U-Boot image written at sector 16, the normal sunxi offset
  - Partition 1 starts at sector 2048 and is formatted ext4 as "rootfs"

The script refuses to run unless the confirmation environment variable is set.
It also refuses mounted targets and internal nvme/mmcblk0-style disks unless
--force is supplied.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

device=
uboot=
rootfs_tar=
force=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      device=${2:-}
      shift 2
      ;;
    --uboot)
      uboot=${2:-}
      shift 2
      ;;
    --rootfs-tar)
      rootfs_tar=${2:-}
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ "${I_UNDERSTAND_DEVICE_WILL_BE_ERASED:-}" = "1" ] || die "set I_UNDERSTAND_DEVICE_WILL_BE_ERASED=1"
[ -n "$device" ] || die "--device is required"
[ -n "$uboot" ] || die "--uboot is required"
[ -n "$rootfs_tar" ] || die "--rootfs-tar is required"
[ -b "$device" ] || die "$device is not a block device"
[ -f "$uboot" ] || die "$uboot does not exist"
[ -f "$rootfs_tar" ] || die "$rootfs_tar does not exist"

base=$(basename "$device")
case "$base" in
  nvme*|mmcblk0)
    [ "$force" -eq 1 ] || die "refusing likely internal disk $device; pass --force only if this is really the MicroSD"
    ;;
esac

if lsblk -nr -o MOUNTPOINTS "$device" | rg -q '\S'; then
  die "$device or one of its partitions is mounted"
fi

rm_flag=$(lsblk -dn -o RM "$device" | tr -d ' ')
if [ "$rm_flag" != "1" ] && [ "$force" -ne 1 ]; then
  die "$device is not marked removable; pass --force only after verifying it is the MicroSD"
fi

command -v sfdisk >/dev/null || die "sfdisk is required"
command -v mkfs.ext4 >/dev/null || die "mkfs.ext4 is required"
command -v partprobe >/dev/null || die "partprobe is required"
command -v tar >/dev/null || die "tar is required"

printf 'Target: %s\n' "$device"
printf 'U-Boot: %s\n' "$uboot"
printf 'Rootfs: %s\n' "$rootfs_tar"

sudo wipefs -a "$device"
sudo sfdisk "$device" <<'EOF'
label: dos
unit: sectors

start=2048, type=83, bootable
EOF

sudo partprobe "$device"
sleep 2

part="${device}1"
case "$device" in
  *mmcblk*|*nvme*) part="${device}p1" ;;
esac

[ -b "$part" ] || die "partition did not appear: $part"

# sunxi SPL offset: sector 16 == 8 KiB. This preserves the MBR in sector 0 and
# keeps partition 1 starting at sector 2048.
sudo dd if="$uboot" of="$device" bs=1024 seek=8 conv=fsync,notrunc status=progress

sudo mkfs.ext4 -F -L rootfs "$part"

mnt=$(mktemp -d)
cleanup() {
  if mountpoint -q "$mnt"; then
    sudo umount "$mnt"
  fi
  rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount "$part" "$mnt"
sudo tar --numeric-owner -xpf "$rootfs_tar" -C "$mnt"
sync

printf 'MicroSD prepared: %s\n' "$device"
printf 'Rootfs partition: %s\n' "$part"
