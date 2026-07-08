#!/usr/bin/env bash
# Convenience runner for all bats unit tests.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -t 1 ]]; then
  FORMATTER="${BATS_FORMATTER:-pretty}"
else
  FORMATTER="${BATS_FORMATTER:-tap}"
fi

exec "${REPO_ROOT}/tests/vendor/bats-core/bin/bats" \
  --print-output-on-failure \
  --formatter "${FORMATTER}" \
  "${SCRIPT_DIR}"/*.bats
