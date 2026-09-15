# Redrix fingerprint driver record

Dates: 2026-09-14 through 2026-09-15  
Machine: Google Redrix rev3 / HP Elite Dragonfly Chromebook  
Operating system: Fedora Linux 44 KDE Plasma Desktop Edition  
Running kernel: `7.2.5-200.fc44.x86_64`  
System firmware: `MrChromebox-2606.1` (2026-07-14)

## Objective

Determine why the integrated fingerprint reader was unavailable under Fedora,
identify the hardware and software boundary, install the appropriate driver,
and leave a reproducible and reversible record.

## Hardware investigation

DMI identified the system as:

```text
sys_vendor: Google
product_name: Redrix
product_version: rev3
board_vendor: Google
board_name: Redrix
board_version: rev3
```

The reader did not appear in PCI enumeration or as a conventional fingerprint
USB device. Kernel and sysfs inspection instead found the ChromeOS fingerprint
MCU on the Intel SPI controller:

```text
ACPI: \\_SB_.PCI0.SPI1.CRFP.PR01: New power resource
cros-ec-spi spi-PRP0001:00: Chrome EC device registered
cros-ec-dev cros-ec-dev.2.auto: CrOS Fingerprint MCU detected
```

The transport was bound to `cros-ec-spi`, and the kernel registered the misc
device `cros_fp` as major 10, minor 263. SPI counters showed active traffic and
zero errors during the investigation.

The FPMCU reported:

```text
RO version:    bloonchipper_v2.0.5938-197506c1
RW version:    bloonchipper-v2.0.30778-e07b67c
Firmware copy: RW
Build info:    bloonchipper-v2.0.30778-e07b67c 2026-04-15 20:53:04
Chip vendor:   st
Chip name:     stm32f412cx
Board version: 0
```

Google's FPMCU documentation maps `bloonchipper` to an STM32F412 MCU and an
FPC1025 sensor. The fingerprint sensor is attached to the FPMCU rather than
directly to the application processor.

References:

- [Redrix coreboot device tree](https://chromium.googlesource.com/chromiumos/third_party/coreboot/+/950fc8169b25167d713580db5ab503174067f733/src/mainboard/google/brya/variants/redrix/overridetree.cb)
- [ChromeOS fingerprint firmware documentation](https://chromium.googlesource.com/chromiumos/platform/ec/+/HEAD/docs/fingerprint/fingerprint.md)
- [ChromeOS biometrics daemon](https://chromium.googlesource.com/chromiumos/platform2/+/HEAD/biod/)

## Fedora software investigation

The required Fedora integration packages were already installed:

```text
libfprint-1.94.100-1.fc44.x86_64
fprintd-1.94.5-5.fc44.x86_64
fprintd-pam-1.94.5-5.fc44.x86_64
```

The kernel configuration included the relevant Chrome EC transport and character
device options, including `CONFIG_CROS_EC_SPI`, `CONFIG_CROS_EC_DEV`, and
`CONFIG_CROS_EC_CHARDEV`.

The stock libfprint library contained USB and conventional SPI drivers but no
`crfpmoc`/`cros_fp` backend. Its supported-device list likewise did not list a
ChromeOS FPMCU driver. fprintd started and stopped cleanly after its normal idle
timeout, consistent with having no supported device rather than a daemon crash.

The installed fprintd service was already prepared for this future driver:

```text
DeviceAllow=/dev/cros_fp rw
```

Fedora authselect was also already configured correctly:

```text
Profile ID: local
Enabled features:
- with-silent-lastlog
- with-mdns4
- with-fingerprint
```

Conclusion: the hardware, firmware, kernel transport, fprintd, and PAM plumbing
were present. The missing component was the libfprint `crfpmoc` backend.

## Driver selection

Upstream libfprint merge request
[`!512`](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/512)
implements a ChromeOS EC FPMCU match-on-chip driver. A Redrix-specific report
confirmed that this branch works on the same model.

The source used for this installation was:

```text
Repository: https://github.com/acd407/libfprint.git
Branch:     feature/crfpmoc
Commit:     4df05918f4670f5eed684c1771d2183f2e2df279
Date:       2026-08-15 19:18:12 +0800
Subject:    crfpmoc: Use fixed encryption keys and pass the user id on GET_RESULT
```

The fixed-key design is experimental and has not been independently audited.
Successful authentication testing establishes functionality, not cryptographic
equivalence with ChromeOS's supported `biod` stack. Password authentication must
remain available, and this driver should not be treated as a sole protection for
high-value data.

The abandoned `libfprint-crfpmoc-git` AUR package was explicitly avoided. Its
former maintainer reports that it was later compromised. Source was cloned from
the current maintainer fork and pinned to the exact reviewed/tested commit.

References:

- [Maintainer's crfpmoc fork](https://github.com/acd407/libfprint)
- [Redrix Linux hardware report](https://www.cnblogs.com/acd407/articles/19669407)
- [libfprint supported devices](https://fprint.freedesktop.org/supported-devices.html)

## Build

Fedora's `dnf builddep -y libfprint` installed 91 build packages and dependencies,
using approximately 264 MiB. The material build inputs included Meson 1.11.2,
Ninja 1.13.2, GCC 16.2.1, GLib 2.88.3, libgusb 0.4.9, NSS 3.127.0, pixman
0.46.2, libgudev 238, and systemd 259.8 development files.

Meson configuration:

```text
prefix:          /usr
libdir:          lib64
buildtype:       release
drivers:         default
doc:             false
gtk-examples:    false
installed-tests: false
```

On Linux, the branch's default driver set includes `crfpmoc` and every normal
non-virtual libfprint driver. The resulting library retained the same SONAME,
`libfprint-2.so.2`, and an exported-symbol comparison found no missing or added
public symbols relative to Fedora's library.

The first test run inside a restricted automation sandbox failed 34 emulated
device tests because umockdev could not create its ioctl listener. This was an
environment restriction: all affected tests failed at the same umockdev setup
point before driver assertions ran. Re-running outside that sandbox produced:

```text
Ok:      38
Fail:     0
Skipped:  2
```

The `drivers+custom - libfprint:crfpmoc` test passed.

## Real-hardware validation before installation

The built library and typelib were loaded directly from the build directory for
a non-mutating probe. It enumerated the physical reader successfully:

```text
devices: 1
crfpmoc ChromeOS Fingerprint Match-on-Chip 0
```

At that point `/dev/cros_fp` existed as:

```text
crw------- root:root 10:263 /dev/cros_fp
```

This permission is sufficient because Fedora's fprintd service runs as root and
its systemd sandbox explicitly allows `/dev/cros_fp`.

## Installation performed

The original Fedora runtime library was copied once to the root-only directory:

```text
/var/lib/libfprint-crfpmoc/libfprint-2.so.2.0.0.fedora-stock
```

The custom shared library was installed atomically at:

```text
/usr/lib64/libfprint-2.so.2.0.0
```

SELinux labels were restored, `ldconfig` was run, and fprintd was restarted. No
udev rule replacement was necessary: generated rules were identical to Fedora's
existing `70-libfprint-2.rules`. The public typelib also did not require
replacement because the public API and exported symbols were unchanged.

### SELinux correction

The initial enumeration test succeeded because listing devices does not claim or
open the reader. The first enrollment attempt exposed a second integration gap:

```text
failed to claim device: GDBus.Error:net.reactivated.Fprint.Error.Internal:
Open failed with error: Failed to open udev path /dev/cros_fp
```

The audit log confirmed an enforcing-policy denial:

```text
avc: denied { read write } comm="pool-0" name="cros_fp"
scontext=system_u:system_r:fprintd_t:s0
tcontext=system_u:object_r:device_t:s0 tclass=chr_file permissive=0
```

Unix permissions and systemd device policy were not the cause. fprintd runs as
root, `/dev/cros_fp` was `0600 root:root`, and the service already contained
`DeviceAllow=/dev/cros_fp rw`. The device had the generic SELinux `device_t`
label, for which `fprintd_t` correctly lacks broad access.

The repository therefore defines the dedicated type `cros_fp_device_t`, labels
only the `/dev/cros_fp` character device with it, and permits only `fprintd_t`
the `getattr`, `ioctl`, `open`, `read`, and `write` operations on that type. It
does not use the unsafe `audit2allow` shortcut of granting fprintd access to all
generic `device_t` character devices.

Two policy prototypes were rejected during diagnosis and were not retained.
Using a nonexistent `device_type` attribute failed module resolution; using the
generic `file_type` attribute allowed module installation but `restorecon`
rejected it as invalid for a device node. Fedora's `dev_node()` interface in
`devices.if` establishes that `device_node` is the correct attribute. The final
policy uses that attribute. `selinux-policy-devel`, `policycoreutils-devel`, and
`setools-console` were installed while inspecting and validating the Fedora
policy interfaces; the reusable installer itself only needs `checkpolicy` and
`policycoreutils` for this small standalone module.

After installing that policy, the open reached the MCU but exposed a separate
protocol incompatibility:

```text
Failed to get max templates and templates size: command failed: INVALID_VERSION
```

The branch sent `EC_CMD_FP_INFO` version 1 unconditionally. A read-only ioctl
probe using `EC_CMD_GET_CMD_VERSIONS` version 1 returned mask `0x0000000c`, so
this April 2026 Bloonchipper firmware supports FP_INFO versions 2 and 3—not
version 1. Direct probes confirmed that v2 returns 180 bytes and v3 returns 216
bytes because the response includes multiple capture-format records.

ChromeOS's current EC protocol header defines the rearranged v2/v3 fixed prefix:
sensor metadata followed by template metadata, then a variable-length array of
image-frame parameters. The local patch therefore:

- queries the supported FP_INFO version mask when opening real hardware;
- selects version 3, then 2, then legacy 1 in preference order;
- requests the full maximum response size advertised by the EC protocol;
- parses both the legacy v1 and current v2/v3 template layouts; and
- preserves v1 behavior for the existing upstream ioctl replay test.

The patch is stored as
`patches/0001-crfpmoc-negotiate-fp-info-version.patch`, pinned by SHA-256 in
`SOURCE.lock`, and verified before `install.sh` applies it.

Protocol reference: [current ChromeOS EC command header](https://chromium.googlesource.com/chromiumos/platform/ec/+/refs/heads/main/include/ec_commands.h)

The final patched release build repeated the complete test set outside the
restricted sandbox: 38 passed, zero failed, and two virtual drivers were
skipped. The crfpmoc ioctl replay test passed. Applying the stored patch with
`git apply --check` to a pristine checkout of the pinned commit also passed.

Recorded SHA-256 values:

```text
d71d98e80eacd49b515ef1999016a540b6e39dc5009a6f84b1924e977d472504  Fedora stock library
8bd4ff46a4dfee25be41da723103a4eca1b6a00cccc3eb60f4b807c0a750a014  patched release library
```

RPM verification now intentionally reports the library as modified:

```text
S.5....T.    /usr/lib64/libfprint-2.so.2.0.0
```

## Post-installation result

The system fprintd daemon—not the build-tree example—enumerated the device:

```text
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
User anze has no fingers enrolled for ChromeOS Fingerprint Match-on-Chip.
```

The post-fix non-enrolling D-Bus claim also succeeded:

```text
gdbus ... net.reactivated.Fprint.Device.Claim anze
()
```

This validates the path that originally failed: SELinux access, opening
`/dev/cros_fp`, EC protocol negotiation, FP_INFO parsing, and device
initialization. `fprintd-list anze` subsequently reported one device and no
enrolled fingers. No new SELinux denial accompanied the successful claim.

Status: **driver installed; device enumeration, open, and MCU initialization
validated**.

No fingerprint was enrolled during installation. Enrollment is a separate,
deliberate action because it creates biometric templates.

## Files in this repository

- `README.md`: user-facing installation, verification, enrollment, maintenance,
  and rollback instructions.
- `RECORD.md`: this investigation and implementation record.
- `SOURCE.lock`: pinned driver source identity and tested Fedora baseline.
- `install.sh`: guarded, reproducible source build, test, backup, and install.
- `patches/0001-crfpmoc-negotiate-fp-info-version.patch`: compatibility fix
  for both legacy FP_INFO v1 and current v2/v3 firmware.
- `probe-protocol.sh` and `tools/cros-fp-probe.c`: read-only firmware command
  version probe and its source.
- `install-selinux-policy.sh`: compiles, installs, and applies the narrowly
  scoped SELinux device policy.
- `selinux/fprintd_cros_fp.te`: policy source defining the dedicated type and
  allowed fprintd operations.
- `selinux/fprintd_cros_fp.fc`: persistent file-context mapping for the device.
- `verify.sh`: read-only checks of the hardware, library, service, PAM, and
  fprintd enumeration.
- `uninstall.sh`: restores the preserved Fedora library.
- `collect-diagnostics.sh`: captures a shareable report without biometric data.
- `SECURITY.md`: security boundary, known risks, and reporting guidance.
- `LICENSE`: MIT license for the repository's original scripts and documentation.
- `CHECKSUMS.sha256`: integrity manifest for repository-controlled files.

The external libfprint source is not vendored. It remains under its upstream
LGPL-2.1-or-later and NIST public-domain licensing terms.

## Maintenance and rollback

Fedora still owns `/usr/lib64/libfprint-2.so.2.0.0`. A DNF update or reinstall
can restore the distribution build and remove `crfpmoc` support. `verify.sh`
detects this condition.

Normal rollback:

```bash
sudo ./uninstall.sh
```

Fallback rollback:

```bash
sudo dnf reinstall libfprint
```

The installer and uninstaller do not erase enrolled fingerprints. Use
`fprintd-delete "$USER"` before rollback if the user explicitly wants to remove
their stored fingerprint records.
