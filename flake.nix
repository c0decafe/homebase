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
        runtimeTools = with pkgs; [
          bashInteractive coreutils findutils gnugrep gawk
          curl wget jq tree which gnused gnutar gzip xz pigz iptables
        ];

        editorTools = with pkgs; [
          git neovim ripgrep fd direnv nix-direnv fish codex pandoc
          gitAndTools.git-lfs
        ];

        containerTools = with pkgs; [
          docker docker-compose containerd runc skopeo rsync rclone
          nixVersions.stable
        ];

        desktopTools = with pkgs; [
          firefox x11vnc novnc xorg.xvfb
        ];

        tools = runtimeTools ++ editorTools ++ containerTools ++ desktopTools;

        fakeNssExtended = pkgs.dockerTools.fakeNss.override {
          extraPasswdLines = [
            "vscode:x:1000:1000:VS Code:/home/vscode:${pkgs.fish}/bin/fish"
          ];
          extraGroupLines = [
            "vscode:x:1000:"
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
            paths = runtimeTools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        editorLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-editor";
            paths = editorTools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        containerLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-container";
            paths = containerTools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        desktopLayer = buildLayer {
          copyToRoot = pkgs.buildEnv {
            name = "homebase-desktop";
            paths = desktopTools;
            pathsToLink = [ "/bin" "/share" ];
          };
        };

        sudoLayer = buildLayer {
          copyToRoot = pkgs.runCommand "homebase-sudo" { buildInputs = [ pkgs.fakeroot ]; } ''
            mkdir -p $out/bin
            fakeroot -- sh -c 'install -m4755 ${pkgs.sudo}/bin/sudo $out/bin/sudo'
          '';
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
            mkdir -p $out/etc/ssh
            mkdir -p $out/etc/pam.d
            mkdir -p $out/etc
            mkdir -p $out/usr/local/bin
            mkdir -p $out/usr/local/share
            mkdir -p $out/lib
            mkdir -p $out/usr/sbin
            mkdir -p $out/tmp
            mkdir -p $out/var/run
            mkdir -p $out/var/empty
            mkdir -p $out/home/vscode $out/workspaces
            mkdir -p $out/home/vscode/.config/fish/conf.d
            echo 'vscode ALL=(ALL) NOPASSWD:ALL' > $out/etc/sudoers.d/vscode
            chmod 0440 $out/etc/sudoers.d/vscode

            chmod 1777 $out/tmp
            chmod 0755 $out/var/run
            chmod 0755 $out/var/empty

            ln -sf ${pkgs.pam}/lib/security $out/lib/security
            install -Dm0644 ${pkgs.writeText "sudo.pam" ''
auth       sufficient pam_permit.so
account    sufficient pam_permit.so
session    optional pam_permit.so
            ''} $out/etc/pam.d/sudo

            install -Dm0644 ${pkgs.writeText "sshd.pam" ''
auth       sufficient pam_permit.so
account    sufficient pam_permit.so
session    optional pam_permit.so
            ''} $out/etc/pam.d/sshd

            cat > $out/etc/os-release <<EOF
NAME="Homebase (Nix)"
PRETTY_NAME="Homebase (Nix) Codespace Image"
ID=homebase
ID_LIKE=nixos
HOME_URL="https://github.com/c0decafe/homebase"
SUPPORT_URL="https://github.com/c0decafe/homebase/issues"
BUG_REPORT_URL="https://github.com/c0decafe/homebase/issues"
VERSION_ID="25.05"
VERSION="nixos-25.05-small"
BUILD_ID="${self.rev or "dirty"}"
EOF

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
            install -Dm0644 ${pkgs.writeText "sshd_config" ''
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
            ''} $out/etc/ssh/sshd_config

            install -Dm0755 ${pkgs.writeScript "docker-init.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              export PATH=${pkgs.lib.makeBinPath [ pkgs.docker pkgs.containerd pkgs.runc pkgs.iptables pkgs.pigz pkgs.util-linux pkgs.procps pkgs.coreutils ]}:$PATH
              SOCKET=/var/run/docker.sock

              mkdir -p /var/lib/docker
              mkdir -p /var/run
              export DOCKER_RAMDISK=yes

              if pgrep -x dockerd >/dev/null 2>&1; then
                pkill dockerd || true
              fi
              if pgrep -x containerd >/dev/null 2>&1; then
                pkill containerd || true
              fi

              if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
                mount -t securityfs none /sys/kernel/security || echo "WARN: could not mount securityfs" >&2
              fi

              if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
                mkdir -p /sys/fs/cgroup/init
                xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs || true
                sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
              fi

              if pgrep -x dockerd >/dev/null; then
                echo "dockerd already running" >&2
                exit 0
              fi

              if pgrep -x containerd >/dev/null; then
                pkill containerd || true
              fi

              rm -f "$SOCKET"

              ${pkgs.containerd}/bin/containerd >/tmp/containerd.log 2>&1 &
              sleep 2

              ${pkgs.docker}/bin/dockerd --host=unix://$SOCKET > /tmp/dockerd.log 2>&1 &

              for i in $(seq 1 30); do
                if ${pkgs.docker}/bin/docker info >/dev/null 2>&1; then
                  chown root:docker "$SOCKET" || true
                  chmod 660 "$SOCKET" || true
                  exit 0
                fi
                sleep 1
              done

              echo "dockerd failed to start" >&2
              exit 1
            ''} $out/usr/local/share/docker-init.sh

            install -Dm0755 ${pkgs.writeScript "ssh-service.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              export PATH=${pkgs.lib.makeBinPath [ pkgs.procps pkgs.coreutils pkgs.openssh pkgs.util-linux ]}:$PATH

              ensure_keys() {
                if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
                  ${pkgs.openssh}/bin/ssh-keygen -A
                fi

                chmod 0600 /etc/ssh/ssh_host_*_key || true
                chmod 0644 /etc/ssh/ssh_host_*_key.pub || true
              }

              start() {
                mkdir -p /var/run/sshd
                chmod 0755 /var/run/sshd

                ensure_keys

                if pgrep -x sshd >/dev/null 2>&1; then
                  echo "sshd already running"
                  return 0
                fi

                ${pkgs.openssh}/bin/sshd -f /etc/ssh/sshd_config -D &
                ln -sf ${pkgs.openssh}/bin/sshd /usr/sbin/sshd || true
              }

              stop() {
                pkill sshd || true
              }

              case "$1" in
                start|"")
                  start
                  ;;
                stop)
                  stop
                  ;;
                restart)
                  stop
                  start
                  ;;
                status)
                  if pgrep -x sshd >/dev/null 2>&1; then
                    exit 0
                  else
                    exit 1
                  fi
                  ;;
                *)
                  echo "Usage: $0 {start|stop|restart|status}" >&2
                  exit 1
                  ;;
              esac
            ''} $out/etc/init.d/ssh

            install -Dm0755 ${pkgs.writeScript "ssh-init.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              sudoIf() {
                if [ "$(id -u)" -ne 0 ]; then
                  sudo "$@"
                else
                  "$@"
                fi
              }

              sudoIf /etc/init.d/ssh start

              set +e
              if [ "$#" -gt 0 ]; then
                exec "$@"
              fi
            ''} $out/usr/local/share/ssh-init.sh

            install -Dm0755 ${pkgs.writeScript "dev-startup.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              if [ -x /usr/local/share/docker-init.sh ]; then
                /usr/local/share/docker-init.sh || true
              fi
            ''} $out/usr/local/bin/dev-startup.sh

            install -Dm0755 ${pkgs.writeScript "desktop-init.sh" ''
              #!/usr/bin/env bash
              set -euo pipefail

              export PATH=${pkgs.lib.makeBinPath [ pkgs.firefox pkgs.x11vnc pkgs.novnc pkgs.xorg.xvfb pkgs.busybox pkgs.python3Packages.websockify ]}:$PATH

              XVFB_DISPLAY="${DISPLAY:-:99}"
              XVFB_W="1280"
              XVFB_H="768"
              XVFB_DPI="96"
              NOVNC_PORT="''${NOVNC_PORT:-6080}"

              if pgrep -f "Xvfb $XVFB_DISPLAY" >/dev/null; then
                echo "Browser session already running on display $XVFB_DISPLAY" >&2
                exit 0
              fi

              Xvfb "$XVFB_DISPLAY" -screen 0 ''${XVFB_W}x''${XVFB_H}x24 -dpi "$XVFB_DPI" >/tmp/xvfb.log 2>&1 &
              XVFB_PID=$!
              sleep 1

              DISPLAY="$XVFB_DISPLAY" firefox >/tmp/firefox.log 2>&1 &

              x11vnc -display "$XVFB_DISPLAY" -localhost -nopw -forever -shared -bg >/tmp/x11vnc.log 2>&1

              if command -v websockify >/dev/null 2>&1; then
                websockify --web ${pkgs.novnc}/share/novnc $NOVNC_PORT 127.0.0.1:5900 >/tmp/websockify.log 2>&1 &
              else
                echo "websockify not available in PATH" >&2
                kill $XVFB_PID || true
                exit 1
              fi

              wait $XVFB_PID
            ''} $out/usr/local/share/desktop-init.sh
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
          layers = [
            compatLayer
            baseLayer
            editorLayer
            containerLayer
            desktopLayer
            sudoLayer
            homeLayer
            vscodeLayer
            nixConfigLayer
          ];

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
