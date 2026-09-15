#!/usr/bin/env bash
set -euo pipefail

TARGET_LIBRARY="/usr/lib64/libfprint-2.so.2.0.0"
account="${SUDO_USER:-${USER}}"

echo "DMI: $(< /sys/class/dmi/id/sys_vendor) $(< /sys/class/dmi/id/product_name) $(< /sys/class/dmi/id/product_version)"
echo "OS: $(. /etc/os-release; echo "${PRETTY_NAME}")"
echo "Kernel: $(uname -r)"
echo "libfprint package: $(rpm -q libfprint)"

echo "--- FPMCU ---"
test -c /dev/cros_fp
stat -c '%A %U:%G %t:%T %n' /dev/cros_fp
ls -lZ /dev/cros_fp
test "$(stat -c '%C' /dev/cros_fp)" = "system_u:object_r:cros_fp_device_t:s0"
if [[ ${EUID} -eq 0 ]]; then
	semodule -l | grep -Fx fprintd_cros_fp
else
	echo "SELinux module listing requires root; the persistent device label is present."
fi
grep -F 'CrOS Fingerprint MCU detected' < <(journalctl -b -k --no-pager) | tail -1

version_file="$(find /sys/devices -path '*/chromeos/cros_fp/version' -print -quit 2>/dev/null)"
if [[ -n "${version_file}" && -r "${version_file}" ]]; then
	cat "${version_file}"
fi

echo "--- Driver library ---"
test -r "${TARGET_LIBRARY}"
sha256sum "${TARGET_LIBRARY}"
grep -aFq 'libfprint-crfpmoc' "${TARGET_LIBRARY}"
echo "crfpmoc marker: present"
echo "RPM verification (a modified library is expected while crfpmoc is installed):"
rpm -V libfprint || true

echo "--- Service and PAM ---"
grep -F 'DeviceAllow=/dev/cros_fp rw' /usr/lib/systemd/system/fprintd.service
authselect current

echo "--- fprintd enumeration ---"
fprintd-list "${account}"

echo "--- fprintd open/claim test (does not enroll) ---"
gdbus call --system \
	--dest net.reactivated.Fprint \
	--object-path /net/reactivated/Fprint/Device/0 \
	--method net.reactivated.Fprint.Device.Claim "${account}"
echo "Device claim and MCU initialization: passed"
