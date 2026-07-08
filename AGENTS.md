# AGENTS.md

Cross-harness contract for working in this repo. Claude Code reads `CLAUDE.md`, which defers here.

## What this repo is

Curated, complete, one-command Proxmox LXC installers for tools worth running. Built on a vendored, bats-tested engine (`lib/*.sh`, synced from soc-stack). The differentiator over community-scripts is enforced completeness: every tool has a `verify.sh` that gates "deployed", and the install path is pinned and checksum-verified.

## Layout

- `bootstrap.sh` - pinned fetch + sha256 verify + exec shim. The trust anchor. Changes here are security-sensitive.
- `lib/` - the engine. `lib/*.sh` except `json-out.sh` are VENDORED from soc-stack via `tools/sync-engine.sh` (SOC_ -> LL_ rename). Do not hand-edit the vendored files for behavior; change them upstream in soc-stack and re-sync, or move the file out of the synced set. `lib/json-out.sh` and `lib/deploy-one.sh` are hand-maintained here.
- `tools/<name>/` - three files per tool: `manifest.jsonc`, `install.sh`, `verify.sh`. See `docs/adding-a-tool.md`.
- `tests/unit/` - bats with mocked `pct`/`pveam`/etc. in `fixtures/bin/`. Run `./tests/unit/run.sh`.

## Rules

- **Never weaken the verify gate.** A tool is deployed only when `verify.sh` exits 0. Do not add a "skip verify" path.
- **Keep in-container scripts self-contained.** `install.sh`/`verify.sh` run inside the LXC with only their own file pushed; they must not source the repo libs.
- **Pin everything downloaded at install time.** Version/tag/SHA, kept in sync between `install.sh` and the manifest `pinned` block.
- **Lint + test before claiming done.** `shellcheck --severity=warning bootstrap.sh lib/*.sh tools/*.sh tools/*/*.sh` and `./tests/unit/run.sh` must be green.
- **Use RFC 5737 IPs** (`192.0.2.x`, `198.51.100.x`) in all docs and examples. No private IPs, no personal hostnames, no home paths anywhere public. The `hooks/pre-push` content-guard hook enforces this; never bypass with `--no-verify` unless the user explicitly accepts the risk.

## Git

- Conventional commits. No `Co-Authored-By` or AI-attribution trailers. No em dashes in commit messages or public docs.
- Feature branch + PR. Do not push to `main` directly.
- Releases happen on request. A release requires bumping the `VERSION` default in `bootstrap.sh` to match the tag (CI enforces it).
