#!/usr/bin/env bash
# tools/sync-engine.sh - vendor the Proxmox engine libs from soc-stack.
#
# The engine primitives (LXC lifecycle, VMID/IP allocation, secrets, state,
# preflight, logging) originate in the soc-stack repo, where they are
# bats-tested against mocked Proxmox binaries. This library reuses them, so
# we vendor a rebranded copy rather than depending on soc-stack at runtime
# (a curl|bash install must carry the libs inside its pinned tree, not fetch
# a second artifact).
#
# This script is dev-only. It is NEVER run on a user's Proxmox host.
#
# Usage:
#   tools/sync-engine.sh <path-to-soc-stack-checkout>
#
# It rebrands SOC_ -> LL_ (a deterministic, mechanical rename) for the six
# domain-neutral libs. lib/json-out.sh is hand-maintained here (it needed
# structural de-SOC-ing: dropping the MCP emitter and the hardcoded component
# secret-file map), so it is intentionally NOT overwritten by this script.
set -euo pipefail

SRC="${1:?usage: sync-engine.sh <path-to-soc-stack>}"
SRC_LIB="${SRC}/scripts/lib"
DEST_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib"

[[ -d "${SRC_LIB}" ]] || { echo "no lib dir at ${SRC_LIB}" >&2; exit 1; }

# Domain-neutral libs that port verbatim (with the SOC_ -> LL_ rename).
# json-out.sh is deliberately excluded: it is hand-maintained in this repo.
PORTABLE=(logging secrets idempotency network preflight lxc)

rebrand() {
  # Deterministic rename. Mechanical enough to re-run on every upstream bump.
  sed \
    -e 's/SOC_/LL_/g' \
    -e 's/_soc_log/_ll_log/g' \
    -e 's,soc-stack,lidless,g' \
    -e 's,/var/log/lidless-install.log,/var/log/lidless-install.log,g'
}

for name in "${PORTABLE[@]}"; do
  src="${SRC_LIB}/${name}.sh"
  [[ -f "${src}" ]] || { echo "missing ${src}" >&2; exit 1; }
  rebrand < "${src}" > "${DEST_LIB}/${name}.sh"
  echo "synced lib/${name}.sh"
done

ref="$(git -C "${SRC}" rev-parse HEAD 2>/dev/null || echo unknown)"
{
  echo "source: soc-stack@${ref}"
  echo "libs: ${PORTABLE[*]} (json-out.sh hand-maintained)"
  echo "rebrand: SOC_ -> LL_"
} > "${DEST_LIB}/ENGINE_VERSION"
echo "wrote lib/ENGINE_VERSION (soc-stack@${ref})"
