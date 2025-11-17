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
        spkgs = pkgs.pkgsStatic // {
          doas = pkgs.pkgsStatic.doas.override { withPAM = false; };
        };

        # Use nix2container exactly as provided by your pin:
        # it exports a set whose functions live under `.nix2container`
        n2c = import nix2container { inherit pkgs; };

        buildImage = n2c.nix2container.buildImage;
        buildLayer = n2c.nix2container.buildLayer;
        # ---- Base tools (lean) ----
        runtimeTools = with pkgs; [
          bashInteractive coreutils findutils gnugrep gawk
          curl wget jq tree which gnused gnutar gzip xz
          procps util-linux iproute2 iputils socat
          nixVersions.stable
        ];

        containerCoreTools = with pkgs; [
          docker containerd runc iptables pigz
        ];

        buildId =
          if self ? rev && self.rev != null then builtins.substring 0 7 self.rev
          else if self ? lastModified && self.lastModified != null then builtins.toString self.lastModified
          else "dev";

        homeFlakeUri = "github:c0decafe/homebase?dir=home#default";

        homebaseSetup = pkgs.writeShellScriptBin "homebase-setup" ''
          #!/usr/bin/env bash
          set -euo pipefail
          uri="''${HOMEBASE_HOME_FLAKE_URI:-${homeFlakeUri}}"
          exec ${pkgs.nixVersions.stable}/bin/nix --extra-experimental-features 'nix-command flakes' run "$uri" -- "$@"
        '';

        sshServiceRun = pkgs.writeShellScriptBin "homebase-ssh-service" ''
          #!/usr/bin/env bash
          set -euo pipefail
          PATH=${pkgs.lib.makeBinPath [ pkgs.procps pkgs.coreutils pkgs.openssh pkgs.util-linux pkgs.curl ]}:$PATH

          log() { echo "[homebase-ssh] $*" >&2; }
          fail() { log "$1"; exit 1; }

          if [ "$(id -u)" -ne 0 ]; then
            fail "ssh service must run as root"
          fi

          mkdir -p /var/run/sshd || fail "cannot create /var/run/sshd"
          chmod 0755 /var/run/sshd || fail "cannot chmod /var/run/sshd"

          if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
            log "generating host keys"
            ${pkgs.openssh}/bin/ssh-keygen -A || fail "ssh-keygen failed"
          fi

          chmod 0600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
          chmod 0644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true

          github_user="''${GITHUB_USER:-}"
          force_keys="''${SSH_INIT_FORCE_KEYS:-}"
          vscode_home="/home/vscode"
          if [ -d "$vscode_home" ]; then
            ssh_dir="$vscode_home/.ssh"
            auth_file="$ssh_dir/authorized_keys"
            install -d -m 0700 -o 1000 -g 1000 "$ssh_dir"
            keys_base="''${GITHUB_SERVER_URL:-https://github.com}"
            keys_url="''${keys_base%/}/''${github_user}.keys"

            refresh_keys=0
            if [ -n "$github_user" ]; then
              if [ ! -f "$auth_file" ] || [ -n "$force_keys" ]; then
                refresh_keys=1
              fi
            fi

            if [ "$refresh_keys" -eq 1 ]; then
              if curl -fsSL --connect-timeout 2 --max-time 3 "$keys_url" -o "$auth_file.tmp"; then
                mv "$auth_file.tmp" "$auth_file"
                chown 1000:1000 "$auth_file"
                chmod 0600 "$auth_file"
                log "installed authorized_keys from $keys_url"
              else
                log "warning: failed to download keys from $keys_url"
                rm -f "$auth_file.tmp"
              fi
            fi

            if [ ! -f "$auth_file" ]; then
              : > "$auth_file"
            fi
            chown 1000:1000 "$auth_file"
            chmod 0600 "$auth_file"

            if [ -z "$github_user" ]; then
              log "no GITHUB_USER set; created empty authorized_keys"
            fi
          else
            log "vscode home not found at $vscode_home"
          fi

          exec ${pkgs.openssh}/bin/sshd -f ${sshConfigFile} -D
        '';

        dockerServiceRun = pkgs.writeShellScriptBin "homebase-docker-service" ''
          #!/usr/bin/env bash
          set -euo pipefail
          PATH=${pkgs.lib.makeBinPath [ pkgs.docker pkgs.containerd pkgs.runc pkgs.iptables pkgs.pigz pkgs.util-linux pkgs.procps pkgs.coreutils ]}:$PATH

          if [ "''${HOMEBASE_ENABLE_DOCKER:-1}" != "1" ]; then
            echo "[homebase-docker] disabled via HOMEBASE_ENABLE_DOCKER" >&2
            exit 0
          fi

          SOCKET=/var/run/docker.sock
          mkdir -p /var/lib/docker
          mkdir -p /var/run
          export DOCKER_RAMDISK=yes

          if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
            mount -t securityfs none /sys/kernel/security || echo "WARN: could not mount securityfs" >&2
          fi

          if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
            mkdir -p /sys/fs/cgroup/init
            xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true
            sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
          fi

          rm -f "$SOCKET"

          ${pkgs.containerd}/bin/containerd >/tmp/containerd.log 2>&1 &
          containerd_pid=$!

          dockerd_pid=""

          cleanup() {
            if [ -n "''${dockerd_pid:-}" ]; then
              kill "$dockerd_pid" >/dev/null 2>&1 || true
              wait "$dockerd_pid" >/dev/null 2>&1 || true
              dockerd_pid=""
            fi
            if [ -n "''${containerd_pid:-}" ]; then
              kill "$containerd_pid" >/dev/null 2>&1 || true
              wait "$containerd_pid" >/dev/null 2>&1 || true
              containerd_pid=""
            fi
          }

          trap cleanup EXIT INT TERM

          ${pkgs.docker}/bin/dockerd --host=unix://$SOCKET >/tmp/dockerd.log 2>&1 &
          dockerd_pid=$!

          wait "$dockerd_pid"
        '';

        homebaseEntrypoint = pkgs.writeShellScriptBin "homebase-entrypoint" ''
          #!/usr/bin/env bash
          set -euo pipefail

          mode="post-start"
          if [ "''${1:-}" = "--init" ]; then
            mode="normal"
            shift
          elif [ "''${1:-}" = "--post-start" ]; then
            mode="post-start"
            shift
          fi

          cmd=( "$@" )
          if [ "$mode" = "post-start" ]; then
            cmd=(/bin/true)
          elif [ "''${#cmd[@]}" -eq 0 ]; then
            echo "[homebase-entrypoint] setup complete, entering idle loop" >&2
            cmd=(/bin/bash -lc "sleep infinity")
          fi

          sudo /bin/homebase-setup

          ssh_pid=""
          docker_pid=""

          start_ssh() {
            sudo /bin/homebase-ssh-service &
            ssh_pid=$!
          }

          start_docker() {
            sudo /bin/homebase-docker-service &
            docker_pid=$!
          }

          start_ssh
          if [ "''${HOMEBASE_ENABLE_DOCKER:-1}" = "1" ]; then
            start_docker
          fi

          cleanup() {
            for pid in "''${ssh_pid}" "''${docker_pid}"; do
              if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
                sudo kill "$pid" >/dev/null 2>&1 || true
                wait "$pid" >/dev/null 2>&1 || true
              fi
            done
          }

          if [ "$mode" = "normal" ]; then
            trap cleanup EXIT
          else
            trap - EXIT
          fi

          if [ "$mode" = "post-start" ]; then
            echo "[homebase-entrypoint] post-start initialization complete" >&2
            exit 0
          fi

          "''${cmd[@]}"
        '';

        fakeNssExtended = pkgs.dockerTools.fakeNss.override {
          extraPasswdLines = [
            "vscode:x:1000:1000:VS Code:/home/vscode:/bin/bash"
            "sshd:x:75:75:Privilege-separated SSH:/run/sshd:/usr/sbin/nologin"
          ];
          extraGroupLines = [
            "vscode:x:1000:"
            "docker:x:998:vscode"
            "sudo:x:27:vscode"
            "sshd:x:75:"
          ];
        };

        sshRuntime = pkgs.buildEnv {
          name = "homebase-ssh-runtime";
          paths = [ pkgs.openssh ];
          pathsToLink = [ "/bin" "/libexec" ];
        };

        sshConfigFile = pkgs.writeText "homebase-sshd_config" ''
          Port 2222
          ListenAddress 0.0.0.0
          ListenAddress ::
          HostKey /etc/ssh/ssh_host_rsa_key
          HostKey /etc/ssh/ssh_host_ed25519_key
          AuthorizedKeysFile .ssh/authorized_keys
          PasswordAuthentication no
          PermitRootLogin prohibit-password
          ChallengeResponseAuthentication no
          UsePAM no
          AllowUsers vscode
          AllowTcpForwarding yes
          GatewayPorts no
          X11Forwarding no
          ClientAliveInterval 120
          ClientAliveCountMax 3
          Subsystem sftp ${pkgs.openssh}/libexec/sftp-server
        '';

        sshStateDirs = pkgs.runCommand "homebase-ssh-state" {} ''
          install -d -m 0750 $out/run/sshd
          mkdir -p $out/var/empty
          mkdir -p $out/etc/ssh
        '';

        sshLayer = buildLayer {
          copyToRoot = [ sshRuntime sshStateDirs sshServiceRun ];
        };

        gossPreFile = pkgs.writeText "homebase-goss-pre.yaml" (builtins.readFile ./goss/pre/goss.yaml);
        gossPostFile = pkgs.writeText "homebase-goss-post.yaml" (builtins.readFile ./goss/post/goss.yaml);

        gossPreWrapper = pkgs.writeShellScriptBin "goss-pre" ''
          exec /bin/goss -g ${gossPreFile} "$@"
        '';

        gossPostWrapper = pkgs.writeShellScriptBin "goss-post" ''
          exec /bin/goss -g ${gossPostFile} "$@"
        '';

        gossTools = pkgs.buildEnv {
          name = "homebase-goss-tools";
          paths = [ gossPreWrapper gossPostWrapper ];
          pathsToLink = [ "/bin" ];
        };

        gossRuntimeLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-goss-runtime";
            paths = [ pkgs.goss ];
            pathsToLink = [ "/bin" ];
          };
        };

        gossLayer = buildLayer {
          copyToRoot = [ gossTools ];
        };

        dockerCompatPaths = [
          pkgs.dockerTools.usrBinEnv
          pkgs.dockerTools.binSh
          pkgs.dockerTools.caCertificates
          fakeNssExtended
        ];

        # VS Code Machine settings for vscode (absolute store paths to nvim/direnv)
        vscodeMachineSettings = pkgs.writeText "vscode-machine-settings.json" (builtins.toJSON {
          "direnv.path.executable" = "/bin/direnv";
          "vscode-neovim.neovimExecutablePaths.linux" = "/bin/nvim";
          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "/bin/nixd";
          "eslint.runtime" = "/bin/node";
          "stylelint.stylelintPath" = "/bin/stylelint";
          "prettier.prettierPath" = "/bin/prettier";
        });

        osReleaseFile = pkgs.writeText "homebase-os-release" ''
NAME="Homebase (Nix)"
PRETTY_NAME="Homebase (Nix) Codespace Image"
ID=homebase
ID_LIKE=nixos
HOME_URL="https://github.com/c0decafe/homebase"
SUPPORT_URL="https://github.com/c0decafe/homebase/issues"
BUG_REPORT_URL="https://github.com/c0decafe/homebase/issues"
VERSION_ID="25.05"
VERSION="nixos-25.05-small"
BUILD_ID="${buildId}"
'';
        systemFiles = pkgs.runCommand "homebase-system-files" {} ''
          mkdir -p $out/etc $out/lib $out/usr/sbin
          cp ${osReleaseFile} $out/etc/os-release
        '';

        baseTools = pkgs.buildEnv {
          name = "homebase-base-tools";
          paths = runtimeTools ++ [
            homebaseSetup
            homebaseEntrypoint
          ];
          pathsToLink = [ "/bin" "/share" "/usr" "/etc" ];
        };

        baseRuntime = pkgs.runCommand "homebase-base-runtime" {} ''
          mkdir -p $out/run
          mkdir -p $out/tmp
          mkdir -p $out/var
          chmod 0755 $out/run
          chmod 1777 $out/tmp
          ln -sf /run $out/var/run
        '';

        # ---- Layers ----
        baseLayer = buildLayer {
          copyToRoot = [ baseTools baseRuntime systemFiles ];
        };

        containerLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-container";
            paths = containerCoreTools ++ [ dockerServiceRun ];
            pathsToLink = [ "/bin" "/share" "/usr" ];
          };
        };

        sudoStreamImage = pkgs.dockerTools.buildImage {
          name = "homebase-sudo-local";
          tag  = "latest";
          extraCommands = ''
            # intentionally empty
          '';
          runAsRoot = ''
            set -eux
            mkdir -p /bin /etc
            install -m 0755 ${spkgs.doas}/bin/doas /bin/doas
            ln -sf doas /bin/sudo
            cat > /etc/doas.conf <<'EOF'
permit keepenv nopass :sudo
permit root
EOF
            chown 0:0 /bin/doas
            chmod 4755 /bin/doas
            touch /.wh.nix
          '';
          config = {
            Entrypoint = [ "/bin/doas" "true" ];
            User = "0:0";
            WorkingDir = "/";
          };
        };

        sudoBaseImage = n2c.nix2container.pullImage {
          imageName = "ghcr.io/c0decafe/homebase-sudo";
          imageDigest = "sha256:85b210029ad9c7921dca1dadfa81acead46ed14f1634187ed3f514f5ab721c10";
          sha256 = "sha256-TefZUnsmc05y+qs0NEu+ADPYZCK1Fn+YvOhMGxMnsJA=";
          arch = "amd64";
        };

        compatLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-compat";
            paths = dockerCompatPaths ++ [
              (pkgs.runCommand "usr-bin-bash" {} ''
                mkdir -p $out/usr/bin
                ln -s ${pkgs.bashInteractive}/bin/bash $out/usr/bin/bash
              '')
            ];
            pathsToLink = [ "/bin" "/usr" "/etc" ];
          };
        };

      in rec {
        packages.editor-settings = vscodeMachineSettings;
        packages."homebase-sudo" = sudoStreamImage;

        packages.homebase = buildImage {
          name   = "ghcr.io/c0decafe/homebase";
          tag    = "latest";
          fromImage = sudoBaseImage;
          layers = [
            compatLayer
            baseLayer
            gossRuntimeLayer
            gossLayer
            containerLayer
            sshLayer
          ];

          config = {
            Env = [
              "PATH=/bin:/usr/local/bin"
              "EDITOR=nvim"
              "PAGER=less"
              "LC_ALL=C"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "HOMEBASE_ENABLE_DOCKER=0"
            ];
            Entrypoint = [ "/usr/local/share/ssh-init.sh" ];
            Cmd = [ "/bin/homebase-entrypoint" "--init" ];
            WorkingDir = "/workspaces";
            User       = "vscode";
            Labels = {
              "org.opencontainers.image.title"       = "homebase";
              "org.opencontainers.image.description" = "Minimal Nix-based Codespaces image with nvim/direnv and sane defaults";
              "org.opencontainers.image.source"      = "https://github.com/c0decafe/homebase";
            };
            Volumes = {
              "/nix" = {};
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
