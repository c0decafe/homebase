#!/usr/bin/env bash
set -euo pipefail

STAMP=".devcontainer/.bootstrap.done"
[[ -f "$STAMP" ]] && { echo "[bootstrap] already completed"; exit 0; }

echo "[bootstrap] start: devcontainer features first, nix fallback as needed"

mkdir -p "$HOME/.config/nix"
cat > "$HOME/.config/nix/nix.conf" <<'EOF'
experimental-features = nix-command flakes
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
allow-unfree = true
# accept-flake-config = true
EOF

[[ -f ".envrc" ]] || echo "use flake" > .envrc

mkdir -p .vscode
if [[ ! -f .vscode/settings.json && -f /opt/homebase/editor-settings.json ]]; then
  cp -f /opt/homebase/editor-settings.json .vscode/settings.json
fi

USE="${HOMEBASE_USE_NIX_FALLBACK:-auto}"

has_bin() { command -v "$1" >/dev/null 2>&1; }

BASIC_TOOLS=(git gh node npm python3 pip docker)
BASICS_OK=true
for t in "${BASIC_TOOLS[@]}"; do
  if ! has_bin "$t"; then BASICS_OK=false; break; fi
done

should_warm_nix=false
case "$USE" in
  always) should_warm_nix=true ;;
  never)  should_warm_nix=false ;;
  auto)   $BASICS_OK || should_warm_nix=true ;;
  *)      $BASICS_OK || should_warm_nix=true ;;
esac

if $should_warm_nix; then
  echo "[bootstrap] warming nix dev shell (fallback path)"
  nix develop -c true
else
  echo "[bootstrap] devcontainer features satisfied basics; skipping nix warmup"
fi

date > "$STAMP"
echo "[bootstrap] complete"
