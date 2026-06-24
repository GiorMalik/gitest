#!/usr/bin/env bash
set -euo pipefail

echo "🚀 GITEST Uninstall"
echo "===================="

REMOVED=false

# Cari gitest.md di semua kemungkinan lokasi commands
for dir in "$HOME/.opencode/commands" "$HOME/.config/opencode/commands" "/root/.opencode/commands"; do
  if [ -f "$dir/gitest.md" ]; then
    rm "$dir/gitest.md"
    echo "✅ Removed: $dir/gitest.md"
    REMOVED=true
  fi
done

if [ "$REMOVED" = false ]; then
  echo "ℹ️  gitest.md not found — already uninstalled"
fi

# Hapus SCAN directory
SCAN_BASE="${GITEST_SCAN_DIR:-$HOME/SCAN}"
if [ -d "$SCAN_BASE" ]; then
  echo ""
  echo "📁 Scan output directory found: $SCAN_BASE"
  echo -n "   Remove this directory and all scan results? [y/N] "
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$SCAN_BASE"
    echo "✅ Removed: $SCAN_BASE"
  else
    echo "⏭️  Skipped"
  fi
else
  echo "ℹ️  Scan directory not found: $SCAN_BASE"
fi

echo ""
echo "✅ GITEST uninstalled"
echo "   The cloned gitest/ directory is still on your system."
echo "   Remove it manually: rm -rf $(cd "$(dirname "$0")" && pwd)"
