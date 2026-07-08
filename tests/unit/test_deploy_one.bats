#!/usr/bin/env bats
# deploy-one.sh sourced with LL_TEST_MODE=1 so main() does not run.
load helpers/load.bash

# Run deploy-one in a contained sub-shell (its `set -e` stays out of bats).
run_deploy() {
  run env LL_TEST_MODE=1 \
    LL_STATE_DIR="${LL_STATE_DIR}" LL_SECRETS_DIR="${LL_SECRETS_DIR}" LL_LOG_FILE="${LL_LOG_FILE}" \
    PATH="${REPO_ROOT}/tests/unit/fixtures/bin:${PATH}" \
    bash -c "source '${REPO_ROOT}/lib/deploy-one.sh'; $*"
}

@test "read_manifest resolves fields from the real adguard manifest" {
  run_deploy 'read_manifest adguard .name'
  assert_success
  assert_output "adguard"
}

@test "read_manifest reads a preset resource value" {
  run_deploy 'read_manifest adguard ".presets.\"standard\".ram_mb"'
  assert_success
  assert_output "1024"
}

@test "resolve_template returns an installed matching volid" {
  MOCK_PVEAM_LIST="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" \
    run_deploy 'MOCK_PVEAM_LIST="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" resolve_template debian-12-standard'
  assert_success
  assert_output --partial "debian-12-standard"
}

@test "deploy_one dry-run plans without creating a container" {
  export MOCK_PVEAM_LIST="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  export MOCK_PCT_CALLS_LOG="${BATS_TEST_TMPDIR}/pct.log"
  : > "${MOCK_PCT_CALLS_LOG}"
  run env LL_TEST_MODE=1 LL_DRY_RUN=1 LL_PRESET=standard \
    LL_STATE_DIR="${LL_STATE_DIR}" LL_SECRETS_DIR="${LL_SECRETS_DIR}" LL_LOG_FILE="${LL_LOG_FILE}" \
    MOCK_PVEAM_LIST="${MOCK_PVEAM_LIST}" MOCK_PCT_CALLS_LOG="${MOCK_PCT_CALLS_LOG}" \
    PATH="${REPO_ROOT}/tests/unit/fixtures/bin:${PATH}" \
    bash -c "source '${REPO_ROOT}/lib/deploy-one.sh'; deploy_one adguard"
  assert_success
  assert_output --partial "[dry-run]"
  # No container should have been created.
  run grep -c "pct create" "${MOCK_PCT_CALLS_LOG}"
  assert_output "0"
}

@test "deploy_one rejects an unknown tool" {
  run_deploy 'deploy_one totally-not-a-tool'
  assert_failure
}
