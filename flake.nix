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
        ];

        # VS Code Machine settings for vscode (absolute store paths to nvim/direnv)
        vscodeMachineSettings = pkgs.writeText "vscode-machine-settings.json" (builtins.toJSON {
          "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
          "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
          "files.trimTrailingWhitespace" = true;
        });

        # ---- Layers ----
        baseLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-base";
            paths = tools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        nssLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-nss" {} ''
            mkdir -p $out/etc
            cat > $out/etc/nsswitch.conf <<'EOF'
passwd: files
group:  files
shadow: files
hosts:  files dns
networks: files
services: files
protocols: files
ethers: files
rpc: files
netgroup: files
EOF
          '';
        };

        usersLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-users" {} ''
            mkdir -p $out/etc $out/etc/sudoers.d
            mkdir -p $out/home/vscode $out/workspaces
            cat > $out/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/bash
vscode:x:1000:1000:VS Code:/home/vscode:/bin/bash
EOF
            cat > $out/etc/group <<'EOF'
root:x:0:
vscode:x:1000:
sudo:x:27:vscode
EOF
            echo 'vscode ALL=(ALL) NOPASSWD:ALL' > $out/etc/sudoers.d/vscode
            chmod 0440 $out/etc/sudoers.d/vscode
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

      in rec {
        packages.homebase = buildImage {
          name   = "homebase";
          tag    = "latest";
          layers = [ baseLayer nssLayer usersLayer vscodeLayer ];

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
