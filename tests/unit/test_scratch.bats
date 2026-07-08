#!/usr/bin/env bats
load helpers/load.bash

run_scratch() {
  run env LL_TEST_MODE=1 \
    LL_STATE_DIR="${LL_STATE_DIR}" LL_SECRETS_DIR="${LL_SECRETS_DIR}" LL_LOG_FILE="${LL_LOG_FILE}" \
    PATH="${REPO_ROOT}/tests/unit/fixtures/bin:${PATH}" \
    bash -c "source '${REPO_ROOT}/tools/scratch/scratch.sh'; $*"
}

@test "scratch_hostname uses the ll-smoke- prefix" {
  run_scratch 'scratch_hostname myprobe'
  assert_success
  assert_output "ll-smoke-myprobe"
}

@test "scratch_hostname defaults to ll-smoke-scratch" {
  run_scratch 'scratch_hostname'
  assert_success
  assert_output "ll-smoke-scratch"
}

@test "scratch_manifest reads a preset value from the real manifest" {
  run_scratch 'scratch_manifest ".presets.\"minimal\".ram_mb"'
  assert_success
  assert_output "512"
}

@test "scratch_resolve_template returns a matching installed volid" {
  MOCK_PVEAM_LIST="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" \
    run_scratch 'MOCK_PVEAM_LIST="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst" scratch_resolve_template debian-12-standard'
  assert_success
  assert_output --partial "debian-12-standard"
}
