# Redrix fingerprint support for Fedora

This repository installs the experimental `crfpmoc` libfprint driver for the
fingerprint reader in the HP Elite Dragonfly Chromebook (`Google Redrix`).

Validated configuration:

- Google Redrix rev3
- Fedora Linux 44 KDE Plasma Desktop Edition
- Linux `7.2.5-200.fc44.x86_64`
- MrChromebox firmware `2606.1`
- Fedora `libfprint-1.94.100-1.fc44.x86_64`
- `acd407/libfprint` commit `4df05918f4670f5eed684c1771d2183f2e2df279`
- Local FP_INFO v2/v3 negotiation patch for the 2026 Bloonchipper firmware

The complete investigation, evidence, implementation decisions, and original
installation record are in [`RECORD.md`](RECORD.md).

## Why this is needed

Redrix does not expose its fingerprint sensor as a normal USB device. An FPC1025
sensor is connected to a dedicated STM32F412 fingerprint MCU running Google
`bloonchipper` firmware. Linux exposes that MCU as `/dev/cros_fp`.

Fedora's kernel supports the MCU transport, but Fedora's stock libfprint does not
yet contain the experimental ChromeOS FPMCU driver. As a result, stock fprintd
starts normally but finds no fingerprint device.

## Install

Review the scripts, then run:

```bash
cd FP-redrix
sudo ./install.sh
```

The installer:

1. Refuses to run on anything other than Redrix rev3 and Fedora 44.
2. Requires the exact Fedora libfprint build validated here.
3. Installs Fedora's official libfprint build dependencies.
4. Clones and verifies the pinned upstream commit.
5. Verifies and applies the repository's pinned FP_INFO compatibility patch.
6. Builds libfprint with all normal drivers plus `crfpmoc`.
7. Runs the complete test suite.
8. Preserves the original Fedora library under `/var/lib/libfprint-crfpmoc`.
9. Installs a narrow SELinux policy and dedicated label for `/dev/cros_fp`.
10. Atomically installs the replacement library and restarts fprintd.

No firmware is flashed, no fingerprint is enrolled, and PAM files are not
modified by the installer.

The SELinux policy allows only `fprintd_t` to open, inspect, read, write, and
issue ioctls to the dedicated `cros_fp_device_t` character device. It does not
grant fprintd access to every character device carrying the generic `device_t`
label.

## Verify

```bash
./verify.sh
```

Expected output includes:

```text
found 1 devices
ChromeOS Fingerprint Match-on-Chip
Device claim and MCU initialization: passed
```

## Enroll

Use KDE System Settings:

```text
System Settings -> Users -> Configure Fingerprint Authentication
```

Or use the command line:

```bash
fprintd-enroll
```

Enrollment stores biometric templates. It is deliberately not part of the
installation script.

## Roll back

```bash
sudo ./uninstall.sh
```

The uninstaller restores the preserved Fedora library and restarts fprintd. If
the backup is unavailable, use:

```bash
sudo dnf reinstall libfprint
```

Build dependencies are not automatically removed because DNF may consider them
useful to other development work.

## Fedora updates

The replacement library remains owned by Fedora's `libfprint` RPM and therefore
appears as a modified package file. A future update or reinstall of libfprint can
replace the custom driver. Run `./verify.sh` after libfprint updates. Re-run the
installer only after confirming that the pinned branch is still appropriate for
the new Fedora version.

## Diagnostics

Create a shareable, text-only diagnostic report with:

```bash
./collect-diagnostics.sh
```

The collector does not read or export enrolled fingerprint templates.

For a root-only, read-only check of the firmware's advertised FP_INFO command
versions, run `./probe-protocol.sh`. The validated firmware reports mask `0x0c`
(versions 2 and 3).

## Security status

This uses an experimental, unmerged libfprint branch. Its device emulation test
and the complete libfprint test suite passed on the validated machine, and the
real reader was detected successfully. It has not received the same downstream
review or lifecycle guarantees as Fedora's signed package. The pinned commit
explicitly uses fixed encryption keys; its security consequences have not been
independently audited. Read [`SECURITY.md`](SECURITY.md) before relying on it.

## Repository licensing

The original scripts and documentation in this repository are MIT-licensed.
The compatibility patch modifies libfprint code and follows libfprint's
LGPL-2.1-or-later terms; the upstream source is fetched rather than vendored.
