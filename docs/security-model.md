# Security model

`lidless-proxmox` runs as root on a Proxmox host and creates LXC containers. It is built for homelabs and internal labs, not for hostile multi-tenant networks.

## Threat model

- **Trusted host.** Anyone who can run the installer already owns the box.
- **Trusted bridge.** Containers talk over the Proxmox bridge (default `vmbr0`), assumed to be hardware you control.
- **Root-only state.** Everything sensitive lives under `/var/lib/lidless/` with root-only permissions.

## What the installer does

- **Generated credentials, never defaults.** Each tool's `install.sh` generates admin passwords and writes them to `/var/lib/lidless/secrets/<tool>-*.txt` (dir `0700`, files `0600`, written under `umask 0077`) before first use.
- **Redacted result JSON by default.** `/root/lidless-<tool>.json` replaces passwords/tokens with `REDACTED` and lists secret file paths. `LL_INCLUDE_SECRETS_JSON=1` opts into raw values for automation.
- **Pinned + checksum-verified install path.** See [pinning.md](pinning.md). The engine is not curled live from a branch.
- **Verify-gated.** A tool is only marked deployed after its `verify.sh` proves the real service answers.

## What is deliberately accepted

- **Plain HTTP on the internal bridge** for tools that serve it (AdGuard web UI on 80). Add TLS termination in front if you expose these beyond the host.
- **Secrets in plaintext on the host.** `/var/lib/lidless/secrets/` is the recovery story. Know it is there before imaging or backing up the host.

## Reporting

See [SECURITY.md](../SECURITY.md) for how to report a vulnerability.
