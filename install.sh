#!/bin/bash
# Build screend, install it to ~/.local/bin, and register the login agent.
set -euo pipefail
cd "$(dirname "$0")"

MIC=""
[[ "${1:-}" == "--mic" ]] && MIC="--mic"

echo "Building..."
swift build -c release

mkdir -p "$HOME/.local/bin"
cp .build/release/screend "$HOME/.local/bin/screend"
echo "Installed: $HOME/.local/bin/screend"

"$HOME/.local/bin/screend" install $MIC

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo
     echo "Note: ~/.local/bin is not on your PATH. To add it:"
     echo '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.zshrc' ;;
esac
