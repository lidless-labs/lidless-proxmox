<!-- One tool or one fix per PR. -->

## What this changes

## How I verified it
<!-- For a new tool: the Proxmox host you ran it on, that verify.sh passed, and that you tore the container down. -->

- [ ] `shellcheck --severity=warning bootstrap.sh lib/*.sh tools/*.sh tools/*/*.sh` clean
- [ ] `./tests/unit/run.sh` green
- [ ] For a new/changed tool: `install.sh` does first-run config, `verify.sh` proves the real service answers
- [ ] Everything downloaded at install time is pinned
- [ ] No private IPs, personal hostnames, or home paths (RFC 5737 IPs in examples)
