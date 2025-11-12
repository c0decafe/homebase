# homebase

`homebase` is a reproducible workstation image built with
[nix2container](https://github.com/nlewo/nix2container) and published to
`ghcr.io/c0decafe/homebase:latest`. It doubles as the development environment for this repo and
as the artifact that CI pushes to GitHub Container Registry.

## Highlights

- **All-Nix workflow** - `flake.nix` defines the layered image, dev shell, and VS Code machine
  settings, so every build is hermetic and auditable.
- **Fast container publishing** - `nix2container` produces an OCI image description that `skopeo`
  uploads directly; no Docker daemon, no tar streams.
- **Devcontainer-first** - `.devcontainer/devcontainer.json` points straight at the published image,
  so the environment that launches in Codespaces matches what CI pushes upstream; only Docker-in-Docker is added at runtime.
- **Editor-ready settings** - `nix build .#editor-settings` emits the exact VS Code configuration
  used inside the image, including absolute store paths for direnv/neovim integrations.

## Repository layout

| Path | Purpose |
|------|---------|
| `flake.nix` | Defines the image (`packages.homebase`), dev shell, and helper outputs. |
| `.github/workflows/container.yml` | GitHub Actions workflow that builds and pushes the image on `main`. |
| `.devcontainer/devcontainer.json` | Devcontainer manifest pointing to the published image (adds Docker-in-Docker when needed). |

## Quick start

### Codespaces / Dev Containers

1. Open the repo in GitHub Codespaces or VS Code using the Dev Containers extension.
2. The environment launches `ghcr.io/c0decafe/homebase:latest`.
3. The image already ships with:
   - system-wide `/etc/nix/nix.conf` enabling `nix-command flakes`,
   - direnv hooks baked into the default bash/zsh/fish configs (fish also sources the Nix profile),
   - `/home/vscode/.vscode-server/.../settings.json` pointing at exact Nix store paths for helper binaries.
   - Docker Engine + containerd installed via Nix; the devcontainer `postStartCommand` launches `dockerd` automatically.
4. Open a terminal and start working; nix, direnv hooks, and editor paths are already configured. Run `nix develop` manually only when you need the dev shell.

### Local Nix workflow

```bash
# Enter the lightweight dev shell (git + nix)
nix develop

# Build the container image
nix build -L .#homebase

# Push to GHCR after logging in (requires GH write access)
nix run .#homebase.copyTo -- docker://ghcr.io/c0decafe/homebase:latest
```

Other useful outputs:

```bash
# Regenerate the VS Code machine configuration JSON
nix build .#editor-settings
```

### Smoke test

We keep container regressions in [`./goss.yaml`](./goss.yaml) and run them with
[dgoss](https://github.com/goss-org/goss/blob/master/extras/dgoss/README.md):

```bash
curl -L https://github.com/goss-org/goss/releases/download/v0.4.4/goss-linux-amd64 -o goss
curl -L https://github.com/goss-org/goss/releases/download/v0.4.4/dgoss -o dgoss
chmod +x goss dgoss

export GOSS_FILES_PATH=$PWD
export DGOSS_RUN_OPTS="--env GITHUB_USER=<your-gh-user>"
sudo ./dgoss run ghcr.io/c0decafe/homebase:latest
```

CI runs the same suite after publishing. For quick ad-hoc checks without dgoss you can still use
`./scripts/smoke.sh <image>`, which executes the same commands sequentially.

### ChatGPT / Codex integration

- The devcontainer installs the official `openai.chatgpt` extension.
- Set `OPENAI_API_KEY` as a GitHub Codespaces secret (or locally in your shell) before launching; the extension will prompt once if it needs a token.
- Inside VS Code run “OpenAI: Set API Key” once; the extension will reuse the stored token afterward.

## Image contents

Defined in `flake.nix`:

- **Base tools** (`tools` list) - bash, coreutils, git, nix, ripgrep, fd, jq, neovim, skopeo,
  wrangler, network debuggers, etc.
- **Base layers** - built entirely from Nix (no Debian base image) with a compatibility layer that injects `/etc/passwd`, `/bin/sh`, and CA certificates so the environment stands on its own.
- **Docker runtime** - Docker Engine, containerd, runc, and friends are provided via Nix and started automatically when the container boots.
- **Home/user layer** - ensures the `vscode` user exists with sudo privileges, fish/direnv hooks, and ready-to-use workspace directories.
- **VS Code layer** - drops the machine settings JSON under
  `/home/vscode/.vscode-server/data/Machine/settings.json` with correct store paths for direnv and
  neovim.
- **Environment defaults** - PATH set to `/bin`, `EDITOR=nvim`, CA certificates for git/curl/nix,
  and `initializeNixDatabase = true` so `nix` works inside the container.
- **Global nix config** - `/etc/nix/nix.conf` enables flakes everywhere (Codespaces, terminals, scripts) without per-user tweaks.

To add tools, extend the `tools` list or include additional layers via `buildLayer`.

## Continuous delivery

Workflow: `.github/workflows/container.yml`

1. Install nix via `cachix/install-nix-action`.
2. Enable flake support in `~/.config/nix/nix.conf`.
3. `nix build -L --no-write-lock-file .#homebase`
4. Log into GHCR with the Actions token.
5. Export `REGISTRY_AUTH_FILE` for skopeo.
6. Push via `nix run .#homebase.copyTo -- docker://ghcr.io/c0decafe/homebase:latest`.
7. Always print disk usage for debugging.

Triggers: push to `main` or manual `workflow_dispatch`.

## Troubleshooting

- **Copy step fails with "Exactly two arguments expected"** - ensure the workflow (or your local
  command) includes `--` when passing arguments to `nix run .#homebase.copyTo`.
- **Direnv not loading** - the shell already sources direnv; if you need extra rules, create your own `.envrc` and run `direnv allow` manually.
- **Need Docker daemon access** - use `nix run .#homebase.copyToDockerDaemon` if you must import
  the image into Docker instead of pushing to a registry.

## Contributing

1. Make your changes.
2. Format/check as needed inside `nix develop`.
3. `git commit` and push.
4. Run `gh workflow run container` (optional) to ensure CI passes before opening a PR.

Please keep the flake outputs (image, editor settings, dev shell) in sync so Codespaces and CI stay
aligned.
