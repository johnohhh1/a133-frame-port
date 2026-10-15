# Joyhong T-2 A133 Porting Artifacts

Working target: Joyhong `T-2` / Android `ceres-aw` digital frame.

Source dump: `(private factory dump, not included)`

Upstream references used locally:
- U-Boot master from `https://source.denx.de/u-boot/u-boot.git`
- Trusted Firmware-A master from `https://github.com/TrustedFirmware-A/trusted-firmware-a.git`
- Linux mainline DTS reference `sun50i-a133-liontron-h-a133l.dts`
- Linux mainline bindings `panel-lvds.yaml`, `lvds-data-mapping.yaml`, and `pwm-backlight.yaml`
- A100/A133 display pipeline patch series: `https://patchew.org/linux/20241227-a133-display-support-v1-0-13b52f71fb14%40linumiz.com/`
- Sipeed LonganPi 3H SDK: `https://github.com/sipeed/LonganPi-3H-SDK`

## Files

- `patches/u-boot/0001-configs-add-joyhong-t2-a133-defconfig.patch`
  - Adds `configs/joyhong-t2-a133_defconfig`.
  - Adds a minimal U-Boot DT at `dts/upstream/src/arm64/allwinner/sun50i-a133-joyhong-t2.dts`.
  - Pins U-Boot/Linux boot console to UART0 / `ttyS0` at `115200`.
  - Builds a serial-first `u-boot-sunxi-with-spl.bin` for external MicroSD boot testing.

- `linux/sun50i-a133-joyhong-t2.dts`
  - Clean mainline-style DTS draft based on `sun50i-a100.dtsi`, matching the public Liontron A133 reference.
  - Contains the reconstructed `panel-lvds` node using the factory panel timing.
  - Preserves the AXP803, eMMC, SD, SDIO Wi-Fi, USB, UART0, and regulator shape.

- `scripts/prep-a133-microsd.sh`
  - Creates a clean MicroSD layout for external boot testing.
  - Does not touch the factory eMMC.
  - Requires explicit destructive confirmation before it will run.

- `scripts/install-a133-kernel-to-microsd.sh`
  - Installs a staged custom kernel, DTB, modules, and `extlinux.conf` onto an already prepared MicroSD rootfs.
  - Refuses to run unless `I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED=1` is set.

## U-Boot Build

Build dependencies installed locally for this step:

- `bison`
- `flex`
- `libfl2`
- `libfl-dev`
- `swig`

APT result: `0 upgraded, 5 newly installed`.

Build commands used:

```bash
cd ./trusted-firmware-a
make -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu- PLAT=sun50i_a133 DEBUG=0 bl31

cd ./u-boot-mainline
make CROSS_COMPILE=aarch64-linux-gnu- joyhong-t2-a133_defconfig
BL31=./trusted-firmware-a/build/sun50i_a133/release/bl31.bin \
  SCP=/dev/null \
  make -j"$(nproc)" CROSS_COMPILE=aarch64-linux-gnu-
```

Build outputs:

- `u-boot-mainline/u-boot-sunxi-with-spl.bin`
  - SHA256: `d3d31c0d4b31df613dfeecdc805a70ae876f9d524416ea3dd5d8f3b1f142b9a9`
- `trusted-firmware-a/build/sun50i_a133/release/bl31.bin`
  - SHA256: `a67571a4419e0d791256d3a208f326ef6b3d3aa8b2cbaf6efaf26080d9f8bd9d`

## Extracted Panel Timing

Factory fields from `live-fdt.dts`:

- `lcd_x = 1920`
- `lcd_y = 1080`
- `lcd_width = 260`
- `lcd_height = 478`
- `lcd_dclk_freq = 135 MHz`
- `lcd_hbp = 140`
- `lcd_ht = 2108`
- `lcd_hspw = 48`
- `lcd_vbp = 41`
- `lcd_vt = 1132`
- `lcd_vspw = 10`
- `lcd_lvds_if = 1`
- `lcd_lvds_colordepth = 0`
- `lcd_lvds_mode = 0`

Derived values:

- `lcd_hfp = 2108 - 1920 - 140 - 48 = 0`
- `lcd_vfp = 1132 - 1080 - 41 - 10 = 1`

Allwinner BSP meaning:

- `lcd_lvds_if = 1` means dual-link LVDS.
- `lcd_lvds_colordepth = 0` means 8-bit / 24 bpp.
- `lcd_lvds_mode = 0` means NS/VESA-style mapping, so the draft uses `data-mapping = "vesa-24"`.

## MicroSD Prep

Example only. Replace the device path and rootfs tar path:

```bash
I_UNDERSTAND_DEVICE_WILL_BE_ERASED=1 \
  ./scripts/prep-a133-microsd.sh \
  --device /dev/sdX \
  --uboot /path/to/u-boot-sunxi-with-spl.bin \
  --rootfs-tar /path/to/debian-bookworm-arm64-rootfs.tar
```

Layout:

- MBR at sector 0.
- U-Boot SPL+U-Boot at sector 16: `dd bs=1024 seek=8`.
- Partition 1 starts at sector 2048 and is formatted ext4 as `rootfs`.

## MicroSD Written 2026-08-10

Detected MicroSD target:

- Reader: `14cd:1212 Super Top microSD card reader (SY-T18)`
- Block device: `/dev/sdb`
- Size: `14.56 GiB` / `30,535,680` sectors

Written layout:

- DOS/MBR disklabel, PTUUID `32674923`
- Raw U-Boot image written at sector 16 / 8 KiB:
  - Source: `u-boot-mainline/u-boot-sunxi-with-spl.bin`
  - SHA256: `d3d31c0d4b31df613dfeecdc805a70ae876f9d524416ea3dd5d8f3b1f142b9a9`
  - Verification: byte-for-byte compare from `/dev/sdb` at `bs=1024 skip=8` passed
  - Header at sector 16 contains `eGON.BT0`
- Partition 1:
  - Device: `/dev/sdb1`
  - Start sector: `2048`
  - End sector: `30535679`
  - Type: Linux / `0x83`
  - Filesystem: ext4
  - Label: `rootfs`
  - UUID: `bd4dc355-9bb7-491c-946c-f7d0f1869ba4`

Debian Bookworm ARM64 userspace has now been installed directly onto `/dev/sdb1`.

Rootfs contents:

- Debian suite: `bookworm`
- Architecture: `arm64`
- Hostname: `a133-frame`
- Kernel: Debian bookworm-backports `linux-image-6.12.95+deb12-arm64`
- Initramfs: `/boot/initrd.img-6.12.95+deb12-arm64`
  - Verified to contain `sunxi-mmc`, `ext4`, `jbd2`, and `mbcache`
- Boot menu: `/boot/extlinux/extlinux.conf`
  - Primary entry uses `sun50i-a133-joyhong-t2.dtb`, copied from the verified U-Boot build DTB
  - Fallback entry uses Debian's packaged `sun50i-a100-allwinner-perf1.dtb`
- Console: `tty0` and `ttyS0,115200n8`
- Early console: `uart8250,mmio32,0x05000000`
- Serial getty: `serial-getty@ttyS0.service` enabled
- Temporary first-boot users:
  - `root` (default password, change on first boot)
  - one regular user (default password, change on first boot)
- SSH server installed and enabled, though first boot is expected to be serial-only until networking is proven.

Target packages added include `systemd-sysv`, `openssh-server`, `sudo`, `ifupdown`, `isc-dhcp-client`, `initramfs-tools`, `linux-image-arm64`, and `zstd`.

Display/simplefb attempt:

- Android runtime bootargs expose `disp_reserve=8294400,0xbbf4c080`.
- `8294400` is exactly `1920 * 1080 * 4`.
- Android `fb0` reports:
  - mode `1920x1080`
  - `bits_per_pixel = 32`
  - `stride = 7680`
  - `virtual_size = 1920,2160`
- Android display state reports live LCD output at `1920x1080`, backlight `255`, about `57 fps`.
- The Joyhong DTB now includes:
  - `/chosen/framebuffer@bbf4c080`
  - `compatible = "simple-framebuffer"`
  - `reg = <0x0 0xbbf4c080 0x0 0x7e9000>`
  - `width = <1920>`
  - `height = <1080>`
  - `stride = <7680>`
  - `format = "x8r8g8b8"`
  - matching reserved-memory carveout with `no-map`
- Debian kernel config confirms:
  - `CONFIG_FB_SIMPLE=y`
  - `CONFIG_FRAMEBUFFER_CONSOLE=y`
  - `CONFIG_DRM_FBDEV_EMULATION=y`

Updated artifacts written to the card:

- Raw U-Boot rewritten at sector 16 and byte-verified.
- Updated DTB: `/boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb`
  - SHA256: `5ffd90f98da2a3b6fd07c0e99606b35677fd589d766a4e75f928810fecb9a1fe`
- Updated U-Boot image:
  - SHA256: `2b07fb513b0dd82524e78a755018ed7973c8247add22c28362998a5864364bb3`
- Updated extlinux config:
  - SHA256: `7d71a9e7cf86fc6c64f519abceb357573af552db8db8f7802c3663b335583075`

## A133 DRM/LVDS Kernel Build 2026-08-10

Sipeed's LonganPi 3H SDK does not initialize display in U-Boot; its U-Boot patch leaves `CONFIG_VIDEO` disabled. Its display work is in the Linux kernel display pipeline. Based on that, the current next test is a custom Linux kernel with A100/A133 display patches and a Joyhong panel graph, not another simple framebuffer-only U-Boot attempt.

Kernel source:

- `./linux-a133`
- Base tag: Linux `v6.13-rc5`
- Applied public A100/A133 display series patches 1-17 from Patchew/lore.
- Applied public A100 syscon/SRAM dependency series.
- Added local Joyhong T-2 DTS and A100/A133 display nodes for DE2, mixer0, TCON-top, TCON LCD, PWM0, and LVDS panel output.
- Added a local `sun50i_a100_lcd_quirks` TCON match so the patched driver can bind `allwinner,sun50i-a100-tcon-lcd`.

Built kernel release:

- `6.13.0-rc5-00019-g37a5998346c6-dirty`

Staged install payload:

- `./staging/linux-6.13.0-rc5-00019-g37a5998346c6-dirty`
- Size: about `328M`
- Module count: `1302` `.ko` files

Staged artifacts:

- `boot/vmlinuz-6.13.0-rc5-00019-g37a5998346c6-dirty`
  - SHA256: `967a553560b6ec04067272d567de6ad5bb54b6c0414dfac5f2f4edd6dd1c61f2`
- `boot/dtb/allwinner/sun50i-a133-joyhong-t2.dtb`
  - SHA256: `c1a6a27c86215e8fdb513a28e46898d54269f65be27b08a0d6933f3cf59fd3ab`
- `lib/modules/6.13.0-rc5-00019-g37a5998346c6-dirty`

Built-in boot/display config:

- `CONFIG_MMC_SUNXI=y`
- `CONFIG_EXT4_FS=y`
- `CONFIG_DRM_SUN4I=y`
- `CONFIG_DRM_SUN8I_MIXER=y`
- `CONFIG_DRM_SUN8I_TCON_TOP=y`
- `CONFIG_DRM_PANEL_LVDS=y`
- `CONFIG_BACKLIGHT_PWM=y`
- `CONFIG_PWM_SUN4I=y`
- `CONFIG_PHY_SUN6I_MIPI_DPHY=y`
- `CONFIG_FB_SIMPLE=y`
- `CONFIG_FRAMEBUFFER_CONSOLE=y`

Install when the MicroSD reader is reinserted:

```bash
I_UNDERSTAND_DEVICE_WILL_BE_MODIFIED=1 \
  ./scripts/install-a133-kernel-to-microsd.sh \
  --device /dev/sdX \
  --stage ./staging/linux-6.13.0-rc5-00019-g37a5998346c6-dirty
```

Replace `/dev/sdX` with the removable MicroSD block device after checking `lsblk`.

## Important Caveats

This is a first-pass external-boot port, not an eMMC flash plan.

Stock U-Boot currently drops `CONFIG_VIDEO_SUNXI` for `MACH_SUN50I_A133` because that path depends on neither `MACH_SUN50I` nor `SUN50I_GEN_H6`. The verified U-Boot artifact is therefore serial-first, not display-initializing.

The simplefb node can show a framebuffer console only if firmware or a warm-boot path leaves the display engine, TCON, LVDS link, panel power, and backlight already initialized. It does not program those blocks by itself.

The DTS panel data is reconstructed, but current mainline `sun50i-a100.dtsi` does not expose the complete A133 display engine/TCON/LVDS/PWM graph. A true cold-boot display path likely requires the A100/A133 display patch series or equivalent downstream display-controller work.

The U-Boot DRAM settings currently inherit the public Liontron H-A133L values. If SPL fails before serial console, port the factory DRAM parameters from the captured Android DT/U-Boot environment before continuing.
