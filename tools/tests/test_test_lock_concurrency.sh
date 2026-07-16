#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
PROBE_FIXTURE="tools/tests/fixtures/test_test_lock_probe.gd"
PROBE_DIR="$(mktemp -d)"
PROBE_BIN="${PROBE_DIR}/bin"
RUN_MARKER="${PROBE_DIR}/run-state"
CLASS_CACHE="${ROOT}/.godot/global_script_class_cache.cfg"
REAL_RM="$(command -v rm)"
first_pid=
second_pid=

cleanup() {
	set +e
	if [[ -n "${first_pid}" ]] && kill -0 "${first_pid}" 2>/dev/null; then
		kill "${first_pid}"
		wait "${first_pid}"
	fi
	if [[ -n "${second_pid}" ]] && kill -0 "${second_pid}" 2>/dev/null; then
		kill "${second_pid}"
		wait "${second_pid}"
	fi
	"${REAL_RM}" -rf "${PROBE_DIR}"
}
trap cleanup EXIT

mkdir -p "${PROBE_BIN}"
ln -s "${ROOT}/tools/tests/fixtures/rm_class_cache_probe.sh" "${PROBE_BIN}/rm"

run_probe() {
	local probe_id="$1"
	local probe_role="$2"
	local output="$3"
	env \
		PATH="${PROBE_BIN}:${PATH}" \
		TINGLAN_TEST_LOCK_CLASS_CACHE="${CLASS_CACHE}" \
		TINGLAN_TEST_LOCK_PROBE_DIR="${PROBE_DIR}" \
		TINGLAN_TEST_LOCK_PROBE_ID="${probe_id}" \
		TINGLAN_TEST_LOCK_PROBE_ROLE="${probe_role}" \
		TINGLAN_TEST_LOCK_REAL_RM="${REAL_RM}" \
		TINGLAN_TEST_LOCK_RUN_MARKER="${RUN_MARKER}" \
		"${ROOT}/tools/test.sh" "${PROBE_FIXTURE}" >"${output}" 2>&1
}

run_probe first first "${PROBE_DIR}/first.out" &
first_pid=$!

state=
for (( attempt = 0; attempt < 400; attempt++ )); do
	if [[ -f "${RUN_MARKER}" ]]; then
		state="$(<"${RUN_MARKER}")"
	fi
	if [[ "${state}" == "running" ]]; then
		break
	fi
	if ! kill -0 "${first_pid}" 2>/dev/null; then
		break
	fi
	sleep 0.05
done
if [[ "${state}" != "running" ]]; then
	echo "First test process did not enter the lock probe" >&2
	wait "${first_pid}" || true
	first_pid=
	sed -n '1,200p' "${PROBE_DIR}/first.out" >&2
	exit 1
fi

run_probe second second "${PROBE_DIR}/second.out" &
second_pid=$!

overlap=no
for (( attempt = 0; attempt < 400; attempt++ )); do
	state="$(<"${RUN_MARKER}")"
	if [[ -f "${PROBE_DIR}/cache-rm-second" && "${state}" != "done" ]]; then
		overlap=yes
		break
	fi
	if [[ "${state}" == "done" ]]; then
		break
	fi
	sleep 0.01
done

set +e
wait "${first_pid}"
first_status=$?
first_pid=
wait "${second_pid}"
second_status=$?
second_pid=
set -e

printf 'overlap=%s first_rc=%s second_rc=%s\n' \
	"${overlap}" \
	"${first_status}" \
	"${second_status}"
if (( first_status != 0 || second_status != 0 )); then
	echo "--- first output ---" >&2
	sed -n '1,200p' "${PROBE_DIR}/first.out" >&2
	echo "--- second output ---" >&2
	sed -n '1,200p' "${PROBE_DIR}/second.out" >&2
	exit 1
fi
[[ "${overlap}" == "no" ]]
