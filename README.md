# 🏠 nix-homebase

**nix-homebase** is a reproducible, Nix-powered DevContainer environment for Codespaces, local development, and CI.  
It gives you a full developer “home base” image that works the same everywhere — whether you’re booting a new Codespace, running `nix develop`, or building and publishing your own image to GitHub Container Registry.

---

## ✨ Highlights

- **DevContainer-first design** – integrates fully with GitHub Codespaces features and VS Code’s DevContainer specs.  
- **Nix as a foundation** – reproducible builds, consistent toolchains, and full fallback if DevContainer features are unavailable.  
- **Single source of truth** – everything configurable via Flakes and `.devcontainer/bootstrap.sh`.  
- **Cross-cloud ready** – includes SDKs and CLIs for Cloudflare, Fly.io, GitHub, GCP, AWS, and OpenAI.  
- **Built once, runs anywhere** – prebuilt Docker image pushed automatically to  
  `ghcr.io/c0decafe/homebase:latest`.

---

## ⚙️ Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json      # DevContainer configuration (ports, features, extensions)
│   ├── bootstrap.sh           # Bootstraps nix.conf, envrc, and VSCode settings
│   └── .bootstrap.done        # Marker to skip reinitialization
├── flake.nix                  # Nix flake defining devShells and the Docker image
├── .github/workflows/
│   └── container.yml          # GitHub Action to build and push to GHCR
└── README.md
```

---

## 🧰 Tooling Included

| Category | Tools |
|-----------|-------|
| 🧱 System & Shell | `bash`, `zsh`, `tmux`, `htop`, `fd`, `ripgrep`, `bat`, `lsof`, `mtr`, `traceroute`, `whois` |
| 🌐 Networking & Sync | `curl`, `rsync`, `rclone`, `socat`, `tcpdump`, `bind` tools (`bind.dnsutils`) |
| ☁️ Cloud SDKs | `google-cloud-sdk`, `awscli2`, `flyctl`, `cloudflared`, `wrangler` |
| 🧠 AI SDKs | `openai`, `anthropic`, `google-generativeai` (via `python3.withPackages`) |
| ⚙️ Development | `nodejs`, `python3`, `nix-direnv`, `devenv`, `neovim`, `direnv` |
| 🧩 LSP / Formatters | `bash-language-server`, `pyright`, `typescript-language-server`, `yaml-language-server`, `lua-language-server`, `marksman`, `prettier`, `shellcheck`, `shfmt`, `stylua` |

---

## 🪄 DevContainer Features

- Ports exposed: **3000–3010** and **8000–8010**
- VS Code extensions preloaded:
  - `Vim`, `Neovim`, `Markdown`, `Prettier`, `ESLint`, `Stylelint`, `Cloudflare Workers`, `Docker`, `Tailwind`, `YAML`, `Volar`, `Copilot`, `Python`
- DevContainer features enabled:
  - `common-utils`, `git`, `gh`, `node`, `python`, `docker-in-docker`, `nix`

---

## 🧬 Bootstrapping

The first time a container starts, `.devcontainer/bootstrap.sh` runs automatically:

1. Creates `~/.config/nix/nix.conf` with:
   ```ini
   experimental-features = nix-command flakes
   allow-unfree = true
   ```
2. Ensures `.envrc` exists with `use flake`
3. Installs VS Code settings from `/opt/homebase/editor-settings.json`
4. Runs `nix develop` if required (based on `HOMEBASE_USE_NIX_FALLBACK`)

You can control fallback behavior with:
```bash
export HOMEBASE_USE_NIX_FALLBACK=auto|always|never
```

---

## 🧱 Building and Publishing

The image builds and pushes automatically on each push to `main`:

```yaml
docker tag nix-homebase:latest ghcr.io/c0decafe/homebase:latest
docker push ghcr.io/c0decafe/homebase:latest
```

Or manually:
```bash
nix build .#homebase-image
docker load < result
```

---

## 🚀 Usage

In Codespaces or locally:
```bash
direnv allow
nix develop
```

Or pull the prebuilt image:
```bash
docker pull ghcr.io/c0decafe/homebase:latest
```

---

## 🧭 Philosophy

> A dev environment should never surprise you.

`nix-homebase` aims for:
- Immutable setup
- Minimal bootstrap time
- Full feature parity between local, Codespaces, and CI

You can build, extend, and reuse this as your universal Nix base image for any project.

---

© 2025 **c0decafe** · MIT License
