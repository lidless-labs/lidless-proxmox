#!/usr/bin/env bash
# Loaded at the top of every .bats file via `load helpers/load.bash`

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
export REPO_ROOT

load "${REPO_ROOT}/tests/vendor/bats-support/load"
load "${REPO_ROOT}/tests/vendor/bats-assert/load"
bats_require_minimum_version 1.5.0

# Prepend fake-binary fixtures dir to PATH so mocks intercept pct/qm/etc.
export PATH="${REPO_ROOT}/tests/unit/fixtures/bin:${PATH}"

# Per-test isolated state
setup() {
  export LL_STATE_DIR="${BATS_TEST_TMPDIR}/var/lib/lidless"
  export LL_LOG_FILE="${BATS_TEST_TMPDIR}/lidless.log"
  export LL_SECRETS_DIR="${LL_STATE_DIR}/secrets"
  mkdir -p "${LL_STATE_DIR}/state" "${LL_SECRETS_DIR}"
}

# Source a lib module under test
source_lib() {
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/lib/${1}.sh"
}
