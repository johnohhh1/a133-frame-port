#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED=1 install-a133-kernel-to-microsd.sh \
    --device /dev/sdX \
    --stage ./staging/linux-<kernelrelease>

Installs a staged Joyhong T-2 / A133 kernel onto partition 1 of an already
prepared MicroSD card. It copies:
  - boot/vmlinuz-<kernelrelease>
  - boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb
  - lib/modules/<kernelrelease>

It also writes /boot/extlinux/extlinux.conf for serial + panel console boot.
EOF
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

device=
stage=
force=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --device)
      device=${2:-}
      shift 2
      ;;
    --stage)
      stage=${2:-}
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

[ "${I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED:-}" = "1" ] || die "set I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED=1"
[ -n "$device" ] || die "--device is required"
[ -n "$stage" ] || die "--stage is required"
[ -b "$device" ] || die "$device is not a block device"
[ -d "$stage" ] || die "$stage does not exist"

base=$(basename "$device")
case "$base" in
  nvme*|mmcblk0)
    [ "$force" -eq 1 ] || die "refusing likely internal disk $device; pass --force only if this is really the MicroSD"
    ;;
esac

rm_flag=$(lsblk -dn -o RM "$device" | tr -d ' ')
if [ "$rm_flag" != "1" ] && [ "$force" -ne 1 ]; then
  die "$device is not marked removable; pass --force only after verifying it is the MicroSD"
fi

part="${device}1"
case "$device" in
  *mmcblk*|*nvme*) part="${device}p1" ;;
esac

[ -b "$part" ] || die "partition did not appear: $part"

release=$(basename "$stage")
release=${release#linux-}

[ -f "$stage/boot/vmlinuz-$release" ] || die "missing staged kernel: boot/vmlinuz-$release"
[ -f "$stage/boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb" ] || die "missing staged Joyhong DTB"
[ -d "$stage/lib/modules/$release" ] || die "missing staged modules for $release"

root_uuid=$(blkid -s UUID -o value "$part")
[ -n "$root_uuid" ] || die "could not read filesystem UUID from $part"

mnt=$(mktemp -d)
cleanup() {
  if mountpoint -q "$mnt"; then
    sync
    sudo umount "$mnt"
  fi
  rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount "$part" "$mnt"

sudo install -d "$mnt/boot/dtb/allwinner" "$mnt/boot/extlinux" "$mnt/lib/modules"
sudo cp -f "$stage/boot/vmlinuz-$release" "$mnt/boot/vmlinuz-$release"
sudo cp -f "$stage/boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb" \
  "$mnt/boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb"
sudo cp -a "$stage/lib/modules/$release" "$mnt/lib/modules/"

sudo tee "$mnt/boot/extlinux/extlinux.conf" >/dev/null <<EOF
TIMEOUT 30
DEFAULT joyhong-a133-drm
MENU TITLE Joyhong T-2 A133

LABEL joyhong-a133-drm
  MENU LABEL Debian Bookworm A133 DRM/LVDS test
  LINUX /boot/vmlinuz-$release
  FDT /boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb
  APPEND root=UUID=$root_uuid rootwait rw console=tty0 console=ttyS0,115200n8 earlycon=uart8250,mmio32,0x05000000 loglevel=8 ignore_loglevel systemd.show_status=true drm.debug=0x1ff

LABEL debian-packaged-fallback
  MENU LABEL Debian packaged kernel fallback
  LINUX /boot/vmlinuz-6.12.95+deb12-arm64
  INITRD /boot/initrd.img-6.12.95+deb12-arm64
  FDT /boot/dtb/allwinner/sun50i-a100-allwinner-perf1.dtb
  APPEND root=UUID=$root_uuid rootwait rw console=tty0 console=ttyS0,115200n8 earlycon=uart8250,mmio32,0x05000000 loglevel=8 systemd.show_status=true
EOF

if [ -f "$stage/SHA256SUMS" ]; then
  sudo cp -f "$stage/SHA256SUMS" "$mnt/boot/SHA256SUMS.$release"
fi

sync

printf 'Installed kernel release: %s\n' "$release"
printf 'Target rootfs: %s UUID=%s\n' "$part" "$root_uuid"
