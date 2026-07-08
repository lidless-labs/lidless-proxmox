#!/usr/bin/env bats
load helpers/load.bash

setup_file() { :; }

@test "state_set / state_get round-trips a nested key" {
  source_lib logging
  source_lib json-out
  state_set adguard lxc.vmid 9001
  run state_get adguard lxc.vmid
  assert_success
  assert_output "9001"
}

@test "state_get returns empty for a missing key" {
  source_lib logging
  source_lib json-out
  run state_get adguard nope.missing
  assert_success
  assert_output ""
}

@test "redact_json masks password-like keys" {
  source_lib logging
  source_lib json-out
  run bash -c 'echo "{\"admin_password\":\"hunter2\",\"url\":\"http://x/\"}" | { source "'"$REPO_ROOT"'/lib/logging.sh"; source "'"$REPO_ROOT"'/lib/json-out.sh"; redact_json; }'
  assert_success
  assert_output --partial 'REDACTED'
  refute_output --partial 'hunter2'
  assert_output --partial 'http://x/'
}

@test "emit_tool_json writes a redacted result with the tool name" {
  source_lib logging
  source_lib json-out
  state_set adguard adguard_admin_password "hunter2"
  state_set adguard adguard_url "http://198.51.100.5/"
  local out="${BATS_TEST_TMPDIR}/result.json"
  emit_tool_json adguard "${out}"
  run jq -r '.tool.name' "${out}"
  assert_output "adguard"
  run jq -r '.tool.adguard_admin_password' "${out}"
  assert_output "REDACTED"
  run jq -r '.tool.adguard_url' "${out}"
  assert_output "http://198.51.100.5/"
}
