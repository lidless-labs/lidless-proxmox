# CLAUDE.md

Claude Code-specific bridge. Cross-harness behavior lives in [AGENTS.md](AGENTS.md); follow it.

## Fast rules

- Lint + test before saying done: `shellcheck --severity=warning bootstrap.sh lib/*.sh tools/*.sh tools/*/*.sh` and `./tests/unit/run.sh`.
- Never weaken the `verify.sh` gate. In-container `install.sh`/`verify.sh` stay self-contained (no sourcing repo libs).
- Vendored `lib/*.sh` (except `json-out.sh`/`deploy-one.sh`) come from soc-stack via `tools/sync-engine.sh`. Re-sync rather than hand-editing behavior.
- RFC 5737 IPs only in docs/examples. No personal hostnames or home paths. Do not bypass the pre-push content-guard hook.
- Conventional commits, no AI-attribution trailers, no em dashes. Feature branch + PR, never push to `main`.
