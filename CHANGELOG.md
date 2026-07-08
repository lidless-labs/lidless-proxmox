# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added
- Repo foundation: vendored + rebranded Proxmox engine (`lib/*.sh`, synced from soc-stack), single-tool orchestrator `lib/deploy-one.sh`.
- Pinned, checksum-verified install path: `bootstrap.sh` + release workflow (tarball + `.sha256`).
- First tool: `adguard` (AdGuard Home) with complete first-run config and a DNS + web `verify.sh` gate.
- Tier-1 CI: shellcheck, bats unit tests with mocked Proxmox binaries (including a `bootstrap-pinning` fail-closed test), and manifest schema validation.
- `scratch` tool: host-side throwaway-LXC spinner in the 9000-9099 smoke band (`ll-smoke-` prefix), plus `tools/lidless-smoke-reaper.sh` cron GC (band-guarded, never touches production VMIDs).
- `wazuh` tool: standalone single-node Wazuh installer ported from soc-stack. Not yet on-host smoke-verified.
