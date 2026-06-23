#!/usr/bin/env bash
set -euo pipefail

GITEST_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🚀 gitest — GIOR Pentest Framework Setup"
echo "==========================================="

# Check requirements
REQUIRED=(curl jq python3)
MISSING=()
for cmd in "${REQUIRED[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    MISSING+=("$cmd")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "❌ Missing: ${MISSING[*]}"
  echo "   Install with: apt-get install -y ${MISSING[*]}"
  exit 1
fi

echo "✅ All core dependencies present"

# Setup pentest command
if [ -d "/root/.opencode/commands" ]; then
  CMD_DIR="/root/.opencode/commands"
elif [ -d "$HOME/.config/opencode/commands" ]; then
  CMD_DIR="$HOME/.config/opencode/commands"
else
  CMD_DIR="$HOME/.opencode/commands"
  mkdir -p "$CMD_DIR"
fi

echo "📁 gitest command will be at: $CMD_DIR/gitest.md"

# Install command
if [ -f "$GITEST_DIR/.opencode/commands/gitest.md" ]; then
  cp "$GITEST_DIR/.opencode/commands/gitest.md" "$CMD_DIR/gitest.md"
  echo "✅ gitest command installed from repo"
elif [ -f "/root/.opencode/commands/gitest.md" ]; then
  cp "/root/.opencode/commands/gitest.md" "$CMD_DIR/gitest.md"
  echo "✅ gitest command installed"
else
  echo "⚠️  gitest.md not found. Copy manually to $CMD_DIR/"
fi

# Setup SCAN directory
SCAN_BASE="${GITEST_SCAN_DIR:-$HOME/SCAN}"
mkdir -p "$SCAN_BASE/targets"
echo "📁 SCAN output directory: $SCAN_BASE"

echo ""
echo "✅ gitest setup complete!"
echo "   Run: /gitest https://target.example.com"
