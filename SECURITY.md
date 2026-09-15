# Security notes

## Support status

This repository installs an experimental libfprint driver from an unmerged
upstream merge request. It is not an official Fedora, Google, HP, FPC, or
libfprint release.

The pinned commit is titled `crfpmoc: Use fixed encryption keys and pass the user
id on GET_RESULT`. The cryptographic consequences of that fixed-key design have
not been independently audited here. Functional enrollment and matching do not
prove that template confidentiality, isolation, replay resistance, or key
management are equivalent to the supported ChromeOS `biod` implementation.

Keep password authentication enabled. Do not use this experimental fingerprint
path as the only protection for high-value or regulated data.

## Supply-chain controls

The installer:

- fetches only the repository and branch recorded in `SOURCE.lock`;
- checks out and verifies the full pinned commit hash;
- checksum-verifies and applies the included FP_INFO compatibility patch;
- builds and tests third-party source as the invoking desktop user, not root;
- compares the resulting public symbols and SONAME with Fedora's library;
- preserves a checksum-verified Fedora library for rollback;
- installs only the runtime shared library;
- labels only `/dev/cros_fp` with a dedicated SELinux device type and grants
  access only to the confined `fprintd_t` domain;
- does not install the abandoned AUR package;
- does not flash FPMCU firmware or read fingerprint images.

The repository is still fetched over the network at installation time. Review
the pinned source and this repository's scripts before running them.

## Biometric data

Installation and verification do not enroll fingers. `collect-diagnostics.sh`
does not read or export templates or fingerprint images. Enrollment through KDE
or `fprintd-enroll` creates biometric records managed by fprintd/libfprint.

To delete the current user's enrolled records deliberately, use:

```bash
fprintd-delete "$USER"
```

## Reporting a vulnerability

Do not include fingerprint templates, fingerprint images, passwords, private
keys, or an unredacted home directory in a public report. Include the commit,
Fedora package versions, kernel version, DMI product, and sanitized output from
`collect-diagnostics.sh`.
