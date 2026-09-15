#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SOURCE_DIR}/SOURCE.lock"

TARGET_LIBRARY="/usr/lib64/libfprint-2.so.2.0.0"
BACKUP_LIBRARY="/var/lib/libfprint-crfpmoc/libfprint-2.so.2.0.0.fedora-stock"

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

[[ ${EUID} -eq 0 ]] || fail "Run as root (for example: sudo $0)."
[[ "$(< /sys/class/dmi/id/product_name)" == "${TESTED_DMI_PRODUCT}" ]] || \
	fail "This rollback is restricted to ${TESTED_DMI_PRODUCT}."

if [[ ! -f "${BACKUP_LIBRARY}" ]]; then
	echo "The preserved Fedora library is unavailable. Using DNF reinstall instead."
	dnf reinstall -y libfprint
else
	backup_sha256="$(sha256sum "${BACKUP_LIBRARY}" | cut -d ' ' -f 1)"
	[[ "${backup_sha256}" == "${STOCK_LIBRARY_SHA256}" ]] || \
		fail "The preserved backup checksum is unexpected; use 'dnf reinstall libfprint'."
	cp --archive "${BACKUP_LIBRARY}" "${TARGET_LIBRARY}.fedora-new"
	restorecon "${TARGET_LIBRARY}.fedora-new"
	mv -f "${TARGET_LIBRARY}.fedora-new" "${TARGET_LIBRARY}"
	restorecon "${TARGET_LIBRARY}"
	ldconfig
fi

systemctl try-restart fprintd.service

if semodule -l | grep -Fxq fprintd_cros_fp; then
	semodule -r fprintd_cros_fp
	restorecon -Fv /dev/cros_fp || true
	systemctl try-restart fprintd.service
fi

sha256sum "${TARGET_LIBRARY}"
rpm -V libfprint
echo "Fedora's stock libfprint library has been restored."
