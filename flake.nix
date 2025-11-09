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
          neovim ripgrep fd jq eza tree which gnused gnutar gzip xz
          direnv nix-direnv
          rsync rclone skopeo
          wrangler
          nixVersions.stable
          docker
          docker-compose
          containerd
          runc
          pigz
          iptables
          sudo
          codex
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

        homeLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-home" {} ''
            mkdir -p $out/etc/sudoers.d
            mkdir -p $out/home/vscode $out/workspaces
            mkdir -p $out/home/vscode/.config/fish/conf.d
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
            cat > $out/home/vscode/.config/fish/conf.d/nix.fish <<'EOF'
if test -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
end
if type -q direnv
  eval (direnv hook fish)
end
EOF
            install -Dm0755 ${pkgs.writeScript "docker-init.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              export PATH=${pkgs.lib.makeBinPath [ pkgs.docker pkgs.containerd pkgs.runc pkgs.iptables pkgs.pigz ]}:$PATH

              mkdir -p /var/lib/docker
              export DOCKER_RAMDISK=yes

              if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
                mount -t securityfs none /sys/kernel/security || echo "WARN: could not mount securityfs" >&2
              fi

              if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
                mkdir -p /sys/fs/cgroup/init
                xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true
                sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
              fi

              dockerd --host=unix:///var/run/docker.sock > /tmp/dockerd.log 2>&1 &
            ''} $out/usr/local/share/docker-init.sh
          '';
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
          fromImage = n2c.nix2container.pullImage {
            imageName = "library/debian";
            imageDigest = "sha256:f522a3167fb670cc4a4518fab6d8c4227fe4bc458f4c7294832383bf284d5e78";
            sha256 = "sha256-rCwMZI6cdEmElJaJqjZ/9jCPLQJ3BPPZvPOf5dfsV4g=";
            arch = "amd64";
            os = "linux";
          };
          layers = [ baseLayer homeLayer vscodeLayer nixConfigLayer ];

          config = {
            Env = [
              "PATH=/bin"
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
