#!/usr/bin/env bash
# model.sh — List, add, remove, and switch default free-LM models for Claude Code
# (works globally — any folder — because it edits the router's authoritative config).
#
# Usage:
#   ./model.sh list                               # show models currently available via the router
#   ./model.sh add    <openrouter-model-id>       # make a new model available (uses existing key)
#   ./model.sh remove <model-id>                  # stop advertising a model
#   ./model.sh default <full-router-model-id>     # switch the ACTIVE default model for Claude Code
#   ./model.sh blacklist <model-id>               # remove a model from the fallback chain
#
# Examples:
#   ./model.sh add nvidia/nemotron-3-super-120b-a12b:free
#   ./model.sh default openrouter/nvidia/nemotron-3-super-120b-a12b:free
#   ./model.sh default gemini/gemini-3.6-flash[1m]      # back to Gemini
#
# Notes:
#   - MODEL IDs: router uses "provider/<model>" (e.g. openrouter/nvidia/nemotron-3-super-120b-a12b:free,
#     gemini/gemini-3.6-flash[1m]). ADD expects the bare OpenRouter id (nvidia/nemotron-3-super-120b-a12b:free).
#   - Editing is done on config.sqlite with CCR stopped, then CCR is restarted so the
#     launcher wrapper + global ~/.claude/settings.json are regenerated automatically.
set -euo pipefail

CCR="${CCR:-/Users/furahamogela/opt/node/bin/ccr}"
[ -x "$CCR" ] || CCR="$(command -v ccr || true)"
SQLITE="$HOME/.claude-code-router/config.sqlite"
KEY_FILE="$HOME/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code"
BASE="http://127.0.0.1:3456"
PATCHER="$(mktemp)"
cat > "$PATCHER" <<'PY'
import json, sqlite3, sys
op, arg = sys.argv[1], sys.argv[2]
sqlite_path = sys.argv[3]

con = sqlite3.connect(sqlite_path)
key, val = con.execute("SELECT key, value_json FROM app_config WHERE key='default'").fetchone()
cfg = json.loads(val)

class NoChange(Exception):
    pass

if op == "add":
    for p in cfg.get("Providers", []):
        if p.get("name") == "openrouter":
            if arg not in p.get("models", []):
                p.setdefault("models", []).append(arg)
            else:
                raise NoChange("model already present")
elif op == "remove":
    touched = False
    for p in cfg.get("Providers", []):
        if arg in p.get("models", []):
            p["models"].remove(arg)
            touched = True
    if not touched:
        raise NoChange("model not in any provider")
elif op == "default":
    fields = ("model", "opusModel", "sonnetModel", "haikuModel", "fableModel", "smallFastModel")
    cc = cfg.setdefault("profile", {}).setdefault("claudeCode", {})
    for f in fields:
        cc[f] = arg
    for pr in cfg.setdefault("profile", {}).get("profiles", []):
        if pr.get("id") == "default-claude-code":
            for f in fields:
                pr[f] = arg
elif op == "blacklist":
    fb = cfg.setdefault("Router", {}).setdefault("fallback", {})
    fb["models"] = [m for m in fb.get("models", []) if m != arg]
else:
    raise SystemExit("unknown op")

con.execute("UPDATE app_config SET value_json=? WHERE key=?",
            (json.dumps(cfg, ensure_ascii=False), key))
con.commit()
con.close()
print("patched:", op, arg)
PY

list_models() {
  local rp=""
  [ -r "$KEY_FILE" ] && rp="$(cat "$KEY_FILE")"
  if [ -n "$rp" ] && lsof -nP -iTCP:3456 -sTCP:LISTEN >/dev/null 2>&1; then
    curl -s -m 10 -H "x-api-key: $rp" -H 'anthropic-version: 2023-06-01' "$BASE/v1/models" \
      | python3 -c "import json,sys; [print(' - '+m['id']) for m in json.load(sys.stdin).get('data',[])]"
  else
    python3 - "$SQLITE" <<'PY2'
import json, sqlite3, sys
con = sqlite3.connect("file:"+sys.argv[1]+"?mode=ro", uri=True)
d = json.loads(con.execute("SELECT value_json FROM app_config").fetchone()[0])
for p in d.get("Providers", []):
    print(f" - {p['name']}: " + ", ".join(p.get("models", [])))
PY2
  fi
}

verify_openrouter_id() {
  local id="$1"
  local key
  key="$(python3 - "$SQLITE" <<'PY3'
import json, sqlite3, sys
con = sqlite3.connect("file:"+sys.argv[1]+"?mode=ro", uri=True)
d = json.loads(con.execute("SELECT value_json FROM app_config").fetchone()[0])
for p in d.get("Providers", []):
    if p.get("name") == "openrouter":
        print(p.get("api_key", ""))
PY3
)"
  echo "verifying '$id' responds via OpenRouter..."
  curl -s -m 90 -H "Authorization: Bearer $key" -H 'Content-Type: application/json' \
       -H 'HTTP-Referer: http://localhost' -H 'X-Title: ccr-model-tool' \
       -d "{\"model\":\"$id\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":16}" \
       https://openrouter.ai/api/v1/chat/completions \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ->', 'OK: works' if d.get('choices') else 'FAILED: '+str(d.get('error',{}).get('message'))[:120])"
}

patch_sqlite() {
  # $1 = op, $2 = model id
  local op="$1" id="$2"
  "$CCR" stop >/dev/null 2>&1 || true
  if python3 "$PATCHER" "$op" "$id" "$SQLITE"; then
    "$CCR" start --no-open >/dev/null 2>&1 || true
  else
    "$CCR" start --no-open >/dev/null 2>&1 || true
    return 1
  fi
}

cmd="${1:-help}"
case "$cmd" in
  list)
    list_models
    ;;
  add)
    id="${2:?usage: ./model.sh add <openrouter-model-id>}"
    patch_sqlite add "$id" && { echo "added '$id'."; verify_openrouter_id "$id"; }
    ;;
  remove)
    id="${2:?usage: ./model.sh remove <model-id>}"
    patch_sqlite remove "$id" && echo "removed '$id' from provider model lists."
    ;;
  default)
    id="${2:?usage: ./model.sh default <full-router-model-id>}"
    patch_sqlite default "$id" && echo "default switched to: $id  (global — affects any folder)"
    ;;
  blacklist)
    id="${2:?usage: ./model.sh blacklist <full-router-model-id>}"
    patch_sqlite blacklist "$id" && echo "removed '$id' from fallback chain."
    ;;
  *)
    sed -n '2,16p' "$0"
    ;;
esac
trap 'rm -f "$PATCHER"' EXIT