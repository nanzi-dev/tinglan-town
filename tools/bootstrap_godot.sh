#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GODOT_VERSION="4.7.1"
GODOT_RELEASE="${GODOT_VERSION}-stable"
GODOT_EXPECTED_VERSION="4.7.1.stable.official.a13da4feb"
GODOT_ARCHIVE="Godot_v${GODOT_RELEASE}_linux.x86_64.zip"
GODOT_ARCHIVE_SHA512="4ccdab7a48eeccbe8819a2fc1f6262f8d72065d98601bcb3743fcbd7ebd39f373758a788ee3293a05ec5b2c48538266c437404312e372225cd2df273945a2de9"
GODOT_BINARY_SHA512="f6f5197c33978f671edf6c851ebedbbcab10714cbd15a4bf3d7a0025322c558671154ae2b160d48fb95a44edcddfdb37dc9bcf2afd4759accb57421cf7b586ca"
TEMPLATE_ARCHIVE="Godot_v${GODOT_RELEASE}_export_templates.tpz"
TEMPLATE_ARCHIVE_SHA512="afcc83d8d3d298038f19c58744a0d660fa75dd4baa33cb55d1011bb2565a2a8c2381728924564cb909e37c205a23f21b521b23bd057993afd43ae4da0b2f9d47"
TEMPLATE_LINUX_SHA512="9cd933f8bf1fbbe189596ba5b020c995bd3ff34124c57d4fa3e9f9f6627e9647352ae567d4c93d777aa427d77f7cf585f289c9a1e9f8eacfa379fbd983133fdf"
TEMPLATE_WINDOWS_SHA512="e279b3f1f1173e68b916bc1077ba62db3ed2bc7fad2935d6592ec26d1708a79e8fe16fb9c9e265ab6c9b2b7d581839c05e960403790af7564b202081425dcb42"
GUT_VERSION="9.7.0"
GUT_ARCHIVE="Gut-v${GUT_VERSION}.tar.gz"
GUT_ARCHIVE_SHA256="6697bc35636fecea84a13604a84642612c214134ce96ea451e4ee35d69f56ef1"
GUT_TREE_SHA256="ae0a7ae22e4805e24cb2217eba9bebc41884a0dcc01473f7613a5e4aca19a15d"
TOOLS_DIR="${ROOT}/.tools"
CACHE_DIR="${TOOLS_DIR}/cache"
GODOT_DIR="${TOOLS_DIR}/godot"
GODOT_BIN="${GODOT_DIR}/godot"
PROJECT_LOCK="${TOOLS_DIR}/bootstrap.lock"
TEMPLATE_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
GUT_PLUGIN_CFG="${ROOT}/addons/gut/plugin.cfg"

require_commands() {
	local missing=0
	local command_name
	for command_name in "$@"; do
		if ! command -v "${command_name}" >/dev/null 2>&1; then
			echo "Missing required command: ${command_name}" >&2
			missing=1
		fi
	done
	(( missing == 0 ))
}

verify_checksum() {
	local algorithm="$1"
	local expected="$2"
	local file="$3"
	local checksum_command="${algorithm}sum"

	printf '%s  %s\n' "${expected}" "${file}" | "${checksum_command}" --check --status
}

godot_binary_is_trusted() {
	local binary="$1"
	[[ -f "${binary}" ]] &&
		[[ ! -L "${binary}" ]] &&
		verify_checksum "sha512" "${GODOT_BINARY_SHA512}" "${binary}"
}

download() {
	local url="$1"
	local output="$2"
	local algorithm="$3"
	local expected="$4"
	local part="${output}.part"

	mkdir -p "$(dirname "${output}")"
	if [[ -f "${output}" ]] && verify_checksum "${algorithm}" "${expected}" "${output}"; then
		return
	fi
	if [[ -f "${output}" ]]; then
		echo "Checksum mismatch for cached file: ${output}" >&2
	fi
	if [[ -f "${part}" ]]; then
		if verify_checksum "${algorithm}" "${expected}" "${part}"; then
			mv "${part}" "${output}"
			return
		fi
		rm -f "${part}"
	fi

	local attempt
	for attempt in 1 2; do
		if curl \
			--http1.1 \
			--fail \
			--location \
			--retry 5 \
			--retry-all-errors \
			--retry-delay 2 \
			--continue-at - \
			"${url}" \
			--output "${part}"
		then
			if verify_checksum "${algorithm}" "${expected}" "${part}"; then
				mv "${part}" "${output}"
				return
			fi
			echo "Checksum mismatch for downloaded file: ${part}" >&2
		fi
		rm -f "${part}"
	done

	echo "Failed to download a valid ${output}" >&2
	return 1
}

godot_version_matches() {
	if ! godot_binary_is_trusted "${GODOT_BIN}" || [[ ! -x "${GODOT_BIN}" ]]; then
		return 1
	fi

	local actual_version
	actual_version="$("${GODOT_BIN}" --version 2>/dev/null)" || return 1
	[[ "${actual_version}" == "${GODOT_EXPECTED_VERSION}" ]]
}

replace_directory() (
	local replacement="$1"
	local target="$2"
	local backup="${target}.backup.$$"
	local target_existed=0
	local committed=0

	rm -rf "${backup}" || return $?
	if [[ -e "${target}" ]]; then
		target_existed=1
	fi

	restore_original_directory() {
		if (( target_existed )); then
			if [[ -e "${backup}" ]]; then
				if [[ -e "${target}" ]] && ! rm -rf "${target}"; then
					return 1
				fi
				mv "${backup}" "${target}"
			elif [[ ! -e "${target}" ]]; then
				return 1
			fi
		elif [[ -e "${target}" ]]; then
			rm -rf "${target}"
		fi
	}

	cleanup_directory_backup() {
		if ! rm -rf "${backup}"; then
			echo "Warning: failed to remove committed directory backup: ${backup}" >&2
		fi
	}

	rollback_directory_replacement() {
		local original_status="$1"
		local handler_status=0

		trap - EXIT
		if (( committed )); then
			cleanup_directory_backup
		elif ! restore_original_directory; then
			handler_status=1
		fi

		if (( original_status != 0 )); then
			exit "${original_status}"
		fi
		exit "${handler_status}"
	}

	trap 'rollback_directory_replacement "$?"' EXIT
	if (( target_existed )); then
		mv "${target}" "${backup}" || exit $?
	fi
	mv "${replacement}" "${target}" || exit $?
	committed=1
	trap - EXIT
	cleanup_directory_backup
)

install_godot() (
	if godot_version_matches; then
		return
	fi

	mkdir -p "${TOOLS_DIR}"
	local archive="${CACHE_DIR}/${GODOT_ARCHIVE}"
	download \
		"https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/${GODOT_ARCHIVE}" \
		"${archive}" \
		"sha512" \
		"${GODOT_ARCHIVE_SHA512}"

	local temp_dir
	temp_dir="$(mktemp -d "${TOOLS_DIR}/godot-install.XXXXXX")"
	trap 'rm -rf "${temp_dir}"' EXIT
	unzip -q "${archive}" -d "${temp_dir}"
	local extracted
	extracted="$(find "${temp_dir}" -maxdepth 1 -type f -name 'Godot_*' -print -quit)"
	if [[ -z "${extracted}" ]]; then
		echo "Godot archive did not contain an executable" >&2
		return 1
	fi

	local replacement="${temp_dir}/ready"
	mkdir -p "${replacement}"
	mv "${extracted}" "${replacement}/godot"
	if ! godot_binary_is_trusted "${replacement}/godot"; then
		echo "Godot archive did not contain the expected executable" >&2
		return 1
	fi
	chmod +x "${replacement}/godot"
	local extracted_version
	extracted_version="$("${replacement}/godot" --version)"
	if [[ "${extracted_version}" != "${GODOT_EXPECTED_VERSION}" ]]; then
		echo "Expected Godot ${GODOT_EXPECTED_VERSION}, got ${extracted_version}" >&2
		return 1
	fi

	replace_directory "${replacement}" "${GODOT_DIR}"
	rm -f "${ROOT}/.godot/global_script_class_cache.cfg"
)

gut_install_matches() {
	local install_dir="$1"
	[[ -d "${install_dir}" ]] && [[ ! -L "${install_dir}" ]] || return 1

	local unexpected_entry
	local actual_digest
	actual_digest="$(
		cd "${install_dir}"
		unexpected_entry="$(find . ! -type d ! -type f -print -quit)" || exit 1
		[[ -z "${unexpected_entry}" ]] || exit 1
		find . -type f -print0 |
			LC_ALL=C sort -z |
			xargs -0 sha256sum |
			sha256sum
	)" || return 1
	[[ "${actual_digest%% *}" == "${GUT_TREE_SHA256}" ]]
}

install_gut() (
	if (
		gut_install_matches "${ROOT}/addons/gut"
	); then
		return
	fi

	mkdir -p "${ROOT}/addons"
	local archive="${CACHE_DIR}/${GUT_ARCHIVE}"
	download \
		"https://github.com/bitwes/Gut/archive/refs/tags/v${GUT_VERSION}.tar.gz" \
		"${archive}" \
		"sha256" \
		"${GUT_ARCHIVE_SHA256}"

	local temp_dir
	temp_dir="$(mktemp -d "${ROOT}/addons/.gut-install.XXXXXX")"
	trap 'rm -rf "${temp_dir}"' EXIT
	tar -xzf "${archive}" -C "${temp_dir}"
	local replacement="${temp_dir}/Gut-${GUT_VERSION}/addons/gut"
	if ! gut_install_matches "${replacement}"; then
		echo "GUT archive did not contain the expected ${GUT_VERSION} tree" >&2
		return 1
	fi

	replace_directory "${replacement}" "${ROOT}/addons/gut"
	rm -f "${ROOT}/.godot/global_script_class_cache.cfg"
)

import_project_classes() {
	local class_cache="${ROOT}/.godot/global_script_class_cache.cfg"
	if [[ -f "${class_cache}" ]] && grep -Fq '"class": &"GutTest"' "${class_cache}"; then
		return
	fi

	"${GODOT_BIN}" --headless --editor --path "${ROOT}" --quit
}

export_templates_match() {
	local install_dir="$1"
	[[ -f "${install_dir}/version.txt" ]] &&
		[[ "$(<"${install_dir}/version.txt")" == "${GODOT_VERSION}.stable" ]] &&
		[[ -f "${install_dir}/linux_release.x86_64" ]] &&
		[[ -f "${install_dir}/windows_release_x86_64.exe" ]] &&
		verify_checksum "sha512" "${TEMPLATE_LINUX_SHA512}" "${install_dir}/linux_release.x86_64" &&
		verify_checksum "sha512" "${TEMPLATE_WINDOWS_SHA512}" "${install_dir}/windows_release_x86_64.exe"
}

install_export_templates() (
	if [[ "${TINGLAN_SKIP_EXPORT_TEMPLATES:-0}" == "1" ]]; then
		return
	fi

	local template_parent
	template_parent="$(dirname "${TEMPLATE_DIR}")"
	mkdir -p "${template_parent}"
	local template_lock="${template_parent}/.${GODOT_VERSION}.stable.bootstrap.lock"
	local template_lock_fd
	exec {template_lock_fd}>"${template_lock}"
	if ! flock "${template_lock_fd}"; then
		echo "Failed to acquire export-template lock: ${template_lock}" >&2
		return 1
	fi
	if export_templates_match "${TEMPLATE_DIR}"; then
		return
	fi

	local archive="${CACHE_DIR}/${TEMPLATE_ARCHIVE}"
	download \
		"https://github.com/godotengine/godot/releases/download/${GODOT_RELEASE}/${TEMPLATE_ARCHIVE}" \
		"${archive}" \
		"sha512" \
		"${TEMPLATE_ARCHIVE_SHA512}"

	local temp_dir
	temp_dir="$(mktemp -d "${template_parent}/.templates-install.XXXXXX")"
	trap 'rm -rf "${temp_dir}"' EXIT
	unzip -q "${archive}" -d "${temp_dir}"
	local replacement="${temp_dir}/templates"
	if ! export_templates_match "${replacement}"; then
		echo "Export template archive did not contain the required ${GODOT_VERSION} files" >&2
		return 1
	fi

	replace_directory "${replacement}" "${TEMPLATE_DIR}"
)

require_commands \
	chmod \
	curl \
	dirname \
	find \
	flock \
	grep \
	head \
	mkdir \
	mktemp \
	mv \
	rm \
	sed \
	sha256sum \
	sha512sum \
	sort \
	tar \
	unzip \
	xargs
mkdir -p "${TOOLS_DIR}" "${CACHE_DIR}"
project_lock_fd=
exec {project_lock_fd}>"${PROJECT_LOCK}"
if ! flock "${project_lock_fd}"; then
	echo "Failed to acquire project bootstrap lock: ${PROJECT_LOCK}" >&2
	exit 1
fi
install_godot
install_gut
import_project_classes
install_export_templates

if ! godot_version_matches; then
	echo "Godot executable failed integrity or version validation" >&2
	exit 1
fi
actual_version="$("${GODOT_BIN}" --version)"
actual_gut_version="$(sed -n 's/^version="\([^"]*\)"/\1/p' "${GUT_PLUGIN_CFG}" | head -n 1)"
if [[ "${actual_gut_version}" != "${GUT_VERSION}" ]]; then
	echo "Expected GUT ${GUT_VERSION}, got ${actual_gut_version:-unknown}" >&2
	exit 1
fi
printf 'Godot %s\n' "${actual_version}"
printf 'GUT %s\n' "${actual_gut_version}"
