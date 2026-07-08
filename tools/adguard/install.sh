#!/usr/bin/env bash
# tools/adguard/install.sh - runs INSIDE the freshly created LXC.
#
# Self-contained by contract: deploy-one.sh pushes only this file and
# verify.sh into the container, so this script defines its own small helpers
# rather than sourcing the repo libs. It is idempotent and does the FIRST-RUN
# CONFIG (admin user, DNS, web, upstream) so the tool is usable when it exits,
# not left sitting on the interactive :3000 setup wizard.
set -euo pipefail

: "${LL_STATE_DIR:=/var/lib/lidless}"
: "${LL_SECRETS_DIR:=${LL_STATE_DIR}/secrets}"
: "${LL_TOOL:=adguard}"

VER="v0.107.52"                         # pinned; keep in sync with manifest.jsonc
INSTALL_DIR="/opt/AdGuardHome"
BIN="${INSTALL_DIR}/AdGuardHome"
CFG="${INSTALL_DIR}/AdGuardHome.yaml"

# --- minimal self-contained helpers (mirror lib/*.sh, no dependency on them) ---
state_file() { printf '%s/state/%s.json\n' "${LL_STATE_DIR}" "${LL_TOOL}"; }
state_set() {
  local key="$1" value="$2" f jqv tmp
  f="$(state_file)"; mkdir -p "$(dirname "${f}")"; chmod 700 "$(dirname "${f}")" 2>/dev/null || true
  [[ -f "${f}" ]] || { echo '{}' > "${f}"; chmod 600 "${f}"; }
  if printf '%s' "${value}" | jq -e . >/dev/null 2>&1; then jqv="${value}"; else jqv="$(printf '%s' "${value}" | jq -R '.')"; fi
  tmp="$(mktemp)"; jq --argjson v "${jqv}" "setpath(\"${key}\"|split(\".\"); \$v)" "${f}" > "${tmp}"; mv "${tmp}" "${f}"; chmod 600 "${f}"
}
store_secret() {
  local name="$1" value="$2"
  ( umask 0077; mkdir -p "${LL_SECRETS_DIR}"; chmod 700 "${LL_SECRETS_DIR}" 2>/dev/null || true
    printf '%s' "${value}" > "${LL_SECRETS_DIR}/${name}.txt"; chmod 600 "${LL_SECRETS_DIR}/${name}.txt" )
}
gen_password() { LC_ALL=C tr -dc 'A-Za-z0-9_+=.-' </dev/urandom 2>/dev/null | head -c "${1:-24}"; }

trap 'state_set status failed' ERR

export DEBIAN_FRONTEND=noninteractive

echo "[adguard] installing dependencies"
apt-get update -qq
# jq: state json. dnsutils: dig, used by verify.sh. apache2-utils: htpasswd bcrypt.
apt-get install -y -qq jq curl ca-certificates tar dnsutils apache2-utils >/dev/null

# 1. Idempotent binary install, pinned version.
if [[ ! -x "${BIN}" ]]; then
  echo "[adguard] downloading AdGuard Home ${VER}"
  arch="$(dpkg --print-architecture)"
  case "${arch}" in
    amd64) aghpkg="AdGuardHome_linux_amd64.tar.gz" ;;
    arm64) aghpkg="AdGuardHome_linux_arm64.tar.gz" ;;
    *) echo "[adguard] unsupported arch: ${arch}" >&2; exit 1 ;;
  esac
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/AdguardTeam/AdGuardHome/releases/download/${VER}/${aghpkg}" -o "${tmp}/agh.tar.gz"
  tar -xzf "${tmp}/agh.tar.gz" -C /opt   # extracts to /opt/AdGuardHome/
  rm -rf "${tmp}"
fi

# 2. First-run config. Written directly so the interactive :3000 wizard is
#    never needed. Regenerate the admin password only if we have not already
#    stored one (idempotent re-runs keep the same creds).
if [[ -f "${LL_SECRETS_DIR}/${LL_TOOL}-admin.txt" ]]; then
  pw="$(cat "${LL_SECRETS_DIR}/${LL_TOOL}-admin.txt")"
else
  pw="$(gen_password 20)"
  store_secret "${LL_TOOL}-admin" "${pw}"   # persisted 0600 BEFORE first use
fi
# bcrypt hash via htpasswd; empty username field, strip the "user:" separator.
hash="$(htpasswd -bnBC 10 "" "${pw}" | tr -d ':\n')"

echo "[adguard] writing ${CFG}"
cat > "${CFG}" <<YAML
http:
  address: 0.0.0.0:80
users:
  - name: admin
    password: "${hash}"
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  upstream_dns:
    - https://dns.quad9.net/dns-query
  bootstrap_dns:
    - 9.9.9.9
filtering:
  protection_enabled: true
  filtering_enabled: true
schema_version: 27
YAML
chmod 600 "${CFG}"

# 3. Service up (idempotent; -s install is a no-op if already a service).
echo "[adguard] installing + starting service"
if ! systemctl list-unit-files 2>/dev/null | grep -q '^AdGuardHome'; then
  "${BIN}" -s install >/dev/null 2>&1 || true
fi
systemctl enable --now AdGuardHome >/dev/null 2>&1 || systemctl restart AdGuardHome

# 4. State - status "deployed" only after config succeeded.
ip="$(hostname -I | awk '{print $1}')"
state_set adguard_url "http://${ip}/"
state_set adguard_admin_user "admin"
state_set status "deployed"
echo "[adguard] done: http://${ip}/  (user: admin)"
