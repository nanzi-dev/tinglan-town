#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GODOT="${ROOT}/.tools/godot/godot"
GODOT_BINARY_SHA512="f6f5197c33978f671edf6c851ebedbbcab10714cbd15a4bf3d7a0025322c558671154ae2b160d48fb95a44edcddfdb37dc9bcf2afd4759accb57421cf7b586ca"
CLASS_CACHE="${ROOT}/.godot/global_script_class_cache.cfg"

for command_name in awk realpath; do
	if ! command -v "${command_name}" >/dev/null 2>&1; then
		echo "Missing required command: ${command_name}" >&2
		exit 1
	fi
done

requested_target="${1:-tests}"
if [[ "${requested_target}" == /* ]]; then
	target_path="${requested_target}"
else
	target_path="${ROOT}/${requested_target}"
fi
target_path="$(realpath -m -- "${target_path}")"
if [[ "${target_path}" == "${ROOT}" ]]; then
	target="."
elif [[ "${target_path}" == "${ROOT}/"* ]]; then
	target="${target_path#"${ROOT}/"}"
else
	echo "Test target must be inside the project: ${requested_target}" >&2
	exit 2
fi
if [[ ! -e "${target_path}" ]]; then
	echo "Test target does not exist: ${requested_target}" >&2
	exit 2
fi
if [[ ! -f "${target_path}" && ! -d "${target_path}" ]]; then
	echo "Test target must be a regular file or directory: ${requested_target}" >&2
	exit 2
fi
if ! command -v tee >/dev/null 2>&1; then
	echo "Missing required command: tee" >&2
	exit 1
fi

TINGLAN_SKIP_EXPORT_TEMPLATES=1 "${ROOT}/tools/bootstrap_godot.sh"

if [[ ! -f "${GODOT}" ]] || [[ -L "${GODOT}" ]] ||
	! printf '%s  %s\n' "${GODOT_BINARY_SHA512}" "${GODOT}" |
		sha512sum --check --status
then
	echo "Godot executable failed integrity validation: ${GODOT}" >&2
	exit 1
fi

test_lock="${ROOT}/.tools/test.lock"
test_lock_fd=
exec {test_lock_fd}>"${test_lock}"
if ! flock "${test_lock_fd}"; then
	echo "Failed to acquire test lock: ${test_lock}" >&2
	exit 1
fi

rm -f "${CLASS_CACHE}"
"${GODOT}" --headless --editor --path "${ROOT}" --quit
if [[ ! -f "${CLASS_CACHE}" ]]; then
	echo "Godot did not rebuild the global script class cache" >&2
	exit 1
fi

class_cache_has_pair() {
	local expected_class="$1"
	local expected_path="$2"
	awk \
		-v expected_class="${expected_class}" \
		-v expected_path="${expected_path}" '
		/^"class": &"/ {
			current_class = $0
			sub(/^"class": &"/, "", current_class)
			sub(/"[,]?$/, "", current_class)
		}
		/^"path": "/ {
			current_path = $0
			sub(/^"path": "/, "", current_path)
			sub(/"[,]?$/, "", current_path)
			if (current_class == expected_class && current_path == expected_path) {
				found = 1
			}
			current_class = ""
		}
		END {
			exit found ? 0 : 1
		}
	' "${CLASS_CACHE}"
}

required_class_paths=(
	"GutConstants|res://addons/gut/gut_constants.gd"
	"GutErrorTracker|res://addons/gut/error_tracker.gd"
	"GutHookScript|res://addons/gut/hook_script.gd"
	"GutInputFactory|res://addons/gut/input_factory.gd"
	"GutInputSender|res://addons/gut/input_sender.gd"
	"GutMain|res://addons/gut/gut.gd"
	"GutStringUtils|res://addons/gut/strutils.gd"
	"GutTest|res://addons/gut/test.gd"
	"GutTrackedError|res://addons/gut/gut_tracked_error.gd"
	"GutUtils|res://addons/gut/utils.gd"
)
for class_path in "${required_class_paths[@]}"; do
	class_name="${class_path%%|*}"
	script_path="${class_path#*|}"
	if ! class_cache_has_pair "${class_name}" "${script_path}"; then
		echo "Missing Godot class cache entry: ${class_name} -> ${script_path}" >&2
		exit 1
	fi
done

args=(
	--headless
	--path "${ROOT}"
	-s res://addons/gut/gut_cmdln.gd
	-gdisable_colors
	-gexit
)

if [[ -f "${target_path}" ]]; then
	args+=("-gtest=res://${target}")
else
	args+=("-gdir=res://${target}" -ginclude_subdirs)
fi

gut_output="$(mktemp "${ROOT}/.tools/gut-output.XXXXXX")"
trap 'rm -f "${gut_output}"' EXIT
set +e
"${GODOT}" "${args[@]}" 2>&1 | tee "${gut_output}"
pipeline_status=("${PIPESTATUS[@]}")
set -e
gut_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"
if (( gut_status != 0 )); then
	exit "${gut_status}"
fi
if (( tee_status != 0 )); then
	exit "${tee_status}"
fi

tests_run="$(
	awk '
		$0 == "Totals" {
			in_totals = 1
			next
		}
		in_totals && $1 == "Tests" && $2 ~ /^[0-9]+$/ && NF == 2 {
			print $2
			exit
		}
	' "${gut_output}"
)"
if [[ ! "${tests_run}" =~ ^[0-9]+$ ]] || (( tests_run == 0 )); then
	echo "GUT summary did not report any executed tests" >&2
	exit 1
fi
