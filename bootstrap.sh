#!/usr/bin/env bash
# bootstrap.sh - pinned, checksum-verified entry point for a lidless-proxmox
# tool install. This is the file a user curls, and it is the trust anchor:
# it is fetched at an immutable git tag, and everything it runs afterward is
# a GitHub Release asset whose sha256 it verifies before executing.
#
# Usage (from a Proxmox host shell):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/lidless-labs/lidless-proxmox/v0.1.0/bootstrap.sh)" _ <tool>
#
# The literal `_` is $0 for the piped shell; the tool name is $1.
#
# Why this shape, versus `source <(curl .../main/misc/build.func)`:
#   - Pinned: the URL names an immutable tag, not a moving branch.
#   - Verified: the release tarball is checked against a published .sha256
#     and never executed on mismatch (fails closed).
#   - No second live fetch: the engine libs travel inside the verified
#     tarball, so nothing else is curled at run time.
set -euo pipefail

TOOL="${1:?usage: bootstrap.sh <tool> (run via the documented curl one-liner)}"

# VERSION is rewritten to the tag at release-cut time. LL_VERSION overrides it
# for testing against a pre-release.
VERSION="${LL_VERSION:-v0.1.0}"
REPO="${LL_REPO:-lidless-labs/lidless-proxmox}"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
NAME="lidless-proxmox-${VERSION}"
TARBALL="${NAME}.tar.gz"

need() { command -v "$1" >/dev/null 2>&1 || { echo "bootstrap: missing required command: $1" >&2; exit 1; }; }
need curl
need sha256sum
need tar

work="$(mktemp -d "${TMPDIR:-/tmp}/lidless.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
cd "${work}"

echo "bootstrap: fetching ${TARBALL} @ ${VERSION}" >&2
curl -fsSLO "${BASE}/${TARBALL}"
curl -fsSLO "${BASE}/${TARBALL}.sha256"

# Fails closed: a mismatched or swapped artifact never reaches exec.
echo "bootstrap: verifying checksum" >&2
if ! sha256sum -c "${TARBALL}.sha256"; then
  echo "bootstrap: CHECKSUM MISMATCH - refusing to run ${TARBALL}" >&2
  exit 1
fi

tar -xzf "${TARBALL}"
entry="${work}/${NAME}/lib/deploy-one.sh"
if [[ ! -f "${entry}" ]]; then
  # Tolerate a tarball whose top dir differs; find the entry point.
  entry="$(find "${work}" -maxdepth 3 -name deploy-one.sh -path '*/lib/*' | head -1)"
fi
[[ -f "${entry}" ]] || { echo "bootstrap: deploy-one.sh not found in tarball" >&2; exit 1; }

echo "bootstrap: verified. deploying ${TOOL}" >&2
exec bash "${entry}" "${TOOL}"
