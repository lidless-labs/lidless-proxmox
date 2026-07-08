#!/usr/bin/env bash
# lib/json-out.sh - per-tool state files + result JSON emitter.
# Hand-maintained fork of soc-stack's json-out.sh: de-SOC'd to a single-tool
# model (no MCP emitter, no hardcoded per-component secret-file map).
# Requires: jq, lib/logging.sh
#
# State lives at ${LL_STATE_DIR}/state/<tool>.json (0600), secrets at
# ${LL_STATE_DIR}/secrets/<name>.txt (0600). Both are written inside the LXC
# by a tool's install.sh, then pulled back to the host by deploy-one.sh.

: "${LL_STATE_DIR:=/var/lib/lidless}"
: "${LL_SECRETS_DIR:=${LL_STATE_DIR}/secrets}"

secure_dir() {
  mkdir -p "$1"
  chmod 700 "$1" 2>/dev/null || true
}

secure_parent_dir() {
  local dir
  dir="$(dirname "$1")"
  [[ "${dir}" == "." ]] && return 0
  secure_dir "${dir}"
}

# state_file <tool> - print path to that tool's state file
state_file() {
  printf '%s/state/%s.json\n' "${LL_STATE_DIR}" "$1"
}

# state_set <tool> <key> <value>
# Key may use dot notation for nesting (e.g., "lxc.vmid").
# Value is interpreted as JSON if it parses, else as a string.
state_set() {
  local tool="$1"
  local key="$2"
  local value="$3"
  local f
  f="$(state_file "${tool}")"

  secure_dir "$(dirname "${f}")"
  [[ -f "${f}" ]] || { echo '{}' > "${f}"; chmod 600 "${f}" 2>/dev/null || true; }

  local jq_value
  if printf '%s' "${value}" | jq -e . >/dev/null 2>&1; then
    jq_value="${value}"
  else
    jq_value="$(printf '%s' "${value}" | jq -R '.')"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --argjson v "${jq_value}" "setpath(\"${key}\" | split(\".\"); \$v)" "${f}" > "${tmp}"
  mv "${tmp}" "${f}"
  chmod 600 "${f}" 2>/dev/null || true
}

# state_get <tool> <key> - print value at key, or empty if missing.
state_get() {
  local tool="$1"
  local key="$2"
  local f
  f="$(state_file "${tool}")"
  [[ -f "${f}" ]] || return 0
  jq -r "getpath(\"${key}\" | split(\".\")) // empty" "${f}"
}

# tool_secret_files_json <tool>
# Lists persisted secret files for a tool by the generic <tool>-*.txt pattern.
# No per-tool special-casing: every tool names its secrets <tool>-<slot>.txt.
tool_secret_files_json() {
  local tool="$1"
  local files=()
  local path
  while IFS= read -r path; do
    [[ -n "${path}" ]] && files+=("${path}")
  done < <(compgen -G "${LL_SECRETS_DIR}/${tool}-*.txt" || true)

  if [[ ${#files[@]} -eq 0 ]]; then
    printf '[]'
  else
    printf '%s\n' "${files[@]}" | jq -R . | jq -s .
  fi
}

redact_json() {
  jq '
    def redact:
      if type == "object" then
        with_entries(
          if (.key | test("(password|passphrase|api_?key|token|secret|authorization)"; "i")) then
            .value = "REDACTED"
          else
            .value |= redact
          end
        )
      elif type == "array" then
        map(redact)
      else
        .
      end;
    redact
  '
}

# emit_tool_json <tool> <output_path> [include_secrets]
# Reads the tool's state file and writes a redacted-by-default result JSON.
emit_tool_json() {
  local tool="$1"
  local out="$2"
  local include_secrets="${3:-0}"
  local installed_at
  installed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  secure_parent_dir "${out}"
  local sf
  sf="$(state_file "${tool}")"
  local obj='{}'
  [[ -f "${sf}" ]] && obj="$(jq --arg name "${tool}" '{name: $name} + .' "${sf}")"

  if [[ "${include_secrets}" != "1" ]]; then
    local secret_files
    secret_files="$(tool_secret_files_json "${tool}")"
    obj="$(redact_json <<< "${obj}" | jq --argjson files "${secret_files}" '. + {secret_files: $files}')"
  fi

  jq -n \
    --arg installed_at "${installed_at}" \
    --arg version "${LL_VERSION:-dev}" \
    --argjson tool "${obj}" \
    '{
      version: "1.0",
      installed_at: $installed_at,
      lidless_version: $version,
      tool: $tool
    }' > "${out}"
  chmod 600 "${out}" 2>/dev/null || true
}
