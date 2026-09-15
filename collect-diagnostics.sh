#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
output="${1:-${SOURCE_DIR}/diagnostics-${timestamp}.txt}"
account="${SUDO_USER:-${USER}}"

{
	echo "Redrix fingerprint diagnostics"
	echo "Captured: $(date --iso-8601=seconds)"
	echo
	echo "== System =="
	uname -a
	cat /etc/os-release
	for field in sys_vendor product_name product_version board_vendor board_name board_version bios_version bios_date; do
		if [[ -r "/sys/class/dmi/id/${field}" ]]; then
			printf '%s: ' "${field}"
			cat "/sys/class/dmi/id/${field}"
		fi
	done
	echo
	echo "== Packages =="
	rpm -q libfprint fprintd fprintd-pam
	rpm -V libfprint || true
	echo
	echo "== Device =="
	stat -c '%A %U:%G %t:%T %n' /dev/cros_fp 2>&1 || true
	ls -lZ /dev/cros_fp 2>&1 || true
	semodule -l 2>/dev/null | grep -F fprintd_cros_fp || true
	find /sys/devices -path '*/chromeos/cros_fp/version' -readable -exec cat {} \; 2>/dev/null || true
	echo
	echo "== Installed library =="
	sha256sum /usr/lib64/libfprint-2.so.2.0.0
	if grep -aFq 'libfprint-crfpmoc' /usr/lib64/libfprint-2.so.2.0.0; then
		echo "crfpmoc marker: present"
	else
		echo "crfpmoc marker: absent"
	fi
	echo
	echo "== fprintd enumeration =="
	fprintd-list "${account}" 2>&1 || true
	echo
	echo "== fprintd open/claim test (does not enroll) =="
	gdbus call --system \
		--dest net.reactivated.Fprint \
		--object-path /net/reactivated/Fprint/Device/0 \
		--method net.reactivated.Fprint.Device.Claim "${account}" 2>&1 || true
	echo
	echo "== Authentication profile =="
	authselect current 2>&1 || true
	echo
	echo "== Relevant kernel journal =="
	journalctl -b -k --no-pager 2>&1 | \
		grep -Ei 'finger|fprint|fpc|cros.?fp|PRP0001|CRFP' || true
	echo
	echo "== fprintd journal =="
	journalctl -b -u fprintd.service --no-pager 2>&1 || true
	echo
	echo "== Relevant SELinux denials =="
	journalctl -b --no-pager 2>&1 | \
		grep -Ei 'avc:.*(fprint|cros_fp)|selinux.*(fprint|cros_fp)|denied.*(fprint|cros_fp)' || true
} > "${output}"

echo "Wrote ${output}"
echo "No fingerprint templates or fingerprint images were collected."
