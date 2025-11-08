# 🏠 homebase — nix2container edition

- Builds with **nix2container** (no Docker daemon, no tarballs) and pushes via Skopeo.
- DRY toolset is shared across the image and devShell (Wrangler, skopeo, LSPs, CLI basics).
- DevContainer: minimal features; forwards **3000 / 5173 / 8000**.
- Bootstrap merges VS Code settings with `jq`, adds direnv hooks, first-run `direnv allow`.
- CI: `nix build .#homebase` + `nix run .#push` to publish to `ghcr.io/c0decafe/homebase:latest`.

## Local usage
- Open the folder in VS Code / Codespaces. The container uses the published image and runs bootstrap.
- Edit `.vscode/settings.json` freely; defaults are merged, not overwritten.
