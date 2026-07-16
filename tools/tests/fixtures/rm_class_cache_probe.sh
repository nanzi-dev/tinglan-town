#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
	if [[ "${argument}" == "${TINGLAN_TEST_LOCK_CLASS_CACHE}" ]]; then
		printf 'entered\n' >"${TINGLAN_TEST_LOCK_PROBE_DIR}/cache-rm-${TINGLAN_TEST_LOCK_PROBE_ID}"
		break
	fi
done

exec "${TINGLAN_TEST_LOCK_REAL_RM}" "$@"
