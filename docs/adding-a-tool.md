# Adding a tool

A tool is a folder under `tools/<name>/` with exactly three files. The shared orchestrator (`lib/deploy-one.sh`) drives every tool through the same lifecycle, so adding one means dropping in a folder with no orchestrator changes.

```
tools/<name>/
├── manifest.jsonc   # declarative: presets, ports, template, what it provides
├── install.sh       # runs INSIDE the LXC: idempotent install + first-run config
└── verify.sh        # runs INSIDE the LXC: exit 0 iff the tool actually works
```

This is soc-stack's six-file component contract collapsed for standalone single-tool use: no `integrate.sh` (nothing to wire), no per-tool `lxc-spec.sh` (the orchestrator derives `pct` flags from the manifest preset), and destroy is handled by the shared reaper.

## manifest.jsonc

JSONC (JSON with `//` comments). CI strips comments and validates `.name`, `.presets`, and `.presets.standard.ram_mb`.

```jsonc
{
  "name": "adguard",
  "display_name": "AdGuard Home",
  "description": "One sentence: what it is.",
  "provides": ["adguard_url", "adguard_admin_user", "adguard_admin_password"],
  "presets": {
    "minimal":  { "ram_mb": 512,  "disk_gb": 4, "cores": 1 },
    "standard": { "ram_mb": 1024, "disk_gb": 8, "cores": 2 }
  },
  "ports": [53, 80],
  "template_pattern": "debian-12-standard",
  "unprivileged": true,
  "pinned": { "adguard_version": "v0.107.52" }
}
```

`template_pattern` is matched against `pveam list`; the orchestrator downloads it if absent. Add `"features": ["nesting=1"]` for tools that need it (Docker inside the LXC).

## install.sh (runs inside the LXC)

The orchestrator pushes only this file into the container and runs it with `LL_STATE_DIR`, `LL_SECRETS_DIR`, `LL_TOOL`, `LL_PRESET`, `LL_NON_INTERACTIVE=1` in the environment. It is **self-contained**: define your own small helpers, do not assume the repo libs are present.

Rules:

1. **Idempotent.** Re-running must not double-install or rotate a working credential. Check for the installed binary and the stored secret first.
2. **Do the first-run config.** This is the whole point. Do not stop at "package installed" and leave a setup wizard. Configure the admin user, the service, and the listeners so the tool is usable when you exit.
3. **Pin what you download.** Version, tag, or commit SHA for anything fetched at install time. Keep it in sync with the manifest `pinned` block.
4. **Persist secrets before use** to `${LL_SECRETS_DIR}/<tool>-<slot>.txt` (mode 0600), so a mid-install crash is recoverable on re-run.
5. **Write state last.** Finish by writing `status: deployed` plus service URLs to `${LL_STATE_DIR}/state/<tool>.json`. Set an `ERR` trap that writes `status: failed`.

## verify.sh (runs inside the LXC)

Exit 0 only when the tool is genuinely usable: services active AND the real interface answers (query the DNS port, curl the web API, hit the health endpoint). This is the same file the CI functional gate runs, so a hollow install cannot pass. The orchestrator retries it 3 times, 30s apart, before marking the tool failed.

## Checklist

1. Create the three files (`chmod +x install.sh verify.sh`).
2. `shellcheck --severity=warning tools/<name>/*.sh` clean.
3. Add the tool to the README tools table.
4. Smoke it: `LL_SMOKE=1 bash lib/deploy-one.sh <name>` on a Proxmox host, confirm `verify.sh` passes, tear the container down.
