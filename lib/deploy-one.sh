#!/usr/bin/env bash
# lib/deploy-one.sh - deploy a single tool into its own LXC on a Proxmox host.
#
# Standalone port of soc-stack's deploy_one orchestrator. Reads a tool's
# tools/<tool>/manifest.jsonc, creates an LXC sized to the chosen preset,
# runs the tool's install.sh inside it, pulls state/secrets back to the host,
# then gates on the tool's own verify.sh. "Installed" never reports success
# without verify.sh passing.
#
# Usage:  bash lib/deploy-one.sh <tool>
#
# Configuration via environment (all optional except the tool arg):
#   LL_PRESET         minimal|standard|... (default: standard)
#   LL_BRIDGE         Proxmox bridge (default: vmbr0)
#   LL_STORAGE        rootfs storage pool (default: local-lvm)
#   LL_IP_MODE        dhcp (default; static allocation is a later phase)
#   LL_STATE_DIR      state root (default: /var/lib/lidless)
#   LL_VMID_START     first VMID to try (default: 200, or 9000 when LL_SMOKE=1)
#   LL_SMOKE          1 => allocate in the 9000-9099 reaper band, hostname
#                     prefix ll-smoke- (matches proxmox_cleanup_smoke_resources)
#   LL_HOSTNAME       override the container hostname
#   LL_JSON_OUT       result JSON path (default: /root/lidless-<tool>.json)
#   LL_FORCE          1 => redeploy even if state says deployed
#   LL_DRY_RUN        1 => plan only, create nothing
#   LL_INCLUDE_SECRETS_JSON  1 => raw creds in result JSON (default: redacted)
set -euo pipefail

LL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LL_REPO_ROOT="$(cd "${LL_LIB_DIR}/.." && pwd)"
LL_TOOLS_DIR="${LL_REPO_ROOT}/tools"

: "${LL_PRESET:=standard}"
: "${LL_BRIDGE:=vmbr0}"
: "${LL_STORAGE:=local-lvm}"
: "${LL_TEMPLATE_STORAGE:=local}"
: "${LL_IP_MODE:=dhcp}"
: "${LL_STATE_DIR:=/var/lib/lidless}"
: "${LL_SECRETS_DIR:=${LL_STATE_DIR}/secrets}"
: "${LL_LOG_FILE:=/var/log/lidless-install.log}"
: "${LL_SMOKE:=0}"
: "${LL_FORCE:=0}"
: "${LL_DRY_RUN:=0}"
: "${LL_INCLUDE_SECRETS_JSON:=0}"

export LL_STATE_DIR LL_SECRETS_DIR LL_LOG_FILE

# shellcheck source=lib/logging.sh
source "${LL_LIB_DIR}/logging.sh"
# shellcheck source=lib/secrets.sh
source "${LL_LIB_DIR}/secrets.sh"
# shellcheck source=lib/json-out.sh
source "${LL_LIB_DIR}/json-out.sh"
# shellcheck source=lib/idempotency.sh
source "${LL_LIB_DIR}/idempotency.sh"
# shellcheck source=lib/network.sh
source "${LL_LIB_DIR}/network.sh"
# shellcheck source=lib/preflight.sh
source "${LL_LIB_DIR}/preflight.sh"
# shellcheck source=lib/lxc.sh
source "${LL_LIB_DIR}/lxc.sh"

# read_manifest <tool> <jq-filter>
# Reads tools/<tool>/manifest.jsonc, strips // comments, applies the filter.
read_manifest() {
  local tool="$1"
  local filter="$2"
  local m="${LL_TOOLS_DIR}/${tool}/manifest.jsonc"
  [[ -f "${m}" ]] || { msg_error "no manifest for tool: ${tool}"; return 1; }
  sed 's://.*$::g' "${m}" | jq -r "${filter}"
}

# resolve_template <pattern>
# Prints an installed template volid matching <pattern>, downloading it first
# if absent. Empty output on failure.
resolve_template() {
  local pattern="$1"
  local volid
  volid="$(pveam list "${LL_TEMPLATE_STORAGE}" 2>/dev/null | awk -v p="${pattern}" '$1 ~ p {print $1; exit}')"
  if [[ -z "${volid}" ]]; then
    msg_info "template ${pattern} not present, fetching"
    pveam update >/dev/null 2>&1 || true
    local avail
    avail="$(pveam available --section system 2>/dev/null | awk -v p="${pattern}" '$2 ~ p {print $2; exit}')"
    if [[ -n "${avail}" ]]; then
      pveam download "${LL_TEMPLATE_STORAGE}" "${avail}" >/dev/null 2>&1 || true
      volid="$(pveam list "${LL_TEMPLATE_STORAGE}" 2>/dev/null | awk -v p="${pattern}" '$1 ~ p {print $1; exit}')"
    fi
  fi
  printf '%s' "${volid}"
}

deploy_one() {
  local tool="$1"
  [[ -d "${LL_TOOLS_DIR}/${tool}" ]] || { msg_error "unknown tool: ${tool}"; return 2; }

  local display
  display="$(read_manifest "${tool}" '.display_name // .name')" || return 2

  msg_info "==== ${display} (${tool}) ===="

  if is_completed "${tool}" && [[ "${LL_FORCE}" != "1" ]]; then
    msg_ok "${tool} already deployed (state status=deployed); skipping. Use LL_FORCE=1 to redeploy."
    return 0
  fi

  # Preset resources
  local ram cores disk template_pattern unpriv
  ram="$(read_manifest "${tool}" ".presets.\"${LL_PRESET}\".ram_mb")"
  cores="$(read_manifest "${tool}" ".presets.\"${LL_PRESET}\".cores")"
  disk="$(read_manifest "${tool}" ".presets.\"${LL_PRESET}\".disk_gb")"
  template_pattern="$(read_manifest "${tool}" '.template_pattern // "debian-12-standard"')"
  unpriv="$(read_manifest "${tool}" 'if .unprivileged == false then 0 else 1 end')"
  if [[ -z "${ram}" || "${ram}" == "null" ]]; then
    msg_error "preset '${LL_PRESET}' not defined in ${tool} manifest"
    return 2
  fi

  # Features (e.g. nesting=1), one --features arg joined by commas
  local features
  features="$(read_manifest "${tool}" '(.features // []) | join(",")')"

  # VMID + hostname
  local vmid_start hostname
  if [[ "${LL_SMOKE}" == "1" ]]; then
    vmid_start="${LL_VMID_START:-9000}"
    hostname="${LL_HOSTNAME:-ll-smoke-${tool}}"
  else
    vmid_start="${LL_VMID_START:-200}"
    hostname="${LL_HOSTNAME:-ll-${tool}}"
  fi
  local vmid
  vmid="$(next_vmid "${vmid_start}")"

  # Network (dhcp for now; static allocation is a later phase)
  local net_config="name=eth0,bridge=${LL_BRIDGE},ip=dhcp"

  # Template
  local template
  template="$(resolve_template "${template_pattern}")"
  if [[ -z "${template}" ]]; then
    msg_error "could not resolve template matching '${template_pattern}'"
    return 1
  fi

  # Assemble pct args
  local pct_args=(
    --memory "${ram}"
    --cores "${cores}"
    --rootfs "${LL_STORAGE}:${disk}"
    --net0 "${net_config}"
    --unprivileged "${unpriv}"
    --onboot 1
    --start 0
  )
  [[ -n "${features}" ]] && pct_args+=(--features "${features}")

  if [[ "${LL_DRY_RUN}" == "1" ]]; then
    msg_info "[dry-run] would: pct create ${vmid} ${template} --hostname ${hostname} ${pct_args[*]} --password ***"
    msg_info "[dry-run] would: run ${tool}/install.sh then ${tool}/verify.sh inside ${vmid}"
    return 0
  fi

  # Root password generated only when a container will actually be created.
  local rootpw
  rootpw="$(gen_password 24)"
  store_secret "${tool}-lxc-root" "${rootpw}"

  msg_info "creating LXC ${vmid} (${hostname}) for ${tool}"
  lxc_create "${vmid}" "${hostname}" "${template}" "${pct_args[@]}" --password "${rootpw}"
  lxc_start "${vmid}"
  msg_info "waiting for LXC ${vmid} network"
  lxc_wait_network "${vmid}"

  # State dirs inside the LXC; orchestrator pulls them back after install.
  pct exec "${vmid}" -- mkdir -p "${LL_STATE_DIR}/state" "${LL_SECRETS_DIR}"

  # Push + run install.sh
  msg_info "running ${tool}/install.sh inside LXC ${vmid}"
  local remote_install="/tmp/${tool}-install.sh"
  lxc_push_script "${vmid}" "${LL_TOOLS_DIR}/${tool}/install.sh" "${remote_install}"
  if ! pct exec "${vmid}" -- env \
      LL_STATE_DIR="${LL_STATE_DIR}" \
      LL_SECRETS_DIR="${LL_SECRETS_DIR}" \
      LL_TOOL="${tool}" \
      LL_PRESET="${LL_PRESET}" \
      LL_NON_INTERACTIVE=1 \
      bash "${remote_install}"; then
    msg_error "${tool} install.sh failed"
    state_set "${tool}" status "failed"
    return 3
  fi

  # Pull state + secrets back to the host.
  secure_dir "${LL_STATE_DIR}/state"
  secure_dir "${LL_SECRETS_DIR}"
  local in_lxc_state="${LL_STATE_DIR}/state/${tool}.json"
  if pct exec "${vmid}" -- test -f "${in_lxc_state}"; then
    pct pull "${vmid}" "${in_lxc_state}" "${LL_STATE_DIR}/state/${tool}.json"
  fi
  while IFS= read -r remote; do
    [[ -n "${remote}" ]] || continue
    pct pull "${vmid}" "${remote}" "${LL_SECRETS_DIR}/$(basename "${remote}")" 2>/dev/null || true
  done < <(pct exec "${vmid}" -- bash -c "ls \"${LL_SECRETS_DIR}\"/* 2>/dev/null" || true)

  state_set "${tool}" "lxc.vmid" "${vmid}"
  state_set "${tool}" "lxc.hostname" "${hostname}"
  state_set "${tool}" "preset" "${LL_PRESET}"

  # Verify - the same verify.sh the CI gate runs. 3 retries, 30s apart.
  msg_info "verifying ${tool}"
  local remote_verify="/tmp/${tool}-verify.sh"
  lxc_push_script "${vmid}" "${LL_TOOLS_DIR}/${tool}/verify.sh" "${remote_verify}"
  local retries=3 i=0
  while (( i < retries )); do
    if pct exec "${vmid}" -- bash "${remote_verify}"; then
      break
    fi
    i=$((i + 1))
    msg_warn "verify attempt ${i}/${retries} failed for ${tool}, retrying in 30s"
    (( i < retries )) && sleep 30
  done
  if (( i >= retries )); then
    msg_error "${tool} verify.sh failed after ${retries} attempts"
    state_set "${tool}" status "failed"
    return 3
  fi

  local ip
  ip="$(lxc_ip "${vmid}")"
  [[ -n "${ip}" ]] && state_set "${tool}" "lxc.ip" "${ip}"
  mark_completed "${tool}"

  local json_out="${LL_JSON_OUT:-/root/lidless-${tool}.json}"
  emit_tool_json "${tool}" "${json_out}" "${LL_INCLUDE_SECRETS_JSON}"

  msg_ok "${tool} deployed on LXC ${vmid}${ip:+ (${ip})}"
  msg_ok "result JSON: ${json_out}  |  secrets: ${LL_SECRETS_DIR}/${tool}-*.txt"
  return 0
}

main() {
  local tool="${1:?usage: deploy-one.sh <tool>}"

  check_root            || return 1
  check_proxmox_version || return 1
  bootstrap_deps        || return 1
  check_bridge "${LL_BRIDGE}" || return 1

  deploy_one "${tool}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -z "${LL_TEST_MODE:-}" ]]; then
  main "$@"
fi
