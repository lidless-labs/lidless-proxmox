#!/usr/bin/env bash
# tools/adguard/verify.sh - runs INSIDE the LXC. Exit 0 iff AdGuard is
# genuinely usable, not merely "the service started". This is the same file
# the CI functional gate runs, so "installed" cannot pass without "works".
#
# Two planes, both required:
#   - DNS:  AdGuard resolves a name on 127.0.0.1:53
#   - Web:  the admin API on :80 answers over HTTP
set -euo pipefail
fail=0

# DNS plane: AdGuard must actually answer a query on 53.
if ! dig +short +time=3 +tries=1 @127.0.0.1 -p 53 example.com | grep -qE '[0-9]+\.[0-9]+'; then
  echo "[verify] FAIL: DNS on 127.0.0.1:53 did not resolve example.com" >&2
  fail=1
else
  echo "[verify] ok: DNS resolves on :53"
fi

# Web plane: the server must serve HTTP on 80. /control/status may require
# auth depending on version, so any real HTTP response (200/401/403) proves
# the web server is up; a connection failure (000) does not.
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1/control/status || true)"
case "${code}" in
  200|401|403) echo "[verify] ok: web API responds on :80 (HTTP ${code})" ;;
  *) echo "[verify] FAIL: web API on :80 returned '${code}'" >&2; fail=1 ;;
esac

exit "${fail}"
