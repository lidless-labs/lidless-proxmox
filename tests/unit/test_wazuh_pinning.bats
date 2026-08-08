#!/usr/bin/env bats
# Wazuh installer supply-chain tests. The real upstream installer is never run:
# curl is mocked to serve a tiny local script, and the test copy of install.sh is
# patched to expect that fixture's sha256.
load helpers/load.bash

setup() {
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export LL_STATE_DIR="${BATS_TEST_TMPDIR}/var/lib/lidless"
  export LL_TOOL="wazuh"
  export LL_PRESET="standard"
  export LL_NON_INTERACTIVE="1"
  export WAZUH_INSTALL_WORKDIR="${BATS_TEST_TMPDIR}/workdir"
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  export MOCK_WAZUH_INSTALLER="${BATS_TEST_TMPDIR}/mock-wazuh-install.sh"
  export MOCK_WAZUH_INSTALL_LOG="${BATS_TEST_TMPDIR}/wazuh-install-runs.log"
  export MOCK_WAZUH_INSTALLED="${BATS_TEST_TMPDIR}/wazuh-installed"

  mkdir -p "${TEST_BIN}" "${LL_STATE_DIR}/state" "${WAZUH_INSTALL_WORKDIR}" "${TMPDIR}"

  cat > "${MOCK_WAZUH_INSTALLER}" <<'EOF'
#!/usr/bin/env bash
readonly wazuh_version=4.9.2
printf '%s\n' "$*" >> "${MOCK_WAZUH_INSTALL_LOG}"
touch "${MOCK_WAZUH_INSTALLED}"
EOF
  chmod +x "${MOCK_WAZUH_INSTALLER}"
  export MOCK_WAZUH_INSTALLER_SHA256
  MOCK_WAZUH_INSTALLER_SHA256="$(sha256sum "${MOCK_WAZUH_INSTALLER}" | awk '{print $1}')"

  cat > "${TEST_BIN}/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_BIN}/apt-get"

  cat > "${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
out=""
url=""
while (($#)); do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
if [[ -z "${out}" ]]; then
  out="$(basename "${url}")"
fi
cp "${MOCK_WAZUH_INSTALLER}" "${out}"
EOF
  chmod +x "${TEST_BIN}/curl"

  cat > "${TEST_BIN}/hostname" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-I" ]]; then
  printf '192.0.2.10 \n'
else
  printf 'wazuh-test\n'
fi
EOF
  chmod +x "${TEST_BIN}/hostname"

  cat > "${TEST_BIN}/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then
  [[ -f "${MOCK_WAZUH_INSTALLED}" ]]
  exit $?
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/systemctl"
}

copy_install_script() {
  local sha="${1:-${MOCK_WAZUH_INSTALLER_SHA256}}"
  SCRIPT_UNDER_TEST="${BATS_TEST_TMPDIR}/install-under-test.sh"
  cp "${REPO_ROOT}/tools/wazuh/install.sh" "${SCRIPT_UNDER_TEST}"
  sed -i "s|^readonly WAZUH_INSTALL_SHA256=.*|readonly WAZUH_INSTALL_SHA256=\"${sha}\"|" "${SCRIPT_UNDER_TEST}"
  chmod +x "${SCRIPT_UNDER_TEST}"
  export SCRIPT_UNDER_TEST
}

run_wazuh_install() {
  run env \
    PATH="${TEST_BIN}:${PATH}" \
    LL_STATE_DIR="${LL_STATE_DIR}" \
    LL_TOOL="${LL_TOOL}" \
    LL_PRESET="${LL_PRESET}" \
    LL_NON_INTERACTIVE="${LL_NON_INTERACTIVE}" \
    WAZUH_INSTALL_WORKDIR="${WAZUH_INSTALL_WORKDIR}" \
    TMPDIR="${TMPDIR}" \
    MOCK_WAZUH_INSTALLER="${MOCK_WAZUH_INSTALLER}" \
    MOCK_WAZUH_INSTALL_LOG="${MOCK_WAZUH_INSTALL_LOG}" \
    MOCK_WAZUH_INSTALLED="${MOCK_WAZUH_INSTALLED}" \
    bash "${SCRIPT_UNDER_TEST}"
}

@test "Wazuh manifest pinned data stays in sync with install.sh constants" {
  manifest_version="$(jq -r '.pinned.wazuh_installer_version' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_url="$(jq -r '.pinned.wazuh_installer_url' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_sha="$(jq -r '.pinned.wazuh_installer_sha256' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_declared_version="$(jq -r '.pinned.wazuh_installer_declared_version' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_release_url="$(jq -r '.pinned.wazuh_installer_release_url' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_source_repository="$(jq -r '.pinned.wazuh_installer_source_repository' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_capture_date="$(jq -r '.pinned.wazuh_installer_capture_date' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"
  manifest_provenance_note="$(jq -r '.pinned.wazuh_installer_provenance_note' "${REPO_ROOT}/tools/wazuh/manifest.jsonc")"

  script_version="$(sed -n 's/^readonly WAZUH_INSTALL_VERSION="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_url="$(sed -n 's/^readonly WAZUH_INSTALL_URL="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_sha="$(sed -n 's/^readonly WAZUH_INSTALL_SHA256="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_declared_version="$(sed -n 's/^readonly WAZUH_INSTALL_DECLARED_VERSION="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_release_url="$(sed -n 's/^readonly WAZUH_INSTALL_RELEASE_URL="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_source_repository="$(sed -n 's/^readonly WAZUH_INSTALL_SOURCE_REPOSITORY="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_capture_date="$(sed -n 's/^readonly WAZUH_INSTALL_CAPTURE_DATE="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"
  script_provenance_note="$(sed -n 's/^readonly WAZUH_INSTALL_PROVENANCE_NOTE="\([^"]*\)"/\1/p' "${REPO_ROOT}/tools/wazuh/install.sh")"

  [[ "${manifest_version}" == "${script_version}" ]]
  [[ "${manifest_url}" == "${script_url}" ]]
  [[ "${manifest_sha}" == "${script_sha}" ]]
  [[ "${manifest_declared_version}" == "${script_declared_version}" ]]
  [[ "${manifest_release_url}" == "${script_release_url}" ]]
  [[ "${manifest_source_repository}" == "${script_source_repository}" ]]
  [[ "${manifest_capture_date}" == "${script_capture_date}" ]]
  [[ "${manifest_provenance_note}" == "${script_provenance_note}" ]]
  [[ "${manifest_sha}" =~ ^[0-9a-f]{64}$ ]]
  [[ "${manifest_declared_version}" == "4.9.2" ]]
  [[ "${manifest_release_url}" == "https://github.com/wazuh/wazuh-packages/releases/tag/v4.9.2" ]]
  [[ "${manifest_source_repository}" == "https://github.com/wazuh/wazuh-packages" ]]
  [[ "${manifest_capture_date}" == "2026-08-08" ]]
  [[ "${manifest_provenance_note}" == *"release has no assets"* ]]
  [[ "${manifest_provenance_note}" == *"SHA-256"* ]]
}

@test "Wazuh install runs the downloaded installer only after checksum match" {
  copy_install_script
  run_wazuh_install
  assert_success
  assert_output --partial "Verified Wazuh installer 4.9.2"
  assert_output --partial "Wazuh deployment complete: https://192.0.2.10"

  run wc -l "${MOCK_WAZUH_INSTALL_LOG}"
  assert_output --partial "5 "
  run test -e "${LL_STATE_DIR}/state/wazuh.json"
  assert_success
  run test -z "$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -print -quit)"
  assert_success
}

@test "Wazuh install fails closed on checksum mismatch" {
  copy_install_script "0000000000000000000000000000000000000000000000000000000000000000"
  run_wazuh_install
  assert_failure
  assert_output --partial "Wazuh installer checksum mismatch"
  run test ! -e "${MOCK_WAZUH_INSTALL_LOG}"
  assert_success
}

@test "Wazuh install fails closed when the SHA-256 pin is missing" {
  copy_install_script
  sed -i '/^readonly WAZUH_INSTALL_SHA256=/d' "${SCRIPT_UNDER_TEST}"
  run_wazuh_install
  assert_failure
  assert_output --partial "missing Wazuh installer SHA-256 pin"
  run test ! -e "${MOCK_WAZUH_INSTALL_LOG}"
  assert_success
}

@test "Wazuh downloaded script never executes when its declared version is missing" {
  sed -i '/^readonly wazuh_version=/d' "${MOCK_WAZUH_INSTALLER}"
  MOCK_WAZUH_INSTALLER_SHA256="$(sha256sum "${MOCK_WAZUH_INSTALLER}" | awk '{print $1}')"
  copy_install_script
  run_wazuh_install
  assert_failure
  assert_output --partial "Wazuh installer declared version mismatch"
  run test ! -e "${MOCK_WAZUH_INSTALL_LOG}"
  assert_success
}

@test "Wazuh downloaded script never executes after verification failure" {
  copy_install_script "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  run_wazuh_install
  assert_failure
  refute_output --partial "Running wazuh-install.sh"
  run test ! -e "${MOCK_WAZUH_INSTALL_LOG}"
  assert_success
}
