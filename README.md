# 🌀 mnm Homebase 

Codespaces “home base” built with **Nix flakes**, **devenv.sh**, **direnv**, and **Neovim**.

## Quick start
1) Create a new repo on GitHub (private).
2) Upload this tarball’s contents or push via git (see below).
3) In Codespaces: Command Palette → **Codespaces: Rebuild Container**.
4) First run:
   ```bash
   direnv allow
   hello
   ```
5) Update flake inputs:
   ```bash
   update
   ```

## Push via CLI
```bash
tar -xzf nix-homebase-flakes.tar.gz
cd nix-homebase-flakes
git init && git add .
git commit -m "chore: flakes-based Codespaces home base (Nix + devenv + Neovim)"
gh repo create homebase-flakes --private --source=. --remote=origin --push
```
