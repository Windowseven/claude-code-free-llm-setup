# Claude Code with Free LLMs — Step-by-Step Setup (OpenRouter + Gemini via Claude Code Router)

> Run Anthropic's **Claude Code CLI** for free by routing all of its API traffic through
> **Claude Code Router (CCR)** to **free models on OpenRouter** and **Google Gemini** — no
> Anthropic API key, no Anthropic billing, and zero traffic to `api.anthropic.com`.

- **Real-world tested:** macOS, Claude Code v2.1.258, Claude Code Router v3.0.22, Node 22
- **Heads up:** the Claude Code banner (`Opus 5 (1M context) · API Usage Billing`) is
  **cosmetic branding only**. It appears even when every request goes to Gemini/OpenRouter.
  The proof is the router's live request log — not the banner.

---

## Table of contents

1. [How it works (architecture)](#how-it-works-architecture)
2. [Prerequisites](#prerequisites)
3. [Step 1 — Install Claude Code](#step-1--install-claude-code)
4. [Step 2 — Install Claude Code Router](#step-2--install-claude-code-router)
5. [Step 3 — Get API keys](#step-3--get-api-keys)
6. [Step 4 — Configure the router providers](#step-4--configure-the-router-providers)
7. [Step 5 — Point Claude Code at the router (global)](#step-5--point-claude-code-at-the-router-global)
8. [Step 6 — Map Claude's default models (critical fix)](#step-6--map-claudes-default-models-critical-fix)
9. [Step 7 — Add automatic failover (recommended)](#step-7--add-automatic-failover-recommended)
10. [Step 8 — Start the router](#step-8--start-the-router)
11. [Step 9 — Verify everything works](#step-9--verify-everything-works)
12. [Troubleshooting (real issues we hit)](#troubleshooting-real-issues-we-hit)
13. [Appendix A — Reference file contents](#appendix-a--reference-file-contents)
14. [Appendix B — Useful commands & model discovery](#appendix-b--useful-commands--model-discovery)

---

## How it works (architecture)

```
┌───────────────────┐          ┌──────────────────────────────┐        ┌───────────────────┐
│   Claude Code      │   HTTP   │  Claude Code Router (local)  │  HTTP  │  OpenRouter       │
│   CLI / VS Code    │ ───────► │  http://127.0.0.1:3456       │ ─────► │  Gemini API       │
└───────────────────┘          └──────────────────────────────┘        └───────────────────┘
  global env in                       providers + router rules               free models
  ~/.claude/settings.json             + fallback chain
```

1. Claude Code is pointed at a **local router** (`127.0.0.1:3456`) instead of `api.anthropic.com`.
2. The router translates the Anthropic `/v1/messages` protocol and forwards each request to
   the configured provider (Gemini via `generativelanguage.googleapis.com`, or OpenRouter).
3. If the primary provider fails, the router can **fail over** automatically to a fallback model.

---

## Prerequisites

```bash
node -v        # Node.js >= 22 (required by CCR v3)
npm -v
```

You also need two free API keys (see Step 3).

---

## Step 1 — Install Claude Code

The Anthropic npm package includes `claude` and runs fine even though we point it at a router
(no Anthropic key / login required when routed).

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

On macOS with a custom Node install, the binary typically lands at something like
`~/opt/node/bin/claude` — make sure that directory is on your `PATH`.

---

## Step 2 — Install Claude Code Router

```bash
npm install -g @musistudio/claude-code-router
ccr --help        # should print usage (start/ui/stop/serve)
```

Config/state lives in `~/.claude-code-router/`:

| File | Purpose |
|---|---|
| `config.sqlite` | **Authoritative config** (CCR v3) — providers, router rules, profile settings |
| `config.json` | **Legacy** config — read only as a migration source; editing it does nothing in v3 |
| `service.json` | Router state + private web token for the dashboard |
| `app-data/usage.sqlite` | Per-request log (great for debugging — provider, model, status, latency) |
| `bin/` | Generated wrapper scripts + API-key files that Claude Code uses |

> ⚠️ **CCR v3 config gotcha:** this version migrated config from `config.json` into a
> SQLite store. If you import/edit via the old JSON file, changes are **ignored by the
---

## Step 3 — Get API keys

| Key | Where | Format used by providers |
|---|---|---|
| **Google Gemini** | https://aistudio.google.com/apikey | `AIza...` or an OAuth-style `AQ.xxxx` |
| **OpenRouter** | https://openrouter.ai/keys | `sk-or-v1-...` |

Store them somewhere safe (e.g. your password manager). You will paste them into the router
config in Step 4. **Never commit them to a repo.**

---

## Step 4 — Configure the router providers

You can do this in the **web dashboard** (easiest) or by **editing config files** (scriptable).

### Option A — Dashboard (easiest)

1. Start the router (`ccr start --no-open`), then open the URL printed in the terminal
   (also stored in `~/.claude-code-router/service.json` under `url`).
2. Go to **Providers**, find/create:
   - `gemini` → paste Gemini key, add model(s) e.g. `gemini-3.6-flash`
   - `openrouter` → paste OpenRouter key, add model(s) e.g. `nvidia/nemotron-3-super-120b-a12b:free`
3. Save. The dashboard writes to the SQLite store correctly.

### Option B — Config file (scriptable, used in this repo's fixes)

The full provider block used here (replace the key placeholders):

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

> ⚠️ If you edit files directly, **stop the router first** (`ccr stop`), then patch the
> SQLite `app_config` row (JSON in `value_json`), then restart. Editing
> `~/.claude-code-router/config.json` alone will not take effect in CCR v3.
>
> Also, don't leave placeholder key text like `PASTE_YOUR_OPENROUTER_KEY_HERE` — a
> config migration has been observed to copy exactly those placeholders into the live
> store, producing silent `401`/`400 API key invalid` errors.

---

## Step 5 — Point Claude Code at the router (global)

All routing lives in the **global** user settings file `~/.claude/settings.json`, so it works
in **any folder** you open. There is no per-project override involved.

```jsonc
{
  "env": {
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_API_BASE_URL": "http://127.0.0.1:3456",
    "CLAUDE_AGENT_API_BASE_URL": "http://127.0.0.1:3456"
  }
}
```

Notes:

- CCR **regenerates this file** when it starts/owns the Claude Code profile, and it may add
  extra vars (`ANTHROPIC_MODEL`, `ANTHROPIC_*_MODEL`, federation/identity tokens). That is
  expected — don't fight it.
- The keys below are the ones CCR writes after it takes over the profile. If you manage the
  profile yourself, add at least the `ANTHROPIC_*_MODEL` overrides from Step 6.
---

## Step 6 — Map Claude's default models (critical fix)

Claude Code normally sends its **hardcoded default model** (e.g. `claude-opus-5`) in
`/v1/messages`. The router has **no route for `claude-opus-5`** unless you map it, which
produces `400 All target providers failed` in ~200ms **before any provider is even called**
(you'll see `provider: unknown` in the router's usage log).

Fix: tell Claude Code which provider model each "Claude tier" should actually use, via the
global env vars it always honors:

```jsonc
"env": {
  // ... Step 5 vars ...
  "ANTHROPIC_DEFAULT_OPUS_MODEL": "gemini/gemini-3.6-flash",
  "ANTHROPIC_DEFAULT_SONNET_MODEL": "gemini/gemini-3.6-flash",
  "ANTHROPIC_DEFAULT_HAIKU_MODEL": "gemini/gemini-3.6-flash",
  "ANTHROPIC_DEFAULT_FABLE_MODEL": "gemini/gemini-3.6-flash",
  "ANTHROPIC_SMALL_FAST_MODEL": "gemini/gemini-3.6-flash"
}
```

What the values mean:

- Model IDs are fully-qualified router IDs: `gemini/gemini-3.6-flash`,
  `openrouter/nvidia/nemotron-3-super-120b-a12b:free`.
- Any `claude-{opus,sonnet,haiku,fable}-*` request now arrives at the router as
  `gemini-3.6-flash` (or your choice) and routes correctly.

> If you let CCR manage the profile, it writes these for you (plus `ANTHROPIC_MODEL` and a
> `[1m]` context suffix, e.g. `gemini/gemini-3.6-flash[1m]`). After any change, **restart
> your open Claude Code session** — an old session keeps the old model name and keeps failing.

---

## Step 7 — Add automatic failover (recommended)

Free tiers are unreliable (Gemini frequently returns `503 high demand`; OpenRouter free
models rotate). Set the router to **fail over** when the primary provider fails:

Router `Router.fallback` config:

```jsonc
"Router": {
  // ...
  "fallback": {
    "mode": "model-chain",
    "models": [
      "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
      "openrouter/minimax/minimax-m3:free"
    ],
    "retryCount": 1
  }
}
```

With this, Gemini `429`/`502`/`503` automatically falls through to the OpenRouter free
model, and the user still gets a reply. (Verified in the request log: failed Gemini attempt →
`200` from `openrouter`.)
---

## Step 8 — Start the router

```bash
ccr start --no-open        # starts service + gateway; prints dashboard URL
ccr stop                   # stop when editing SQLite directly
ccr ui                     # start + open the dashboard
```

The service listens on:

- `127.0.0.1:3456` — the API gateway Claude Code talks to
- `127.0.0.1:3458` — the web dashboard (token-authenticated; URL + token in `service.json`)

Confirm it's listening:

```bash
lsof -nP -iTCP:3456 -sTCP:LISTEN
```

---

## Step 9 — Verify everything works

### 9a. Router model discovery

The API key shown is the per-profile key (read from `bin/ccr-claude-code-api-key-*`).

```bash
RP=$(cat ~/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code)
curl -s -H "x-api-key: $RP" -H 'anthropic-version: 2023-06-01' \
     http://127.0.0.1:3456/v1/models
```

Expected: only your configured Gemini + OpenRouter models.

### 9b. Send one message through the router

```bash
RP=$(cat ~/.claude-code-router/bin/ccr-claude-code-api-key-default-claude-code)
curl -s -m 180 -H "x-api-key: $RP" \
     -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
     -d '{"model":"openrouter/nvidia/nemotron-3-super-120b-a12b:free",
          "max_tokens":64,
          "messages":[{"role":"user","content":"Reply with exactly: ROUTER_OK"}]}' \
     http://127.0.0.1:3456/v1/messages
```

Expected: a JSON response with `"content"` containing `ROUTER_OK`. (OpenRouter is more
reliable than Gemini for this smoke test.)

### 9c. End-to-end with actual Claude Code

```bash
claude -p 'Reply with exactly: E2E_OK'
```

Expected output: `E2E_OK` (you may also see a harmless warning about an unrecognized model
used for *session-title generation* — it doesn't affect replies).

### 9d. Confirm no Anthropic traffic

```bash
lsof -nP -iTCP -sTCP:ESTABLISHED | grep -i anthropic   # should print nothing
# and inspect the router request log:
python3 - <<'EOF'
import sqlite3
con = sqlite3.connect('file:/Users/furahamogela/.claude-code-router/app-data/usage.sqlite?mode=ro', uri=True)
for r in con.execute('SELECT * FROM usage_events ORDER BY id DESC LIMIT 10'):
    print(r)
EOF
```

You should see `provider: gemini` / `provider: openrouter` and **never** `provider: anthropic`.
---

## Troubleshooting (real issues we hit)

| Symptom | Root cause | Fix |
|---|---|---|
| `400 All target providers failed` in < 1s, `provider: unknown` in usage log | Claude Code sends `claude-opus-5`; router has no route | Set `ANTHROPIC_DEFAULT_OPUS_MODEL` (and sonnet/haiku) to `gemini/gemini-3.6-flash`; **restart the Claude session** |
| `401 Missing Authentication header` (OpenRouter) / `API key not valid` (Gemini) | Placeholder keys like `PASTE_YOUR_*_KEY_HERE` ended up in the SQLite store after a config migration | Enter real keys via dashboard, or stop CCR and patch SQLite `app_config`, then restart |
| Editing `config.json` has no effect | CCR v3 reads the SQLite store, not legacy JSON | Use dashboard or patch `value_json` in `config.sqlite` with the router stopped |
| `404 This model ... no longer available to new users` (Gemini) | Model deprecated; only `gemini-3.6-flash` (etc.) available to this key | `GET /v1beta/models?key=...` to list available models, update to a live one |
| `404 This model is unavailable for free` (OpenRouter) | Free model rotated to paid-only | List current `:free` models from OpenRouter (Appendix B), update provider |
| `503 high demand` / `429` / `502` from Gemini (intermittent) | Free Google tier is overloaded | Add fallback chain (Step 7) or retry; keep Gemini as preferred model |
| Banner says `Opus 5 (1M context) · API Usage Billing` | Static branding, not real usage | Ignore it; confirm real usage via router request log |
| Warning `unrecognized_model ... generate_session_title` | Claude Code pings a cosmetic model for the session title | Harmless; the actual `settings.json` path is there. |
| `API key is missing` when curling `/v1/models` | Router requires the profile API key | Use the key from `bin/ccr-claude-code-api-key-default-claude-code` |
| Old Claude session still fails after fix | Session cached old model before override | `/exit` and start `claude` again |

---

## Appendix A — Reference file contents

### `~/.claude/settings.json` (global — this makes it work in ANY folder)

```jsonc
{
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

The `[1m]` suffix is the 1M-token context variant the router exposes; drop it if your setup
doesn't advertise `[1m]` variants.

### Router `Providers` (in `config.sqlite` / dashboard)

```jsonc
// name, api_base_url, api_key (placeholder), transformer as shown in Step 4
```

### Router `Router` rules

```jsonc
{
  "builtInRules": { "claude-code": { "enabled": true }, "codex": { "enabled": true } },
  "fallback": { "mode": "model-chain", "models": [
      "openrouter/nvidia/nemotron-3-super-120b-a12b:free",
      "openrouter/minimax/minimax-m3:free"
    ], "retryCount": 1 },
  "default": "gemini,gemini-3.6-flash",
  "background": "gemini,gemini-3.6-flash",
  "think": "gemini,gemini-3.6-flash",
  "longContext": "gemini,gemini-3.6-flash",
  "webSearch": "gemini,gemini-3.6-flash"
}
```

---

## Appendix B — Useful commands & model discovery

### List Gemini models available to a key

```bash
GKEY="YOUR_GOOGLE_GEMINI_KEY"
curl -s -m 30 "https://generativelanguage.googleapis.com/v1beta/models?key=$GKEY" \
  | python3 -m json.tool | grep '"name"'
# Then smoke-test one (note: the network can be flaky — retry a few times):
curl -s -m 90 -A 'Mozilla/5.0' \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$GKEY" \
  -H 'Content-Type: application/json' \
  -d '{"contents":[{"parts":[{"text":"Say OK"}]}],"generationConfig":{"maxOutputTokens":20}}'
```

### List OpenRouter free models (and smoke-test them)

```bash
OKEY="YOUR_OPENROUTER_KEY"
curl -s -m 30 https://openrouter.ai/api/v1/models -H "Authorization: Bearer $OKEY" \
  | python3 -c "import json,sys; print('\n'.join(m['id'] for m in json.load(sys.stdin)['data'] if ':free' in m['id']))"
```

Smoke test — verify the model actually answers before adding it to the router:

```bash
curl -s -m 60 -H "Authorization: Bearer $OKEY" -H 'Content-Type: application/json' \
     -H 'HTTP-Referer: http://localhost' -H 'X-Title: ccr-test' \
     -d '{"model":"nvidia/nemotron-3-super-120b-a12b:free",
          "messages":[{"role":"user","content":"Say OK"}],"max_tokens":20}' \
     https://openrouter.ai/api/v1/chat/completions
```

### Day-to-day

```bash
ccr start --no-open     # ensure the router is running
claude                  # use Claude Code as usual (any folder — config is global)
ccr stop                # only if you plan to edit SQLite directly
```

---

*This guide documents a real, working setup. No Anthropic API key or subscription is used —
all traffic goes to Gemini/OpenRouter through the local router.*
> running router**. Always use the dashboard UI, or stop CCR before touching the SQLite files.