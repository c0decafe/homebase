#!/usr/bin/env bash
set -euo pipefail

STAMP=".devcontainer/.bootstrap.done"
[[ -f "$STAMP" ]] && { echo "[bootstrap] already completed"; exit 0; }

echo "[bootstrap] start"

mkdir -p "$HOME/.config/nix"
cat > "$HOME/.config/nix/nix.conf" <<'EOF'
experimental-features = nix-command flakes
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
allow-unfree = true
EOF

[[ -f ".envrc" ]] || echo "use flake" > .envrc

mkdir -p .vscode
SRC="/opt/homebase/editor-settings.json"
if [[ ! -f "$SRC" ]]; then
  echo "[bootstrap] no baked editor-settings.json; building from flake"
  nix build -L .#editor-settings --out-link .editor-settings
  SRC="$(readlink -f .editor-settings)"
fi

cp -f "$SRC" .vscode/settings.json
echo "[bootstrap] copied editor settings -> .vscode/settings.json"

for TARGET in   "$HOME/.vscode-server/data/Machine/settings.json"   "$HOME/.config/Code/User/settings.json"
do
  mkdir -p "$(dirname "$TARGET")"
  cp -f "$SRC" "$TARGET" || true
done

date > "$STAMP"
echo "[bootstrap] complete"
