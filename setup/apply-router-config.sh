#!/usr/bin/env bash
# apply-router-config.sh — Write providers + router rules + fallback into CCR's
# authoritative SQLite store.  Safe: stops CCR first, patches, restarts.
#
# Usage:
#   ./apply-router-config.sh YOUR_GOOGLE_GEMINI_KEY YOUR_OPENROUTER_KEY
#
# Reads ./configure-providers.json for provider/model definitions.
set -euo pipefail

GEMINI_KEY="${1:?Usage: ./apply-router-config.sh GEMINI_KEY OPENROUTER_KEY}"
OPENROUTER_KEY="${2:?Usage: ./apply-router-config.sh GEMINI_KEY OPENROUTER_KEY}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQLITE="$HOME/.claude-code-router/config.sqlite"
JSON_REF="$SCRIPT_DIR/configure-providers.json"

command -v python3 >/dev/null
command -v /Users/furahamogela/opt/node/bin/ccr >/dev/null 2>&1 && CCR=/Users/furahamogela/opt/node/bin/ccr || CCR=$(command -v ccr)

echo "==> Stopping CCR (safe SQLite edit)"
if [ -n "${CCR:-}" ]; then "$CCR" stop 2>/dev/null || true; fi

echo "==> Patching $SQLITE"
python3 - "$SQLITE" "$JSON_REF" "$GEMINI_KEY" "$OPENROUTER_KEY" <<'PY'
import json, sqlite3, sys
sqlite_path, json_ref, gkey, okey = sys.argv[1:5]
providers = json.load(open(json_ref))["Providers"]
for p in providers:
    if p.get("name") == "gemini":
        p["api_key"] = gkey
    elif p.get("name") == "openrouter":
        p["api_key"] = okey

con = sqlite3.connect(sqlite_path)
row = con.execute("SELECT key, value_json FROM app_config WHERE key='default'").fetchone()
if not row:
    raise SystemExit("app_config default row not found")
cfg = json.loads(row[1])
cfg["Providers"] = providers
cfg.setdefault("Router", {})["fallback"] = {
    "mode": "model-chain",
    "models": [
        "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
        "gemini/gemini-3.6-flash",
    ],
    "retryCount": 1,
}
con.execute("UPDATE app_config SET value_json=? WHERE key=?", (json.dumps(cfg, ensure_ascii=False), row[0]))
con.commit()
con.close()
print("  providers:", [p["name"] for p in providers])
print("  fallback : model-chain -> openrouter nemotron/minimax")
PY

echo "==> Restarting CCR"
if [ -n "${CCR:-}" ]; then "$CCR" start --no-open; else echo "ccr not found — start manually"; fi

echo
echo "Done. Verify with: ./verify.sh"