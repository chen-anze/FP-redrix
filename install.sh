#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SOURCE_DIR}/SOURCE.lock"

TARGET_LIBRARY="/usr/lib64/libfprint-2.so.2.0.0"
BACKUP_DIRECTORY="/var/lib/libfprint-crfpmoc"
BACKUP_LIBRARY="${BACKUP_DIRECTORY}/libfprint-2.so.2.0.0.fedora-stock"
BUILD_ROOT=""

cleanup() {
	if [[ -n "${BUILD_ROOT}" && "${BUILD_ROOT}" == /var/tmp/libfprint-crfpmoc.* ]]; then
		rm -rf -- "${BUILD_ROOT}"
	fi
}
trap cleanup EXIT

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

[[ ${EUID} -eq 0 ]] || fail "Run as root (for example: sudo $0)."
[[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] || \
	fail "Invoke this script with sudo from the desktop user; third-party source will not be built as root."
[[ -r /sys/class/dmi/id/product_name ]] || fail "DMI product information is unavailable."
[[ "$(< /sys/class/dmi/id/product_name)" == "${TESTED_DMI_PRODUCT}" ]] || \
	fail "This installer is restricted to ${TESTED_DMI_PRODUCT}."
[[ "$(< /sys/class/dmi/id/product_version)" == "${TESTED_DMI_VERSION}" ]] || \
	fail "This installer is restricted to ${TESTED_DMI_PRODUCT} ${TESTED_DMI_VERSION}."

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID}" == "${TESTED_OS_ID}" && "${VERSION_ID}" == "${TESTED_OS_VERSION}" ]] || \
	fail "This revision is validated only on Fedora ${TESTED_OS_VERSION}."

installed_nevra="$(rpm -q --qf '%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}' libfprint)"
installed_nevra="${installed_nevra/-0:/-}"
[[ "${installed_nevra}" == "${TESTED_LIBFPRINT_NEVRA}" ]] || \
	fail "Expected ${TESTED_LIBFPRINT_NEVRA}; found ${installed_nevra}."

[[ -c /dev/cros_fp ]] || fail "/dev/cros_fp is absent; the kernel has not exposed the FPMCU."
grep -Fq 'DeviceAllow=/dev/cros_fp rw' /usr/lib/systemd/system/fprintd.service || \
	fail "Fedora's fprintd service does not allow access to /dev/cros_fp."

if [[ ! -e "${BACKUP_LIBRARY}" ]]; then
	current_sha256="$(sha256sum "${TARGET_LIBRARY}" | cut -d ' ' -f 1)"
	[[ "${current_sha256}" == "${STOCK_LIBRARY_SHA256}" ]] || \
		fail "The Fedora library differs from the tested stock build; refusing to create an unsafe backup."
fi

dnf builddep -y libfprint
dnf install -y checkpolicy policycoreutils

BUILD_ROOT="$(mktemp -d /var/tmp/libfprint-crfpmoc.XXXXXX)"
builder_group="$(id -gn "${SUDO_USER}")"
chown "${SUDO_USER}:${builder_group}" "${BUILD_ROOT}"

runuser -u "${SUDO_USER}" -- git clone \
	--branch "${SOURCE_BRANCH}" --single-branch --no-checkout \
	"${SOURCE_REPOSITORY}" "${BUILD_ROOT}/source"
runuser -u "${SUDO_USER}" -- git -C "${BUILD_ROOT}/source" \
	checkout --detach "${SOURCE_COMMIT}"

actual_commit="$(git -C "${BUILD_ROOT}/source" rev-parse HEAD)"
[[ "${actual_commit}" == "${SOURCE_COMMIT}" ]] || \
	fail "Source branch moved to ${actual_commit}; expected pinned commit ${SOURCE_COMMIT}."

actual_patch_sha256="$(sha256sum "${SOURCE_DIR}/${PATCH_FILE}" | cut -d ' ' -f 1)"
[[ "${actual_patch_sha256}" == "${PATCH_SHA256}" ]] || \
	fail "Compatibility patch checksum does not match SOURCE.lock."
runuser -u "${SUDO_USER}" -- git -C "${BUILD_ROOT}/source" apply --check \
	"${SOURCE_DIR}/${PATCH_FILE}"
runuser -u "${SUDO_USER}" -- git -C "${BUILD_ROOT}/source" apply \
	"${SOURCE_DIR}/${PATCH_FILE}"

runuser -u "${SUDO_USER}" -- meson setup \
	"${BUILD_ROOT}/source/build" "${BUILD_ROOT}/source" \
	--prefix=/usr \
	--libdir=lib64 \
	-Dbuildtype=release \
	-Ddoc=false \
	-Dgtk-examples=false \
	-Dinstalled-tests=false
runuser -u "${SUDO_USER}" -- meson compile -C "${BUILD_ROOT}/source/build"
runuser -u "${SUDO_USER}" -- meson test -C "${BUILD_ROOT}/source/build" \
	--print-errorlogs

custom_library="${BUILD_ROOT}/source/build/libfprint/libfprint-2.so.2.0.0"
[[ -f "${custom_library}" ]] || fail "The expected shared library was not built."

readelf -d "${custom_library}" | grep -Fq 'Library soname: [libfprint-2.so.2]' || \
	fail "The custom library SONAME does not match Fedora's ABI."

nm -D --defined-only "${TARGET_LIBRARY}" | awk '{print $2, $3}' | sort \
	> "${BUILD_ROOT}/stock.symbols"
nm -D --defined-only "${custom_library}" | awk '{print $2, $3}' | sort \
	> "${BUILD_ROOT}/custom.symbols"
if [[ -s "${BUILD_ROOT}/stock.symbols" ]] && \
	[[ -n "$(comm -23 "${BUILD_ROOT}/stock.symbols" "${BUILD_ROOT}/custom.symbols")" ]]; then
	fail "The custom library is missing public symbols exported by Fedora's library."
fi

install -d -m 0700 -o root -g root "${BACKUP_DIRECTORY}"
if [[ ! -e "${BACKUP_LIBRARY}" ]]; then
	cp --archive "${TARGET_LIBRARY}" "${BACKUP_LIBRARY}"
fi
install -m 0600 -o root -g root "${SOURCE_DIR}/SOURCE.lock" \
	"${BACKUP_DIRECTORY}/SOURCE.lock"

install -m 0755 -o root -g root "${custom_library}" "${TARGET_LIBRARY}.crfpmoc-new"
restorecon "${TARGET_LIBRARY}.crfpmoc-new"
mv -f "${TARGET_LIBRARY}.crfpmoc-new" "${TARGET_LIBRARY}"
restorecon "${TARGET_LIBRARY}"
ldconfig
"${SOURCE_DIR}/install-selinux-policy.sh"
systemctl try-restart fprintd.service

installed_sha256="$(sha256sum "${TARGET_LIBRARY}" | cut -d ' ' -f 1)"
if [[ "${installed_sha256}" != "${CUSTOM_LIBRARY_SHA256}" ]]; then
	echo "NOTE: build checksum differs from the original validated build because the toolchain or build metadata changed."
	echo "Original: ${CUSTOM_LIBRARY_SHA256}"
	echo "Current:  ${installed_sha256}"
fi

account="${SUDO_USER:-root}"
fprintd-list "${account}"
echo "crfpmoc installed. Run ${SOURCE_DIR}/verify.sh as the desktop user."
