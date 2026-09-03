# Claude Code with Free LLMs — OpenRouter / Gemini via Claude Code Router

Run Anthropic's **Claude Code CLI entirely for free** by routing every request through
[Claude Code Router](https://github.com/musistudio/claude-code-router) to **free models on
OpenRouter** and **Google Gemini**. No Anthropic API key, no Anthropic billing, and no traffic
to `api.anthropic.com`.

- **Real-world tested:** macOS, Claude Code v2.1.258, Claude Code Router v3.0.22, Node 22
- The `Opus 5 (1M context) · API Usage Billing` banner Claude Code prints is **cosmetic
  branding** — it appears even when all traffic goes to Gemini/OpenRouter. Verify with the
  router's request log (see [docs](./docs/)).

---

## Quick start

```bash
# 1. Install
npm install -g @anthropic-ai/claude-code
npm install -g @musistudio/claude-code-router

# 2. Get free API keys
#    OpenRouter: https://openrouter.ai/keys
#    Gemini:     https://aistudio.google.com/apikey

# 3. Configure providers in the router dashboard
ccr start --no-open        # open the printed URL (also in ~/.claude-code-router/service.json)

# 4. Point Claude Code at the router + map its default models (global → any folder)
./setup/apply-claude-settings.sh "gemini/gemini-3.6-flash[1m]"

# 5. Use it
claude
```

> 💡 There are helper scripts in [`setup/`](./setup/) that automate install, config,
> and verification. See each file header for usage.

---

## Why the "critical fix" exists

Claude Code normally sends its hardcoded default model name (`claude-opus-5`) to the router.
The router has no provider route for that name, so requests die with
`400 All target providers failed` in ~200 ms **without any provider being called**
(`provider: unknown` in the request log).

The fix maps Claude's tiers (`ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU/FABLE_MODEL`, plus
`ANTHROPIC_MODEL` and `ANTHROPIC_SMALL_FAST_MODEL`) to a real router model ID like
`gemini/gemini-3.6-flash`. Free tiers are flaky, so a **fallback chain** to a working
OpenRouter free model is also configured (Gemini `429/502/503` → auto-failover to
`openrouter/nvidia/nemotron-3-super-120b-a12b:free`).

---

## Documentation

| File | What it is |
|---|---|
| [`docs/CLAUDE-CODE-FREE-LLM-SETUP.md`](docs/CLAUDE-CODE-FREE-LLM-SETUP.md) | Full step-by-step guide + troubleshooting (the "everything we did" doc) |
| [`docs/REFERENCE-FILES.md`](docs/REFERENCE-FILES.md) | Exact config file contents + command reference |
| [`setup/install.sh`](setup/install.sh) | Install Claude Code + CCR |
| [`setup/apply-claude-settings.sh`](setup/apply-claude-settings.sh) | Write global `~/.claude/settings.json` with router + model overrides |
| [`setup/configure-providers.json`](setup/configure-providers.json) | Router provider block (placeholders for your keys) |
| [`setup/apply-router-config.sh`](setup/apply-router-config.sh) | Stop CCR → patch SQLite providers/fallback → restart |
| [`setup/verify.sh`](setup/verify.sh) | E2E verification (router up, models, chat request, `claude -p`, no-Anthropic check) |

---

## Security

- **Never commit real API keys.** This repo only contains placeholders.
- Router API keys / tokens under `~/.claude-code-router/` are machine-local and out of scope.
- `ccr start` may re-write the global `~/.claude/settings.json` (router-managed profile).
  That's expected.

---

## License

MIT — do whatever you want, and credit the upstream projects
([Claude Code Router](https://github.com/musistudio/claude-code-router),
[Claude Code](https://github.com/anthropics/claude-code)).