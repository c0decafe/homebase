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
command -v direnv >/dev/null 2>&1 && direnv allow || true

mkdir -p .vscode
SRC="/opt/homebase/editor-settings.json"
if [[ ! -f "$SRC" ]]; then
  echo "[bootstrap] building editor-settings from flake"
  nix build -L .#editor-settings --no-write-lock-file --out-link .editor-settings
  SRC="$(readlink -f .editor-settings)"
fi

HASHDIR=".devcontainer"
HASHFILE="$HASHDIR/.sync.hash"
mkdir -p "$HASHDIR"
current_hash="$( (sha256sum "$HASHDIR/devcontainer.json" 2>/dev/null || true; sha256sum "$SRC") | sha256sum | awk '{print $1}' )"
previous_hash="$(cat "$HASHFILE" 2>/dev/null || true)"

merge_settings() {
  if command -v jq >/dev/null 2>&1 && [[ -f ".vscode/settings.json" ]]; then
    tmp="$(mktemp)"
    jq -s '.[0] * .[1]' "$SRC" .vscode/settings.json > "$tmp" && mv "$tmp" .vscode/settings.json
  else
    cp -f "$SRC" .vscode/settings.json
  fi
}

if [[ "$current_hash" != "$previous_hash" ]] || [[ ! -f ".vscode/settings.json" ]]; then
  merge_settings
  echo "[bootstrap] synced VS Code settings -> .vscode/settings.json"

  for TARGET in     "$HOME/.vscode-server/data/Machine/settings.json"     "$HOME/.config/Code/User/settings.json"
  do
    mkdir -p "$(dirname "$TARGET")"
    cp -f ".vscode/settings.json" "$TARGET" || true
  done

  echo "$current_hash" > "$HASHFILE"
else
  echo "[bootstrap] settings already in sync"
fi

echo "[bootstrap] complete"
