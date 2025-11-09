{
  description = "nix homebase: layered nix2container image for Codespaces (vscode user, nixos-25.05-small)";

  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-25.05-small";
    flake-utils.url   = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, flake-utils, nix2container }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Use nix2container exactly as provided by your pin:
        # it exports a set whose functions live under `.nix2container`
        n2c = import nix2container { inherit pkgs; };

        buildImage = n2c.nix2container.buildImage;
        buildLayer = n2c.nix2container.buildLayer;

        # ---- Base tools (lean) ----
        tools = with pkgs; [
          bashInteractive coreutils findutils gnugrep gawk
          git openssh curl wget
          neovim ripgrep fd jq eza tree which gnused gnutar gzip xz
          direnv nix-direnv
          rsync rclone skopeo
          gh wrangler
          nixVersions.stable
          sudo
          iproute2 iputils traceroute mtr whois mosh lsof
          codex
        ];

        fakeNssExtended = pkgs.dockerTools.fakeNss.override {
          extraPasswdLines = [
            "vscode:x:1000:1000:VS Code:/home/vscode:/bin/bash"
          ];
          extraGroupLines = [
            "vscode:x:1000:"
            "sudo:x:27:vscode"
            "docker:x:998:vscode"
          ];
        };

        dockerCompatPaths = [
          pkgs.dockerTools.usrBinEnv
          pkgs.dockerTools.binSh
          pkgs.dockerTools.caCertificates
          fakeNssExtended
        ];

        # VS Code Machine settings for vscode (absolute store paths to nvim/direnv)
        vscodeMachineSettings = pkgs.writeText "vscode-machine-settings.json" (builtins.toJSON {
          "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
          "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
          "eslint.runtime" = "${pkgs.nodejs_22}/bin/node";
          "stylelint.stylelintPath" = "${pkgs.nodePackages_latest.stylelint}/bin/stylelint";
          "prettier.prettierPath" = "${pkgs.nodePackages_latest.prettier}/bin/prettier";
        });

        # ---- Layers ----
        baseLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-base";
            paths = tools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        compatLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-compat";
            paths = dockerCompatPaths;
            pathsToLink = [ "/bin" "/usr" "/etc" ];
          };
        };

        homeLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-home" {} ''
            mkdir -p $out/etc/sudoers.d
            mkdir -p $out/home/vscode $out/workspaces
            echo 'vscode ALL=(ALL) NOPASSWD:ALL' > $out/etc/sudoers.d/vscode
            chmod 0440 $out/etc/sudoers.d/vscode

            cat >> $out/home/vscode/.bashrc <<'EOF'
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
EOF
            cat >> $out/home/vscode/.zshrc <<'EOF'
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
EOF
          '';
          # Ownership + sane modes (no 0777) applied at layer creation
          perms = [
            { path = "copyToRoot"; regex = "^/home/vscode(/.*)?$"; uid = 1000; gid = 1000; dirMode = "0755"; fileMode = "0644"; }
            { path = "copyToRoot"; regex = "^/workspaces(/.*)?$";  uid = 1000; gid = 1000; dirMode = "0755"; fileMode = "0644"; }
          ];
        };

        vscodeLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-vscode" {} ''
            install -Dm0644 ${vscodeMachineSettings} \
              $out/home/vscode/.vscode-server/data/Machine/settings.json
          '';
          perms = [
            { path = "copyToRoot"; regex = "^/home/vscode(/.*)?$"; uid = 1000; gid = 1000; dirMode = "0755"; fileMode = "0644"; }
          ];
        };

        nixConfigLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-nix-config" {} ''
            install -Dm0644 ${pkgs.writeText "nix.conf" ''
              experimental-features = nix-command flakes
              substituters = https://cache.nixos.org/
              trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
            ''} $out/etc/nix/nix.conf
          '';
        };

      in rec {
        packages.editor-settings = vscodeMachineSettings;

        packages.homebase = buildImage {
          name   = "homebase";
          tag    = "latest";
          layers = [ compatLayer baseLayer homeLayer vscodeLayer nixConfigLayer ];

          config = {
            Env = [
              "PATH=/bin"
              "SHELL=/bin/bash"
              "EDITOR=nvim"
              "PAGER=less"
              "LC_ALL=C"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Entrypoint = [ "/bin/bash" ];
            WorkingDir = "/workspaces";
            User       = "vscode";
            Labels = {
              "org.opencontainers.image.title"       = "homebase";
              "org.opencontainers.image.description" = "Minimal Nix-based Codespaces image with nvim/direnv and sane defaults";
              "org.opencontainers.image.source"      = "https://github.com/c0decafe/homebase";
            };
          };

          # Allow nix inside the running container
          initializeNixDatabase = true;
        };

        packages.default = packages.homebase;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nixVersions.stable git jq ];
        };
      }
    );
}
