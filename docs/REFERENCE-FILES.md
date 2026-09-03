# Reference files & commands

Exact file contents referenced by the setup guide. All API keys / tokens shown here are
**placeholders** — replace them with your own.

---

## 1. `~/.claude/settings.json` (global — applies to ANY folder)

```jsonc
{
  // existing keys like "theme" / "apiKeyHelper" may also be present — preserved
  "env": {
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_API_BASE_URL": "http://127.0.0.1:3456",
    "CLAUDE_AGENT_API_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_MODEL": "gemini/gemini-3.6-flash[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "gemini/gemini-3.6-flash[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "gemini/gemini-3.6-flash[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gemini/gemini-3.6-flash[1m]",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "gemini/gemini-3.6-flash[1m]",
    "ANTHROPIC_SMALL_FAST_MODEL": "gemini/gemini-3.6-flash[1m]"
  }
}
```

> ⚠️ When CCR manages the "Claude Code" profile it may also write federation vars
> (`ANTHROPIC_FEDERATION_RULE_ID`, `ANTHROPIC_IDENTITY_TOKEN_FILE`,
> `ANTHROPIC_ORGANIZATION_ID`) — that's the router taking ownership; leave them.

---

## 2. Router `Providers` (stored in `~/.claude-code-router/config.sqlite`)

```json
{
  "name": "gemini",
  "api_base_url": "https://generativelanguage.googleapis.com/v1beta/models/",
  "api_key": "YOUR_GOOGLE_GEMINI_KEY",
  "models": ["gemini-3.6-flash"],
  "transformer": { "use": ["gemini"] }
},
{
  "name": "openrouter",
  "api_base_url": "https://openrouter.ai/api/v1/chat/completions",
  "api_key": "YOUR_OPENROUTER_KEY",
  "models": [
    "nvidia/nemotron-3-super-120b-a12b:free",
    "nvidia/nemotron-3.5-lightning:free",
    "minimax/minimax-m3:free"
  ],
  "transformer": { "use": ["openrouter"] }
}
```

---

## 3. Router `Router` rules (same SQLite store)

```jsonc
"Router": {
  "builtInRules": {
    "claude-code": { "enabled": true },
    "codex":     { "enabled": true }
  },
  "fallback": {
    "mode": "model-chain",
    "models": [
      "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
      "openrouter/minimax/minimax-m3:free"
    ],
    "retryCount": 1
  },
  "default":     "gemini,gemini-3.6-flash",
  "background":  "gemini,gemini-3.6-flash",
  "think":       "gemini,gemini-3.6-flash",
  "longContext": "gemini,gemini-3.6-flash",
  "webSearch":   "gemini,gemini-3.6-flash"
}
```

---

## 4. Commands reference

| Task | Command |
|---|---|
| Start router | `ccr start --no-open` |
| Open dashboard | `ccr ui` (prints URL + token) |
| Stop router | `ccr stop` |
| Check port | `lsof -nP -iTCP:3456 -sTCP:LISTEN` |
| Models through router | `curl -s -H "x-api-key: $(cat ~/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code)" -H 'anthropic-version: 2023-06-01' http://127.0.0.1:3456/v1/models` |
| Send message through router | `curl -s -m 180 -H "x-api-key: $(cat ~/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code)" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{"model":"openrouter/nvidia/nemotron-3-super-120b-a12b:free","max_tokens":64,"messages":[{"role":"user","content":"Say hi"}]}' http://127.0.0.1:3456/v1/messages` |
| Full E2E (real Claude Code) | `claude -p 'Reply with exactly: E2E_OK'` |
| Request log | `python3 -c "import sqlite3; con=sqlite3.connect('file:'+'$HOME/.claude-code-router/app-data/usage.sqlite?mode=ro',uri=True); [print(r) for r in con.execute('SELECT id,created_at,model,provider,status_code,duration_ms FROM usage_events ORDER BY id DESC LIMIT 10')]"` |
| No-Anthropic check | `lsof -nP -iTCP -sTCP:ESTABLISHED \| grep -i anthropic` → expect nothing |

---

## 5. OpenRouter free model discovery

```bash
curl -s -m 30 https://openrouter.ai/api/v1/models \
  -H "Authorization: Bearer $YOUR_OPENROUTER_KEY" \
  | python3 -c "import json,sys; print('\n'.join(m['id'] for m in json.load(sys.stdin)['data'] if ':free' in m['id']))"
```

Smoke test a specific free model before adding it to the router:

```bash
curl -s -m 60 -H "Authorization: Bearer $YOUR_OPENROUTER_KEY" -H 'Content-Type: application/json' \
  -H 'HTTP-Referer: http://localhost' -H 'X-Title: ccr-test' \
  -d '{"model":"nvidia/nemotron-3-super-120b-a12b:free","messages":[{"role":"user","content":"Say OK"}],"max_tokens":20}' \
  https://openrouter.ai/api/v1/chat/completions
```

## 6. Gemini model discovery

```bash
curl -s -m 30 "https://generativelanguage.googleapis.com/v1beta/models?key=$YOUR_GOOGLE_GEMINI_KEY" \
  | python3 -m json.tool | grep '"name"'
```

Smoke test (note: network can be flaky — retry a few times):

```bash
curl -s -m 90 -A 'Mozilla/5.0' \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$YOUR_GOOGLE_GEMINI_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"contents":[{"parts":[{"text":"Say OK"}]}],"generationConfig":{"maxOutputTokens":20}}'
```