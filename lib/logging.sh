#!/usr/bin/env bash
# scripts/lib/logging.sh - structured logging for lidless
# Reads: LL_LOG_FILE (path; default /var/log/lidless-install.log)
# Writes: log file + stderr

: "${LL_LOG_FILE:=/var/log/lidless-install.log}"

_ll_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local line
  printf -v line '[%s] %-5s %s' "${ts}" "${level}" "${msg}"

  mkdir -p "$(dirname "${LL_LOG_FILE}")" 2>/dev/null || true
  printf '%s\n' "${line}" >> "${LL_LOG_FILE}" 2>/dev/null || true

  case "${level}" in
    ERROR|WARN) printf '%s\n' "${line}" >&2 ;;
    *)          printf '%s\n' "${line}" >&2 ;;
  esac
}

msg_info()  { _ll_log "INFO"  "$*"; }
msg_ok()    { _ll_log "OK"    "$*"; }
msg_warn()  { _ll_log "WARN"  "$*"; }
msg_error() { _ll_log "ERROR" "$*"; }
