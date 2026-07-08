#!/usr/bin/env bats
# Unit-tests the supply-chain claim: bootstrap.sh must verify the release
# tarball against its published sha256 and FAIL CLOSED on mismatch, never
# executing the payload. Uses a local mock `curl` that serves a real fake
# release; sha256sum and tar are real.
load helpers/load.bash

setup() {
  BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${BIN}"

  # Build a real fake release: <name>/lib/deploy-one.sh prints a sentinel.
  NAME="lidless-proxmox-vtest"
  STAGE="${BATS_TEST_TMPDIR}/stage"
  mkdir -p "${STAGE}/${NAME}/lib"
  cat > "${STAGE}/${NAME}/lib/deploy-one.sh" <<'EOF'
#!/usr/bin/env bash
echo "PAYLOAD-RAN tool=$1"
EOF
  ( cd "${STAGE}" && tar -czf "${BATS_TEST_TMPDIR}/${NAME}.tar.gz" "${NAME}" )
  GOOD_SHA="$(sha256sum "${BATS_TEST_TMPDIR}/${NAME}.tar.gz" | awk '{print $1}')"
  export FAKE_TARBALL="${BATS_TEST_TMPDIR}/${NAME}.tar.gz"
  export TARBALL_NAME="${NAME}.tar.gz"
  export GOOD_SHA

  # Mock curl: -O writes the URL basename into cwd. For the tarball, copy the
  # fake release; for the .sha256, emit a good or bad checksum per MOCK_SHA.
  cat > "${BIN}/curl" <<'EOF'
#!/usr/bin/env bash
url="${@: -1}"
base="$(basename "${url}")"
if [[ "${base}" == *.sha256 ]]; then
  if [[ "${MOCK_SHA:-good}" == "good" ]]; then
    printf '%s  %s\n' "${GOOD_SHA}" "${TARBALL_NAME}" > "${base}"
  else
    printf '%s  %s\n' "0000000000000000000000000000000000000000000000000000000000000000" "${TARBALL_NAME}" > "${base}"
  fi
else
  cp "${FAKE_TARBALL}" "${base}"
fi
EOF
  chmod +x "${BIN}/curl"
}

run_bootstrap() {
  run env PATH="${BIN}:${PATH}" LL_VERSION=vtest LL_REPO="x/y" \
    bash "${REPO_ROOT}/bootstrap.sh" someTool
}

@test "bootstrap runs the payload when the checksum matches" {
  MOCK_SHA=good run_bootstrap
  assert_success
  assert_output --partial "PAYLOAD-RAN tool=someTool"
}

@test "bootstrap fails closed and never runs the payload on checksum mismatch" {
  MOCK_SHA=bad run_bootstrap
  assert_failure
  refute_output --partial "PAYLOAD-RAN"
  assert_output --partial "CHECKSUM MISMATCH"
}
