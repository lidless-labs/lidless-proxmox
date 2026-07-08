# Pinning and the install trust model

The install one-liner runs code as root on your Proxmox host. This document is honest about what that code is, how it is pinned, and what the checks do and do not protect against.

## The flow

```
bash -c "$(curl -fsSL .../<TAG>/bootstrap.sh)" _ <tool>
```

1. `curl` fetches `bootstrap.sh` **at an immutable git tag**, not a branch.
2. `bootstrap.sh` downloads the release tarball `lidless-proxmox-<TAG>.tar.gz` and its `.sha256`, both GitHub Release assets.
3. It runs `sha256sum -c`. On mismatch it exits non-zero and never executes anything.
4. On match it extracts the tarball and execs `lib/deploy-one.sh` from the verified tree. The engine libraries travel inside that tarball, so nothing else is fetched at run time.

## What this improves over `source <(curl .../main/misc/build.func)`

- **Pinned, not `main`.** The URL names a tag. A push to a branch cannot change what you run.
- **Verified.** The payload is checked against a published checksum and fails closed.
- **No second live fetch.** Community scripts re-fetch shared functions from the network mid-install. Here the libs are in the verified tarball.
- **Independently auditable.** The `.sha256` is a published asset. You can compare it against the tarball yourself, and CI has a `bootstrap-pinning` test asserting the fail-closed behavior.

## What this does NOT protect against

- A fully compromised tag plus release could ship a matching checksum. The checksum defeats tampering and tag-move, not a total repo compromise. The real fix is **signed releases** (minisign/cosign), planned for a later phase. This document will not claim signing before it ships.
- The tools themselves download upstream artifacts (the AdGuard binary, etc.). Those are pinned to a version in each tool's `install.sh` and manifest, but they are fetched from the upstream project, whose supply chain is outside this repo.

## Verifying by hand

```bash
tag=v0.1.0
base=https://github.com/lidless-labs/lidless-proxmox/releases/download/$tag
curl -fsSLO $base/lidless-proxmox-$tag.tar.gz
curl -fsSLO $base/lidless-proxmox-$tag.tar.gz.sha256
sha256sum -c lidless-proxmox-$tag.tar.gz.sha256
tar -tzf lidless-proxmox-$tag.tar.gz   # inspect before running
```
