#!/usr/bin/env bash
# apply-claude-settings.sh — Write the GLOBAL Claude Code settings so any folder
# uses the router, and Claude's default tier models map to a usable free model.
#
# Usage:  ./apply-claude-settings.sh "gemini/gemini-3.6-flash[1m]"
#   (optional arg = model string; default below)
set -euo pipefail

MODEL="${1:-gemini/gemini-3.6-flash[1m]}"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.claude"

# Keep existing keys like theme/apiKeyHelper if present.
_scratch="$(mktemp)"
python3 - "$SETTINGS" "$MODEL" "$_scratch" <<'PY'
import json, os, sys
path, model, out = sys.argv[1], sys.argv[2], sys.argv[3]
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
env = data.setdefault("env", {})
env.update({
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_API_BASE_URL": "http://127.0.0.1:3456",
    "CLAUDE_AGENT_API_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_MODEL": model,
    "ANTHROPIC_DEFAULT_OPUS_MODEL": model,
    "ANTHROPIC_DEFAULT_SONNET_MODEL": model,
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": model,
    "ANTHROPIC_DEFAULT_FABLE_MODEL": model,
    "ANTHROPIC_SMALL_FAST_MODEL": model,
})
with open(out, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("Wrote global settings (preserving existing keys):", path)
PY
mv "$_scratch" "$SETTINGS"

echo
echo "==> Result: $SETTINGS"
cat "$SETTINGS"
echo
echo "Note: if the router manages this profile, 'ccr' may rewrite this file — expected."