# nix-homebase

A flake-based developer home for Codespaces and reusable container images. Everything is provided by Nix; no system package installs.

## Features
- Flake-only dev environment (`nix develop`)
- VS Code settings generated from the flake with hardpinned tool paths
- OCI images (core & cloud) preloaded with tools and a `/opt/homebase-template` starter
- Port forwarding: 3000–3010 and 8000–8010

## Codespaces
- Open the repo → Rebuild container
- First run:
  ```bash
  direnv allow
  nix develop
  ```

## Build & Use Images Locally
```bash
nix build .#homebase-core-image
docker load < result
docker run -it --rm -v $PWD:/workspace nix-homebase-core:latest
# inside container:
homebase-welcome
```

## Template
A generic devenv-enabled flake lives in `/opt/homebase-template` inside the images.
Copy it to start a new project:
```bash
cp -r /opt/homebase-template ~/new-project
cd ~/new-project
direnv allow && nix develop
```

## Cloud shell
```bash
nix develop .#cloud
```

## GitHub Actions (GHCR)
Workflow builds and pushes:
- `ghcr.io/<owner>/<repo>:<tag>-core`
- `ghcr.io/<owner>/<repo>:<tag>-cloud`
