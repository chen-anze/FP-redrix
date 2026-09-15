#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POLICY_NAME="fprintd_cros_fp"
POLICY_DIR="${SOURCE_DIR}/selinux"
BUILD_DIR=""

cleanup() {
	if [[ -n "${BUILD_DIR}" && "${BUILD_DIR}" == /tmp/fprintd-cros-fp-policy.* ]]; then
		rm -rf -- "${BUILD_DIR}"
	fi
}
trap cleanup EXIT

fail() {
	echo "ERROR: $*" >&2
	exit 1
}

[[ ${EUID} -eq 0 ]] || fail "Run as root (for example: sudo $0)."
[[ "$(< /sys/class/dmi/id/product_name)" == "Redrix" ]] || \
	fail "This policy is restricted to Redrix."
[[ -c /dev/cros_fp ]] || fail "/dev/cros_fp is absent."

for command in checkmodule semodule_package semodule restorecon; do
	command -v "${command}" >/dev/null || fail "Missing command: ${command}"
done

BUILD_DIR="$(mktemp -d /tmp/fprintd-cros-fp-policy.XXXXXX)"
checkmodule -M -m -o "${BUILD_DIR}/${POLICY_NAME}.mod" \
	"${POLICY_DIR}/${POLICY_NAME}.te"
semodule_package -o "${BUILD_DIR}/${POLICY_NAME}.pp" \
	-m "${BUILD_DIR}/${POLICY_NAME}.mod" \
	-f "${POLICY_DIR}/${POLICY_NAME}.fc"

semodule -i "${BUILD_DIR}/${POLICY_NAME}.pp"
restorecon -Fv /dev/cros_fp
systemctl try-restart fprintd.service

semodule -l | grep -Fxq "${POLICY_NAME}"
ls -lZ /dev/cros_fp
echo "Installed the narrow ${POLICY_NAME} SELinux policy."
