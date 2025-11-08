# 🏠 homebase — clean, DRY, slim

Applied:
- Minimal ports: **3000, 5173, 8000**
- DevContainer features trimmed (Nix + git + common utils + Docker only)
- Dropped OpenAI/Anthropic/Google-gen libs and Python tooling
- DRY helpers (`toolset`, `mkEditorSettings`)
- Layered image (`streamLayeredImage`) with OCI labels
- Skopeo push to GHCR; concurrency + cleanup
- Bootstrap merges VS Code settings with `jq` and auto-`direnv allow`

Build/push target: `ghcr.io/c0decafe/homebase:latest`
