#!/usr/bin/env bash
# install.sh — Install Claude Code + Claude Code Router (CCR)
# Usage: ./install.sh
set -euo pipefail

echo "==> Checking Node.js >= 22 (required by CCR v3)"
node -v

echo "==> Installing Claude Code"
npm install -g @anthropic-ai/claude-code

echo "==> Installing Claude Code Router"
npm install -g @musistudio/claude-code-router

echo
echo "Done. Versions:"
claude --version 2>/dev/null || true
ccr --help 2>&1 | head -3 || true
echo
echo "Next: get API keys (OpenRouter: https://openrouter.ai/keys, Gemini: https://aistudio.google.com/apikey)"
echo "Then run: ./configure-providers via the dashboard (ccr ui) or apply-router-config.sh"