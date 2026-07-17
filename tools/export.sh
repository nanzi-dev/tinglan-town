#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GODOT="${ROOT}/.tools/godot/godot"
LINUX_OUTPUT="${ROOT}/build/linux/tides-of-tinglan.x86_64"
WINDOWS_OUTPUT="${ROOT}/build/windows/tides-of-tinglan.exe"

"${ROOT}/tools/bootstrap_godot.sh"

mkdir -p "$(dirname "${LINUX_OUTPUT}")" "$(dirname "${WINDOWS_OUTPUT}")"
rm -f "${LINUX_OUTPUT}" "${WINDOWS_OUTPUT}"

"${GODOT}" \
	--headless \
	--path "${ROOT}" \
	--export-release Linux \
	"${LINUX_OUTPUT}"
"${GODOT}" \
	--headless \
	--path "${ROOT}" \
	--export-release Windows \
	"${WINDOWS_OUTPUT}"

for output in "${LINUX_OUTPUT}" "${WINDOWS_OUTPUT}"; do
	if [[ ! -s "${output}" ]]; then
		echo "Export did not create a non-empty artifact: ${output}" >&2
		exit 1
	fi
done

chmod +x "${LINUX_OUTPUT}"
printf 'Linux: %s\nWindows: %s\n' "${LINUX_OUTPUT}" "${WINDOWS_OUTPUT}"
