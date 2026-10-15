# a133-frame-port

Work-in-progress port of mainline **U-Boot + Linux + Debian** to the **Joyhong T-2** digital photo frame (Allwinner **A133**, Android board name `ceres-aw`, 1920×1080 dual-link LVDS panel). It boots from an external MicroSD card and leaves the factory eMMC alone.

Status: the U-Boot serial console and Debian userspace boot from MicroSD. A custom 6.13 kernel with the A100/A133 display series and a Joyhong panel graph is built and waiting to be tested. Cold-boot display init isn't working yet. See [docs/LAB_NOTES.md](docs/LAB_NOTES.md) for the full log, checksums and caveats.

If you have one of these frames, or any A133/A100 board with an LVDS panel, help is very welcome.

## What's here

| Path | Contents |
|---|---|
| `patches/u-boot/` | Adds a `joyhong-t2-a133_defconfig` and a minimal board DTS to U-Boot (UART0 console at 115200) |
| `patches/linux-a133-local/` | Local kernel changes: A100/A133 display nodes (DE2, mixer, TCON-top, TCON-LCD, PWM, LVDS), a TCON quirk for `sun50i-a100-tcon-lcd`, and the Joyhong T-2 DTS |
| `patches/linux-a133-display/`, `patches/linux-a100-syscon/` | Public upstream patch series this depends on (Parthiban Nallathambi's A100/A133 display series and the A100 syscon series), saved from lore/patchew |
| `linux/sun50i-a133-joyhong-t2.dts` | Mainline-style board DTS with the panel timing reconstructed from the factory device tree |
| `upstream-linux/`, `upstream-bindings/` | Reference DTS/DTSI and DT bindings copied from mainline Linux |
| `scripts/prep-a133-microsd.sh` | Partitions a MicroSD card, writes U-Boot at 8 KiB and unpacks a rootfs tarball (**erases the card**) |
| `scripts/install-a133-kernel-to-microsd.sh` | Installs a staged kernel, DTB, modules and `extlinux.conf` onto a prepared card |

## Build

You need an `aarch64-linux-gnu-` cross toolchain, plus `bison flex swig libfl-dev` for U-Boot.

```bash
# 1. Trusted Firmware-A (BL31)
git clone https://github.com/TrustedFirmware-A/trusted-firmware-a
make -C trusted-firmware-a CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_a133 DEBUG=0 bl31

# 2. U-Boot with the Joyhong defconfig
git clone https://source.denx.de/u-boot/u-boot.git u-boot-mainline
git -C u-boot-mainline apply ../patches/u-boot/0001-configs-add-joyhong-t2-a133-defconfig.patch
make -C u-boot-mainline CROSS_COMPILE=aarch64-linux-gnu- joyhong-t2-a133_defconfig
BL31=$PWD/trusted-firmware-a/build/sun50i_a133/release/bl31.bin SCP=/dev/null \
  make -C u-boot-mainline -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu-
# -> u-boot-mainline/u-boot-sunxi-with-spl.bin

# 3. Kernel: Linux v6.13-rc5 + the upstream series in patches/ + the local patch
git clone --branch v6.13-rc5 https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git linux-a133
cd linux-a133
git am ../patches/linux-a100-syscon/am-syscon/*.mbx
git am ../patches/linux-a133-display/b4-original/am-original/*.mbx
git apply ../patches/linux-a133-local/0001-joyhong-t2-local-display-nodes.patch
```

## Flash a MicroSD card

Check the device name with `lsblk` first. These scripts are destructive and refuse to run without the confirmation variable.

```bash
I_UNDERSTAND_DEVICE_WILL_BE_ERASED=1 ./scripts/prep-a133-microsd.sh \
  --device /dev/sdX \
  --uboot u-boot-mainline/u-boot-sunxi-with-spl.bin \
  --rootfs-tar debian-bookworm-arm64-rootfs.tar

I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED=1 ./scripts/install-a133-kernel-to-microsd.sh \
  --device /dev/sdX --stage ./staging/linux-<kernelrelease>
```

Connect a 3.3 V serial adapter to UART0 (115200 8N1) to watch the boot.

## Contributing

Issues and pull requests are welcome. The most useful things right now:

- Getting the panel to light up on a cold boot (DE2 → TCON → LVDS → panel/backlight)
- Porting the factory DRAM parameters if SPL fails on your unit
- Testing on other A133 devices

## License

The patches and the DTS are derived from U-Boot and the Linux kernel, so this repository is licensed under **GPL-2.0**; see [LICENSE](LICENSE). Files copied from upstream (`upstream-linux/`, `upstream-bindings/`, the saved patch series) keep their original SPDX license headers and authorship.
