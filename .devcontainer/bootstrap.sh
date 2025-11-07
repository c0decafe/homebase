#!/usr/bin/env bash
set -euo pipefail

echo "[bootstrap] start"

mkdir -p "$HOME/.config/nix"
cat > "$HOME/.config/nix/nix.conf" <<'EOF'
experimental-features = nix-command flakes
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
EOF

[[ -f ".envrc" ]] || echo "use flake" > .envrc

for sh in bash zsh; do
  rc="$HOME/.${sh}rc"
  if [[ "$sh" == "bash" ]]; then
    hook='eval "$(direnv hook bash)"'
  else
    hook='eval "$(direnv hook zsh)"'
  fi
  grep -q 'direnv hook' "$rc" 2>/dev/null || echo "$hook" >> "$rc"
done

mkdir -p .vscode
SRC="/opt/homebase/editor-settings.json"
if [[ ! -f "$SRC" ]]; then
  echo "[bootstrap] no baked editor-settings.json; building from flake"
  nix build -L .#editor-settings --no-write-lock-file --out-link .editor-settings
  SRC="$(readlink -f .editor-settings)"
fi

HASHDIR=".devcontainer"
HASHFILE="$HASHDIR/.sync.hash"
mkdir -p "$HASHDIR"
current_hash="$( (sha256sum "$HASHDIR/devcontainer.json" 2>/dev/null || true; sha256sum "$SRC") | sha256sum | awk '{print $1}' )"
previous_hash="$(cat "$HASHFILE" 2>/dev/null || true)"

if [[ "$current_hash" != "$previous_hash" ]] || [[ ! -f ".vscode/settings.json" ]]; then
  cp -f "$SRC" .vscode/settings.json
  echo "[bootstrap] synced VS Code settings -> .vscode/settings.json"

  for TARGET in     "$HOME/.vscode-server/data/Machine/settings.json"     "$HOME/.config/Code/User/settings.json"
  do
    mkdir -p "$(dirname "$TARGET")"
    cp -f "$SRC" "$TARGET" || true
  done

  echo "$current_hash" > "$HASHFILE"
else
  echo "[bootstrap] settings already in sync"
fi

echo "[bootstrap] complete"
