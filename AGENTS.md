# Repository Guidelines

## Project Structure & Module Organization
- `flake.nix` defines the layered docker/nix2container image, custom packages, and build logic.
- `.github/workflows/` contains CI pipelines: `container.yml` builds & pushes images; `smoke.yml` runs ssh smoke tests.
- Runtime assets (scripts, configs) are created on-the-fly via `buildLayer`/`dockerTools` in `flake.nix`; no separate `src/` tree exists.
- Generated images publish to `ghcr.io/c0decafe/homebase` (full stack) and `ghcr.io/c0decafe/homebase-sudo` (bootstrap layer).
- When introducing a new docker layer in `flake.nix`, always remember to add it to the `layers = [ ... ]` list so it becomes part of the final image.
- Avoid ad-hoc builders (e.g., `runCommand` with inline shell) whenever possible; prefer pure helpers like `pkgs.linkFarm` or structured derivations so outputs stay deterministic.

## Build, Test, and Development Commands
- `nix flake check -L` – validates the flake, formatting, and build graph; run before opening PRs.
- `nix build .#homebase` – builds the layered image JSON/tarball locally.
- `nix run .#homebase.copyToRegistry -- docker://ghcr.io/<owner>/homebase:<tag>` – pushes a built image to GHCR via skopeo.
- `docker run --rm ghcr.io/c0decafe/homebase:latest bash -lc "sudo -n /etc/init.d/init.sh"` – quick end-to-end smoke test.

## Coding Style & Naming Conventions
- Nix code: two-space indentation, trailing commas, prefer `let … in` blocks with descriptive names (`baseLayer`, `sshLayer`).
- Bash scripts created via `pkgs.writeScript` must use `#!/usr/bin/env bash`, `set -euo pipefail`, and log to stderr.
- Commit messages follow short imperative sentences (e.g., “Add doas PAM stack”, “Tag sudo base image before pushing”).

## Testing Guidelines
- After every change, double-check that the relevant tests cover the behavior and update them when needed.
- Rely on `nix flake check` for structural/tests; add targeted scripts when changing ssh or docker init flows.
- CI smoke test (`.github/workflows/smoke.yml`) runs `sudo -n /etc/init.d/init.sh`; keep ssh changes compatible.
- When touching sshd or docker layers, manually run the docker smoke command above before pushing.

## Commit & Pull Request Guidelines
- Reference related issues in PR descriptions; summarize image-layer changes and testing evidence (logs/commands).
- Include new hashes/digests when fixed-output derivations change (mention `nix`-reported value in the description).
- Screenshots are unnecessary; paste command outputs or GHCR links instead.
- Ensure PRs pass both `container` and `ssh-smoke-test` workflows; re-run if rate-limited after adding `access-tokens` config.
- The Codex agent may run any git command (push only on request) and other safe tooling like `gh` or `curl` when needed.

## Security & Configuration Tips
- Never embed real secrets in `flake.nix`; reference `${{ secrets.* }}` in workflows instead.
- Keep `/run/sshd` perms aligned with the fake NSS user (UID/GID 75) and avoid shipping PAM when `doas` is static.
- When updating GHCR digests, temporarily set `sha256 = pkgs.lib.fakeSha256;` to capture the new hash from CI.

## Reference Docs
- `docs/gossfile.md` – local copy of the upstream gossfile spec from https://github.com/goss-org/goss; keep it in sync when the source doc changes.
