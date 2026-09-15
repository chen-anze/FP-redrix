#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="$(mktemp /tmp/cros-fp-probe.XXXXXX)"
trap 'rm -f -- "${binary}"' EXIT

cc -Wall -Wextra -O2 "${SOURCE_DIR}/tools/cros-fp-probe.c" -o "${binary}"
chmod 0755 "${binary}"

if [[ ${EUID} -eq 0 ]]; then
	"${binary}"
else
	sudo "${binary}"
fi
