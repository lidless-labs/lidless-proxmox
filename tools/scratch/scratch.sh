#!/usr/bin/env bash
# tools/scratch/scratch.sh - spin a throwaway Debian LXC for smoke-testing.
#
# Runs on the Proxmox host. Allocates in the 9000-9099 reaper band with a
# ll-smoke- hostname prefix, so both lidless-smoke-reaper.sh and the Proxmox
# MCP's proxmox_cleanup_smoke_resources (name_prefix: ll-smoke-) can GC it.
#
# Usage:
#   bash tools/scratch/scratch.sh [--label NAME] [--preset P] [--run 'CMD'] [--reap]
#
#   --label NAME   hostname becomes ll-smoke-NAME (default: ll-smoke-scratch)
#   --preset P     manifest preset (default: minimal)
#   --run 'CMD'    run CMD inside the CT and print its output
#   --reap         destroy the CT when done (default: keep it for poking;
#                  the cron reaper GCs the band later regardless)
set -euo pipefail

LL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"
LL_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

: "${LL_BRIDGE:=vmbr0}"
: "${LL_STORAGE:=local-lvm}"
: "${LL_TEMPLATE_STORAGE:=local}"
: "${LL_STATE_DIR:=/var/lib/lidless}"
: "${LL_SECRETS_DIR:=${LL_STATE_DIR}/secrets}"
: "${LL_LOG_FILE:=/var/log/lidless-install.log}"
export LL_STATE_DIR LL_SECRETS_DIR LL_LOG_FILE

# shellcheck source=lib/logging.sh
source "${LL_LIB_DIR}/logging.sh"
# shellcheck source=lib/secrets.sh
source "${LL_LIB_DIR}/secrets.sh"
# shellcheck source=lib/network.sh
source "${LL_LIB_DIR}/network.sh"
# shellcheck source=lib/preflight.sh
source "${LL_LIB_DIR}/preflight.sh"
# shellcheck source=lib/lxc.sh
source "${LL_LIB_DIR}/lxc.sh"

scratch_manifest() {
  sed 's://.*$::g' "${LL_TOOLS_DIR}/scratch/manifest.jsonc" | jq -r "$1"
}

# scratch_hostname <label> - the ll-smoke- prefixed hostname for a label.
scratch_hostname() {
  local label="${1:-scratch}"
  printf 'll-smoke-%s' "${label}"
}

scratch_resolve_template() {
  local pattern="$1" volid
  volid="$(pveam list "${LL_TEMPLATE_STORAGE}" 2>/dev/null | awk -v p="${pattern}" '$1 ~ p {print $1; exit}')"
  if [[ -z "${volid}" ]]; then
    pveam update >/dev/null 2>&1 || true
    local avail
    avail="$(pveam available --section system 2>/dev/null | awk -v p="${pattern}" '$2 ~ p {print $2; exit}')"
    [[ -n "${avail}" ]] && pveam download "${LL_TEMPLATE_STORAGE}" "${avail}" >/dev/null 2>&1 || true
    volid="$(pveam list "${LL_TEMPLATE_STORAGE}" 2>/dev/null | awk -v p="${pattern}" '$1 ~ p {print $1; exit}')"
  fi
  printf '%s' "${volid}"
}

main() {
  local label="scratch" preset="minimal" run_cmd="" reap=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --label)  label="$2"; shift 2 ;;
      --preset) preset="$2"; shift 2 ;;
      --run)    run_cmd="$2"; shift 2 ;;
      --reap)   reap=1; shift ;;
      *) msg_error "unknown flag: $1"; return 2 ;;
    esac
  done

  check_root            || return 1
  check_proxmox_version || return 1
  check_bridge "${LL_BRIDGE}" || return 1

  local ram cores disk pattern
  ram="$(scratch_manifest ".presets.\"${preset}\".ram_mb")"
  cores="$(scratch_manifest ".presets.\"${preset}\".cores")"
  disk="$(scratch_manifest ".presets.\"${preset}\".disk_gb")"
  pattern="$(scratch_manifest '.template_pattern')"
  [[ -n "${ram}" && "${ram}" != "null" ]] || { msg_error "preset '${preset}' not defined"; return 2; }

  local vmid hostname template
  vmid="$(next_vmid 9000)"
  hostname="$(scratch_hostname "${label}")"
  template="$(scratch_resolve_template "${pattern}")"
  [[ -n "${template}" ]] || { msg_error "could not resolve template '${pattern}'"; return 1; }

  local rootpw
  rootpw="$(gen_password 24)"

  msg_info "creating scratch LXC ${vmid} (${hostname})"
  lxc_create "${vmid}" "${hostname}" "${template}" \
    --memory "${ram}" --cores "${cores}" --rootfs "${LL_STORAGE}:${disk}" \
    --net0 "name=eth0,bridge=${LL_BRIDGE},ip=dhcp" \
    --unprivileged 1 --onboot 0 --start 0 --password "${rootpw}"
  lxc_start "${vmid}"
  lxc_wait_network "${vmid}"

  local ip
  ip="$(lxc_ip "${vmid}")"
  msg_ok "scratch LXC ${vmid} up at ${ip}"

  if [[ -n "${run_cmd}" ]]; then
    msg_info "running command inside ${vmid}"
    pct exec "${vmid}" -- bash -lc "${run_cmd}" || msg_warn "command exited non-zero"
  fi

  if [[ "${reap}" == "1" ]]; then
    msg_info "reaping scratch LXC ${vmid}"
    lxc_destroy "${vmid}"
    msg_ok "reaped ${vmid}"
  else
    msg_ok "scratch LXC ${vmid} (${ip}) left running. Reap: pct stop ${vmid} && pct destroy ${vmid}"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -z "${LL_TEST_MODE:-}" ]]; then
  main "$@"
fi
