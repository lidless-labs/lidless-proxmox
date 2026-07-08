# Contributing

Thanks for the interest. This library stays small on purpose: tools worth running, each done completely.

## The bar for a new tool

A tool is accepted when it does the whole job, not part of it. Concretely:

- Three files under `tools/<name>/`: `manifest.jsonc`, `install.sh`, `verify.sh` (see [docs/adding-a-tool.md](docs/adding-a-tool.md)).
- `install.sh` does the first-run config, not just package install. If the tool has a web frontend and a backend, both come up configured.
- `verify.sh` proves the real service answers (query the port, hit the API), and it passes on a clean host.
- Everything downloaded at install time is pinned to a version/tag/SHA.
- `shellcheck --severity=warning` clean; `./tests/unit/run.sh` green.

A script that installs a package and starts a service but leaves the tool unconfigured will not be merged. That gap is the reason this repo exists.

## Style

- `#!/usr/bin/env bash`, `set -euo pipefail`, quote your variables.
- No hardcoded credentials, ever. Generate and persist under `${LL_SECRETS_DIR}`.
- RFC 5737 IPs (`192.0.2.x`, `198.51.100.x`) in examples. No private IPs or personal hostnames.
- Conventional commits. No AI-attribution trailers. No em dashes in docs.

## PRs

Feature branch, one tool or one fix per PR, describe how you verified it on a real Proxmox host.
