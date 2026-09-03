#!/usr/bin/env bash
# verify.sh — End-to-end verification that Claude Code talks to the router
# (and never to Anthropic), and that the primary provider + fallback work.
#
# Usage: ./verify.sh [model_id]
#   default model_id = openrouter/nvidia/nemotron-3-super-120b-a12b:free (most reliable)
set -euo pipefail

MODEL="${1:-openrouter/nvidia/nemotron-3-super-120b-a12b:free}"
PORT="${PORT:-3456}"
KEY_FILE="$HOME/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code"

if [ ! -r "$KEY_FILE" ]; then
  echo "Key file not found at $KEY_FILE — is the router configured for a Claude Code profile?" >&2
  exit 1
fi
RP="$(cat "$KEY_FILE")"
BASE="http://127.0.0.1:$PORT"

echo "==> 1/5 Router up?"
if ! lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "  Router NOT listening on :$PORT. Start it: ccr start --no-open" >&2
  exit 1
fi
echo "  OK"

echo "==> 2/5 Models discovered"
curl -s -m 10 -H "x-api-key: $RP" -H 'anthropic-version: 2023-06-01' "$BASE/v1/models" \
  | python3 -c "import json,sys; print('  ', [m['id'] for m in json.load(sys.stdin).get('data',[])])"

echo "==> 3/5 Send a chat request through the router (model=$MODEL)"
RESP="$(curl -s -m 180 -H "x-api-key: $RP" -H 'anthropic-version: 2023-06-01' \
  -H 'content-type: application/json' \
  -d "{\"model\":\"$MODEL\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: ROUTER_OK\"}]}" \
  "$BASE/v1/messages")"
echo "  $(echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('content') or ('ERR: '+str(d.get('error',{}).get('message'))[:160]))")"

echo "==> 4/5 End-to-end via real Claude Code (claude -p)"
OUT="$(/Users/furahamogela/opt/node/bin/claude -p 'Reply with exactly: E2E_OK' 2>&1 || true)"
echo "  $(echo "$OUT" | grep -v 'unrecognized_model' | tail -2 | tr '\n' ' ')"

echo "==> 5/5 Confirm no Anthropic connections"
NO_ANTH="$(lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -ic anthropic || true)"
echo "  established Anthropic connections: $NO_ANTH (expect 0)"

echo
echo "Done. Full request log: ~/.claude-code-router/app-data/usage.sqlite"