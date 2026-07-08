#!/usr/bin/env bash
# tools/lidless-smoke-reaper.sh
# Cron GC for smoke-test containers. Destroys any LXC in the 9000-9099 band
# older than MAX_AGE_MIN. Production LXCs (< 9000, > 9099) are never touched.
#
# Install on the Proxmox host, e.g.:
#   */15 * * * * root /opt/lidless-proxmox/tools/lidless-smoke-reaper.sh
#
# Ported from soc-stack's test reaper. Deliberately keys ONLY on the VMID
# band, so it is safe even if a hostname convention drifts.
set -euo pipefail

LOG="${LL_REAPER_LOG:-/var/log/lidless-smoke-reaper.log}"
MAX_AGE_MIN="${LL_REAPER_MAX_AGE_MIN:-90}"
BAND_LO="${LL_REAPER_BAND_LO:-9000}"
BAND_HI="${LL_REAPER_BAND_HI:-9099}"
CONF_DIR="${LL_REAPER_CONF_DIR:-/etc/pve/lxc}"

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >> "${LOG}"; }

now=$(date +%s)
threshold=$(( now - MAX_AGE_MIN * 60 ))

pct list 2>/dev/null | awk 'NR>1' | while read -r vmid _ _; do
  [[ "${vmid}" =~ ^[0-9]+$ ]] || continue
  if (( vmid >= BAND_LO && vmid <= BAND_HI )); then
    conf="${CONF_DIR}/${vmid}.conf"
    if [[ -f "${conf}" ]]; then
      mtime=$(stat -c %Y "${conf}")
      if (( mtime < threshold )); then
        log "reaping LXC ${vmid} (mtime=${mtime}, threshold=${threshold})"
        pct stop "${vmid}" 2>/dev/null || true
        pct destroy "${vmid}" 2>/dev/null || true
      fi
    fi
  fi
done
