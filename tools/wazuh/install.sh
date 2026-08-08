#!/usr/bin/env bash
# tools/wazuh/install.sh
# Runs INSIDE the Wazuh LXC. Idempotent. Installs Wazuh single-node.
#
# Required env (set by orchestrator via pct exec):
#   LL_STATE_DIR        - path inside the LXC (e.g. /var/lib/lidless);
#                          orchestrator pulls outputs via pct pull after exit
#   LL_TOOL        - "wazuh"
#   LL_PRESET           - informational
#   LL_NON_INTERACTIVE  - "1"
#
# On success: writes ${LL_STATE_DIR}/state/wazuh.json with status=deployed
# On failure: writes ${LL_STATE_DIR}/state/wazuh.json with status=failed + error

set -euo pipefail

: "${LL_STATE_DIR:?LL_STATE_DIR must be set}"
: "${LL_TOOL:=wazuh}"
: "${WAZUH_INSTALL_WORKDIR:=/root}"

readonly WAZUH_INSTALL_VERSION="4.9.2"
readonly WAZUH_INSTALL_URL="https://packages.wazuh.com/4.9/wazuh-install.sh"
readonly WAZUH_INSTALL_SHA256="0cf8e370cdfdd8187af16bff2bd1fd09741c02eccc00c9458b6a814c7990decc"
readonly WAZUH_INSTALL_DECLARED_VERSION="4.9.2"
readonly WAZUH_INSTALL_SOURCE_REPOSITORY="https://github.com/wazuh/wazuh-packages"
readonly WAZUH_INSTALL_RELEASE_URL="https://github.com/wazuh/wazuh-packages/releases/tag/v4.9.2"
readonly WAZUH_INSTALL_CAPTURE_DATE="2026-08-08"
readonly WAZUH_INSTALL_PROVENANCE_NOTE="Official v4.9.2 release has no assets; CDN script is mutable and pinned by SHA-256."
readonly WAZUH_INSTALL_WORKDIR

STATE_FILE="${LL_STATE_DIR}/state/${LL_TOOL}.json"
SECRETS_DIR="${LL_STATE_DIR}/secrets"
WAZUH_INSTALL_TMPDIR=""
WAZUH_PASSWORD_TMPDIR=""
WAZUH_INSTALL_SCRIPT=""
mkdir -p "${LL_STATE_DIR}/state" "${SECRETS_DIR}"

log() { printf '[wazuh-deploy] %s\n' "$*"; }

cleanup_wazuh_tmp() {
  local dir tmp_parent
  tmp_parent="${TMPDIR:-/tmp}"
  for dir in "${WAZUH_INSTALL_TMPDIR:-}" "${WAZUH_PASSWORD_TMPDIR:-}"; do
    [[ -n "${dir}" && -d "${dir}" ]] || continue
    case "${dir}" in
      "${tmp_parent}"/wazuh-install.*|"${tmp_parent}"/wazuh-passwords.*)
        rm -rf -- "${dir}"
        ;;
    esac
  done
}

write_failed() {
  local err="$1"
  jq -n --arg err "${err}" '{
    component: "wazuh",
    status: "failed",
    error: $err
  }' > "${STATE_FILE}"
  log "FAILED: ${err}"
  exit 1
}

require_wazuh_installer_pin() {
  [[ -n "${WAZUH_INSTALL_VERSION:-}" ]] || write_failed "missing Wazuh installer version pin"
  [[ -n "${WAZUH_INSTALL_URL:-}" ]] || write_failed "missing Wazuh installer URL pin"
  [[ -n "${WAZUH_INSTALL_SHA256:-}" ]] || write_failed "missing Wazuh installer SHA-256 pin"
  [[ -n "${WAZUH_INSTALL_DECLARED_VERSION:-}" ]] || write_failed "missing Wazuh installer declared version metadata"
  [[ -n "${WAZUH_INSTALL_SOURCE_REPOSITORY:-}" ]] || write_failed "missing Wazuh installer source repository metadata"
  [[ -n "${WAZUH_INSTALL_RELEASE_URL:-}" ]] || write_failed "missing Wazuh installer release URL metadata"
  [[ -n "${WAZUH_INSTALL_CAPTURE_DATE:-}" ]] || write_failed "missing Wazuh installer capture date metadata"
  [[ -n "${WAZUH_INSTALL_PROVENANCE_NOTE:-}" ]] || write_failed "missing Wazuh installer provenance note metadata"
  [[ "${WAZUH_INSTALL_SHA256}" =~ ^[0-9a-f]{64}$ ]] || write_failed "invalid Wazuh installer SHA-256 pin"
}

verify_wazuh_installer_declared_version() {
  grep -Fxq "readonly wazuh_version=${WAZUH_INSTALL_DECLARED_VERSION}" "${WAZUH_INSTALL_SCRIPT}" && return 0
  grep -Fxq "readonly wazuh_version=\"${WAZUH_INSTALL_DECLARED_VERSION}\"" "${WAZUH_INSTALL_SCRIPT}" && return 0
  write_failed "Wazuh installer declared version mismatch: expected ${WAZUH_INSTALL_DECLARED_VERSION}"
}

download_wazuh_installer() {
  local actual_sha tmp_parent

  require_wazuh_installer_pin
  command -v sha256sum >/dev/null 2>&1 || write_failed "sha256sum is required to verify Wazuh installer"

  tmp_parent="${TMPDIR:-/tmp}"
  WAZUH_INSTALL_TMPDIR="$(mktemp -d "${tmp_parent}/wazuh-install.XXXXXXXXXX")"
  WAZUH_INSTALL_SCRIPT="${WAZUH_INSTALL_TMPDIR}/wazuh-install.sh"

  log "Downloading Wazuh installer ${WAZUH_INSTALL_VERSION}"
  curl -fsSL "${WAZUH_INSTALL_URL}" -o "${WAZUH_INSTALL_SCRIPT}" \
    || write_failed "failed to download Wazuh installer ${WAZUH_INSTALL_VERSION}"

  if ! actual_sha="$(sha256sum "${WAZUH_INSTALL_SCRIPT}" | awk '{print $1}')"; then
    write_failed "failed to calculate Wazuh installer checksum"
  fi

  if [[ "${actual_sha}" != "${WAZUH_INSTALL_SHA256}" ]]; then
    write_failed "Wazuh installer checksum mismatch: expected ${WAZUH_INSTALL_SHA256}, got ${actual_sha}"
  fi

  verify_wazuh_installer_declared_version
  log "Verified Wazuh installer ${WAZUH_INSTALL_VERSION}"
}

trap cleanup_wazuh_tmp EXIT
trap 'write_failed "deploy.sh aborted on line $LINENO"' ERR

# Idempotency: if services are already running, refresh state and exit 0
if systemctl is-active --quiet wazuh-manager 2>/dev/null \
   && systemctl is-active --quiet wazuh-indexer 2>/dev/null \
   && systemctl is-active --quiet wazuh-dashboard 2>/dev/null; then
  log "Wazuh already installed and running, refreshing state"

  IP="$(hostname -I | awk '{print $1}')"
  ADMIN_PASS=""
  if [[ -f "${SECRETS_DIR}/wazuh-admin.txt" ]]; then
    ADMIN_PASS="$(cat "${SECRETS_DIR}/wazuh-admin.txt")"
  fi

  jq -n \
    --arg ip "${IP}" \
    --arg pass "${ADMIN_PASS}" \
    '{
      component: "wazuh",
      status: "deployed",
      url: ("https://" + $ip),
      api_url: ("https://" + $ip + ":55000"),
      agent_endpoint: ($ip + ":1515"),
      credentials: { user: "admin", password: $pass },
      services: ["wazuh-manager","wazuh-indexer","wazuh-dashboard"]
    }' > "${STATE_FILE}"
  exit 0
fi

# Fresh install

# Wazuh-install hardware check: required on minimal preset (2GB/1c), not needed
# on standard (4GB/2c) or production (8GB/4c) which already meet the upstream
# 4GB/2c floor.
WAZUH_INSTALL_FLAGS=""
if [[ "${LL_PRESET:-standard}" == "minimal" ]]; then
  WAZUH_INSTALL_FLAGS="-i"
  log "preset=minimal: passing -i to wazuh-install.sh to skip hardware check"
fi

log "Updating apt"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl wget gnupg jq

download_wazuh_installer
mkdir -p "${WAZUH_INSTALL_WORKDIR}"
cd "${WAZUH_INSTALL_WORKDIR}"
# Always write our own config.yml; the upstream URL serves a template with
# placeholder IPs that cause wazuh-install.sh --generate-config-files to fail.
cat > config.yml <<'EOF'
nodes:
  indexer:
    - name: node-1
      ip: "127.0.0.1"
  server:
    - name: wazuh-1
      ip: "127.0.0.1"
  dashboard:
    - name: dashboard
      ip: "127.0.0.1"
EOF

log "Running wazuh-install.sh (this may take 10-20 minutes)"
# shellcheck disable=SC2086
bash "${WAZUH_INSTALL_SCRIPT}" ${WAZUH_INSTALL_FLAGS} --generate-config-files
# shellcheck disable=SC2086
bash "${WAZUH_INSTALL_SCRIPT}" ${WAZUH_INSTALL_FLAGS} --wazuh-indexer node-1
# shellcheck disable=SC2086
bash "${WAZUH_INSTALL_SCRIPT}" ${WAZUH_INSTALL_FLAGS} --start-cluster
# shellcheck disable=SC2086
bash "${WAZUH_INSTALL_SCRIPT}" ${WAZUH_INSTALL_FLAGS} --wazuh-server wazuh-1
# shellcheck disable=SC2086
bash "${WAZUH_INSTALL_SCRIPT}" ${WAZUH_INSTALL_FLAGS} --wazuh-dashboard dashboard

# Extract the generated admin password from wazuh-passwords.txt
ADMIN_PASS=""
if [[ -f "${WAZUH_INSTALL_WORKDIR}/wazuh-install-files.tar" ]]; then
  WAZUH_PASSWORD_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/wazuh-passwords.XXXXXXXXXX")"
  tar -xf "${WAZUH_INSTALL_WORKDIR}/wazuh-install-files.tar" -C "${WAZUH_PASSWORD_TMPDIR}"
  if [[ -f "${WAZUH_PASSWORD_TMPDIR}/wazuh-install-files/wazuh-passwords.txt" ]]; then
    ADMIN_PASS="$(grep -A1 "username: 'admin'" "${WAZUH_PASSWORD_TMPDIR}/wazuh-install-files/wazuh-passwords.txt" | grep password | awk -F\' '{print $2}')"
  fi
fi
ADMIN_PASS="${ADMIN_PASS:-admin}"

# Store the password
printf '%s' "${ADMIN_PASS}" > "${SECRETS_DIR}/wazuh-admin.txt"
chmod 600 "${SECRETS_DIR}/wazuh-admin.txt"

# Verify services
for svc in wazuh-manager wazuh-indexer wazuh-dashboard; do
  if ! systemctl is-active --quiet "${svc}"; then
    write_failed "${svc} did not start"
  fi
done

IP="$(hostname -I | awk '{print $1}')"

jq -n \
  --arg ip "${IP}" \
  --arg pass "${ADMIN_PASS}" \
  '{
    component: "wazuh",
    status: "deployed",
    url: ("https://" + $ip),
    api_url: ("https://" + $ip + ":55000"),
    agent_endpoint: ($ip + ":1515"),
    credentials: { user: "admin", password: $pass },
    services: ["wazuh-manager","wazuh-indexer","wazuh-dashboard"]
  }' > "${STATE_FILE}"

log "Wazuh deployment complete: https://${IP}"
trap - ERR
