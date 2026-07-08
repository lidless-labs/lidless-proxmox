#!/usr/bin/env bats
# The reaper must destroy only aged containers in the 9000-9099 band and never
# touch production VMIDs, even when they are old.
load helpers/load.bash

setup() {
  CONF_DIR="${BATS_TEST_TMPDIR}/lxc"
  CALLS="${BATS_TEST_TMPDIR}/pct.log"
  mkdir -p "${CONF_DIR}"
  # Two smoke CTs (9001 old, 9002 fresh) and one production CT (100 old).
  export MOCK_PCT_LIST=$'VMID Status\n100 running\n9001 running\n9002 running'
  export MOCK_PCT_CALLS_LOG="${CALLS}"
  : > "${CALLS}"
  # 100 and 9001 are old; 9002 is brand new.
  touch "${CONF_DIR}/100.conf" "${CONF_DIR}/9001.conf" "${CONF_DIR}/9002.conf"
  touch -d '3 hours ago' "${CONF_DIR}/100.conf" "${CONF_DIR}/9001.conf"
}

reap() {
  run env PATH="${REPO_ROOT}/tests/unit/fixtures/bin:${PATH}" \
    LL_REAPER_LOG="${BATS_TEST_TMPDIR}/reaper.log" \
    LL_REAPER_CONF_DIR="${CONF_DIR}" \
    MOCK_PCT_LIST="${MOCK_PCT_LIST}" MOCK_PCT_CALLS_LOG="${MOCK_PCT_CALLS_LOG}" \
    bash "${REPO_ROOT}/tools/lidless-smoke-reaper.sh"
}

@test "reaps an aged container in the smoke band" {
  reap
  assert_success
  run grep -c "pct destroy 9001" "${CALLS}"
  assert_output "1"
}

@test "leaves a fresh container in the band alone" {
  reap
  run grep -c "pct destroy 9002" "${CALLS}"
  assert_output "0"
}

@test "never touches a production VMID even when aged" {
  reap
  run grep -c "pct destroy 100" "${CALLS}"
  assert_output "0"
}
