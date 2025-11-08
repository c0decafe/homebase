{
  description = "nix homebase: minimal nix2container image for Codespaces (vscode user, nixos-25.05-small)";

  inputs = {
    nixpkgs.url       = "github:NixOS/nixpkgs/nixos-25.05-small";
    flake-utils.url   = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, flake-utils, nix2container }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # ✅ Use nix2container *library* (not the package derivation)
        n2c = nix2container.lib.${system};

        # Minimal, practical toolset
        tools = with pkgs; [
          bashInteractive coreutils findutils gnugrep gawk
          git openssh curl wget
          neovim ripgrep fd jq eza tree which gnused gnutar gzip xz
          direnv nix-direnv
          rsync rclone skopeo
          gh wrangler
          nixVersions.stable
          sudo
          # small net diag set
          iproute2 iputils traceroute mtr whois mosh lsof
        ];

        # Flatten tools into /bin for stable absolute paths in VS Code
        rootfs = pkgs.buildEnv {
          name = "homebase-root";
          paths = tools;
          pathsToLink = [ "/bin" "/share" ];
        };

        # Simple NSS config (no fakeNss)
        nssLayer = pkgs.runCommand "homebase-nss" {} ''
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

        # vscode user (uid/gid 1000), sudo, and ownership of /workspaces
        usersLayer = pkgs.runCommand "homebase-users" {} ''
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
docker:x:999:vscode
EOF
          echo 'vscode ALL=(ALL) NOPASSWD:ALL' > $out/etc/sudoers.d/vscode
          chmod 0440 $out/etc/sudoers.d/vscode
          chmod 0755 $out/home/vscode
          chown -R 1000:1000 $out/home/vscode
          chown -R 1000:1000 $out/workspaces
        '';

        # VS Code Machine settings for *vscode* with absolute Nix paths (only what we ship)
        vscodeMachineSettings = pkgs.writeText "vscode-machine-settings.json" (builtins.toJSON {
          "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
          "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
          "files.trimTrailingWhitespace" = true;
        });

        vscodeMachineLayer = pkgs.runCommand "homebase-vscode-machine-settings" {} ''
          install -Dm0644 ${vscodeMachineSettings} \
            $out/home/vscode/.vscode-server/data/Machine/settings.json
          chown -R 1000:1000 $out/home/vscode
        '';
      in rec {
        # -------- OCI image via nix2container --------
        packages.homebase = n2c.buildImage {
          name = "homebase";
          tag  = "latest";

          copyToRoot = pkgs.buildEnv {
            name = "image-root";
            paths = [ rootfs nssLayer usersLayer vscodeMachineLayer ];
            pathsToLink = [ "/bin" "/etc" "/share" "/home" "/workspaces" ];
          };

          config = {
            Env = [
              "PATH=/bin"
              "SHELL=/bin/bash"
              "EDITOR=nvim"
              "PAGER=less"
              "LC_ALL=C"
              # unified TLS trust for git/curl/nix
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Entrypoint = [ "/bin/bash" ];
            WorkingDir = "/workspaces";
            User = "vscode";
          };

          # Let nix work in the running container
          initializeNixDatabase = true;
        };

        packages.default = packages.homebase;

        # Optional devShell for local hacking
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ nixVersions.stable git jq ];
        };
      }
    );
}
