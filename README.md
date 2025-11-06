# 🌀 Nix Homebase (Flakes + Neovim) — v2

- No hardcoded user: works with **vscode** or **codespace**.
- **direnv** + **neovim** preinstalled; PATH and hooks applied via `$HOME`.
- Which Key extension included.

## Import to GitHub
```bash
tar -xzf nix-homebase-flakes-v2.tar.gz
cd nix-homebase-flakes-v2
git init && git add .
git commit -m "chore: flakes-based Codespaces home base (v2: user-agnostic hooks)"
gh repo create homebase-flakes --private --source=. --remote=origin --push
```

## In Codespaces
1. Command Palette → **Codespaces: Rebuild Container**
2. First run:
   ```bash
   direnv allow
   hello
   nvim --version
   ```
