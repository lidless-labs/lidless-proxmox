# Security

## Reporting a vulnerability

Report privately through GitHub Security Advisories on this repo (Security tab, "Report a vulnerability"), or open a minimal issue asking for a private contact if that is unavailable. Do not file public exploit details before a fix ships.

## Scope

`lidless-proxmox` runs as root on a Proxmox host and creates LXCs. Its threat model, hardening, and deliberate trade-offs are documented in [docs/security-model.md](docs/security-model.md). The install trust model (pinning, checksum verification, and its limits) is in [docs/pinning.md](docs/pinning.md).

Notable current limitation, stated plainly: releases are pinned and checksum-verified but **not yet cryptographically signed**. A total repo/release compromise could ship a matching checksum. Signed releases (minisign/cosign) are planned. This file will be updated when signing ships, not before.
