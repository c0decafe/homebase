{
  description = "Homebase home profile";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05-small";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, devenv }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          baseUserTools = with pkgs; [
            nixVersions.stable fish tmux
            openssh mosh gh
            wrangler
          ];
          devenvPackage = devenv.packages.${system}.default;
          editorTools = with pkgs; [
            git neovim ripgrep fd direnv nix-direnv codex pandoc
            gitAndTools.git-lfs nixd nodejs_22
            nodePackages_latest.stylelint nodePackages_latest.prettier
          ];
          containerExtraTools = with pkgs; [
            docker-compose skopeo rsync rclone
          ];
          desktopTools = with pkgs; [
            firefox
          ];
          cliToolEnv = pkgs.buildEnv {
            name = "homebase-cli-tools";
            paths = baseUserTools;
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          devenvToolEnv = pkgs.buildEnv {
            name = "homebase-devenv-tools";
            paths = [ devenvPackage ];
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          editorToolEnv = pkgs.buildEnv {
            name = "homebase-editor-tools";
            paths = editorTools;
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          containerToolEnv = pkgs.buildEnv {
            name = "homebase-container-tools";
            paths = containerExtraTools;
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          desktopToolEnv = pkgs.buildEnv {
            name = "homebase-desktop-tools";
            paths = desktopTools;
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          userToolEnv = pkgs.buildEnv {
            name = "homebase-user-tools";
            paths = [ cliToolEnv devenvToolEnv editorToolEnv containerToolEnv desktopToolEnv ];
            pathsToLink = [ "/bin" "/share" "/etc" "/usr" ];
          };
          referenceRoot = "/share/homebase/home-reference.d";
          homeFiles = pkgs.runCommand "homebase-home-reference" {} ''
            root=$out${referenceRoot}
            base=$root/00-base/home/vscode
            mkdir -p "$base/.config/fish/conf.d"
            mkdir -p "$base/.config/nix"
            mkdir -p "$base/.ssh"

            install -Dm0644 ${pkgs.writeText "vscode-bashrc" ''
export PATH="$HOME/.nix-profile/bin:$PATH"
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
            ''} "$base/.bashrc"

            install -Dm0644 ${pkgs.writeText "vscode-zshrc" ''
export PATH="$HOME/.nix-profile/bin:$PATH"
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
            ''} "$base/.zshrc"

            install -Dm0644 ${pkgs.writeText "nix.fish" ''
if test -d $HOME/.nix-profile/bin
  fish_add_path $HOME/.nix-profile/bin
end
if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
end
if type -q direnv
  eval (direnv hook fish)
end
            ''} "$base/.config/fish/conf.d/nix.fish"

            install -Dm0644 ${pkgs.writeText "ssh-config" ''
Host *
  ServerAliveInterval 120
  ServerAliveCountMax 3
            ''} "$base/.ssh/config"

            install -Dm0644 ${pkgs.writeText "nix.conf" ''
experimental-features = nix-command flakes
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
            ''} "$base/.config/nix/nix.conf"

            editor=$root/10-editor/home/vscode
            mkdir -p "$editor/.vscode-server/data/Machine"
            install -Dm0644 ${pkgs.writeText "vscode-machine-settings.json" (builtins.toJSON {
              "direnv.path.executable" = "/bin/direnv";
              "vscode-neovim.neovimExecutablePaths.linux" = "/bin/nvim";
              "nix.enableLanguageServer" = true;
              "nix.serverPath" = "/bin/nixd";
              "eslint.runtime" = "/bin/node";
              "stylelint.stylelintPath" = "/bin/stylelint";
              "prettier.prettierPath" = "/bin/prettier";
              "files.trimTrailingWhitespace" = true;
              "editor.formatOnSave" = true;
              "editor.minimap.enabled" = false;
              "editor.cursorBlinking" = "solid";
              "editor.renderWhitespace" = "boundary";
              "editor.rulers" = [ 80 ];
              "editor.guides.bracketPairsHorizontal" = "active";
              "editor.lineNumbers" = "relative";
              "editor.smoothScrolling" = true;
              "vim.enableNeovim" = true;
              "vim.neovimUseWSL" = false;
              "vim.useSystemClipboard" = true;
              "vim.statusBarColorControl" = true;
              "vim.highlightedyank.enable" = true;
              "workbench.startupEditor" = "none";
              "workbench.tips.enabled" = false;
              "workbench.welcomePage.walkthroughs.openOnInstall" = false;
              "extensions.ignoreRecommendations" = true;
              "telemetry.telemetryLevel" = "off";
            })} \
              "$editor/.vscode-server/data/Machine/settings.json"
          '';

          setupScript = pkgs.writeShellScriptBin "homebase-home-setup" ''
            #!/usr/bin/env bash
            set -euo pipefail

            if [ "$(id -u)" -ne 0 ]; then
              echo "homebase-home-setup must run as root" >&2
              exit 1
            fi

            REF_ROOT=${homeFiles}${referenceRoot}
            TARGET_HOME_ROOT="''${TARGET_HOME_ROOT:-/home}"
            TARGET_USER_HOME="$TARGET_HOME_ROOT/vscode"
            TARGET_WORKSPACES="''${TARGET_WORKSPACES:-/workspaces}"
            CODE_GROUP="''${CODE_GROUP:-vscode}"
            USER_UID="''${USER_UID:-1000}"
            USER_GID="''${USER_GID:-1000}"

            ensure_user_dir() {
              local path="$1"
              install -d -m 0755 "$path"
              chown "$USER_UID:$USER_GID" "$path"
            }

            ensure_root_dir() {
              local path="$1"
              install -d -m 0755 "$path"
              chown 0:0 "$path"
            }

            ensure_code_dir() {
              local path="$1"
              install -d -m 0775 "$path"
              chown root:"$CODE_GROUP" "$path"
            }

            ensure_root_dir "$TARGET_HOME_ROOT"
            ensure_user_dir "$TARGET_USER_HOME"
            ensure_user_dir "$TARGET_WORKSPACES"
            ensure_code_dir /usr/local
            ensure_code_dir /usr/local/share

            apply_layer() {
              local layer="$1"
              local source="$layer/home"
              if [ ! -d "$source" ]; then
                return
              fi
              tar -C "$source" -cf - . | \
                tar -C "$TARGET_HOME_ROOT" --owner="$USER_UID" --group="$USER_GID" -xpf -
            }

            install_profile_links() {
              local target="$TARGET_USER_HOME/.nix-profile"
              ln -sfn ${userToolEnv} "$target"
              chown -h "$USER_UID:$USER_GID" "$target"
            }

            if [ -d "$REF_ROOT" ]; then
              shopt -s nullglob
              for layer in "$REF_ROOT"/*; do
                [ -d "$layer" ] || continue
                apply_layer "$layer"
              done
              shopt -u nullglob
            fi

            install_profile_links

            chmod 0755 "$TARGET_HOME_ROOT"
            chmod 0755 "$TARGET_USER_HOME"

            if [ -d "$TARGET_USER_HOME/.ssh" ]; then
              chmod 0700 "$TARGET_USER_HOME/.ssh"
              chmod 0600 "$TARGET_USER_HOME/.ssh"/* || true
            fi

            chown -R "$USER_UID:$USER_GID" "$TARGET_USER_HOME"
            chown "$USER_UID:$USER_GID" "$TARGET_WORKSPACES" || true
          '';
        in {
          files = homeFiles;
          cli = cliToolEnv;
          devenv = devenvToolEnv;
          editors = editorToolEnv;
          containers = containerToolEnv;
          desktop = desktopToolEnv;
          setup = setupScript;
          default = setupScript;
        });

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.setup}/bin/homebase-home-setup";
        };
      });
    };
}
