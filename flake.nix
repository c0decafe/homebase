{
  description = "nix-homebase: single nix-enabled image + flake dev env";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://cache.nixos.org/" "https://cache.cachix.org" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" "cachix.org-1:bfVvKxB9...REPLACEME..." ];
    http-connections = 50;
    accept-flake-config = true;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, systems, devenv, ... }:
  let
    forAllSystems = nixpkgs.lib.genAttrs (import systems);
  in {
    packages = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };

        settingsJson = builtins.toJSON {
          "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
          "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
          "prettier.prettierPath" = "${pkgs.nodePackages.prettier}/bin/prettier";
          "eslint.runtime" = "${pkgs.nodejs}/bin/node";
          "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";
          "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
          "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python3";
          "black-formatter.path" = "${pkgs.python3Packages.black}/bin/black";
          "isort.path" = "${pkgs.python3Packages.isort}/bin/isort";
          "ruff.path" = "${pkgs.python3Packages.ruff}/bin/ruff";
          "stylua.styluaPath" = "${pkgs.stylua}/bin/stylua";
          "markdownlint-cli.path" = "${pkgs.nodePackages.markdownlint-cli}/bin/markdownlint";
          "yaml.lint.tool" = "${pkgs.python3Packages.yamllint}/bin/yamllint";
        };

        editor-settings = pkgs.writeTextFile {
          name = "editor-settings";
          destination = "/settings.json";
          text = settingsJson;
        };

        pyAi = pkgs.python3.withPackages (ps: [ ps.openai ps.anthropic ps.google-generativeai ps.black ps.isort ps.ruff ps.yamllint ]);

        allPkgs = with pkgs; [
          bashInteractive coreutils gnused gnugrep findutils procps shadow
          git gh curl jq nodejs python3 openssl wget
          tmux fzf ripgrep fd bat tree htop
          iproute2 iputils traceroute mtr whois lsof ethtool nmap nmap-ncat socat tcpdump
          bind mosh
          pre-commit editorconfig-checker nixfmt-rfc-style
          neovim direnv nix-direnv
          shellcheck shfmt nodePackages.prettier nodePackages.eslint nodePackages.markdownlint-cli stylua
          nodePackages.bash-language-server nodePackages.pyright nodePackages.typescript-language-server nodePackages.yaml-language-server nodePackages.vscode-langservers-extracted nodePackages.dockerfile-language-server-nodejs lua-language-server
          nix cacert
          google-cloud-sdk awscli2 flyctl cloudflared nodePackages.wrangler
        ] ++ [ pyAi ] ++ (pkgs.lib.optional (pkgs ? aider-chat) pkgs.aider-chat);

        entry = pkgs.writeShellScriptBin "homebase-entry" ''
          set -e
          if [ ! -d /nix ]; then mkdir -p /nix; fi
          chown -R root:root /nix || true
          chmod 0755 /nix || true
          export USER=root
          export HOME=/root
          export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export NIX_CONFIG="experimental-features = nix-command flakes
accept-flake-config = true"
          echo "Nix ready. Template at /opt/homebase-template"
          exec bash -l
        '';

        homebase = pkgs.dockerTools.buildLayeredImage {
          name = "nix-homebase";
          tag = "latest";
          contents = allPkgs ++ [
            entry
            (pkgs.writeShellScriptBin "homebase-welcome" ''
              echo "Welcome to nix-homebase"
              echo "Copy the template:"
              echo "  cp -r /opt/homebase-template ~/new-project && cd ~/new-project"
              echo "  direnv allow && nix develop"
            '')
            (pkgs.writeTextDir "/opt/homebase-template/flake.nix" (builtins.readFile ./template/flake.nix))
            (pkgs.writeTextDir "/opt/homebase-template/.envrc" (builtins.readFile ./template/.envrc))
            (pkgs.writeTextDir "/opt/homebase-template/README.md" (builtins.readFile ./template/README.md))
          ];
          config = {
            Env = [
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "NIX_CONFIG=experimental-features = nix-command flakes
accept-flake-config = true"
              "HOME=/root"
              "PATH=/bin:/usr/bin:/sbin:/usr/sbin:${pkgs.coreutils}/bin"
            ];
            WorkingDir = "/workspace";
            Cmd = [ "${entry}/bin/homebase-entry" ];
            Labels = {
              "org.opencontainers.image.title" = "nix-homebase";
              "org.opencontainers.image.source" = "https://github.com/owner/repo";
            };
          };
        };
      in {
        editor-settings = editor-settings;
        homebase-image = homebase;
      }
    );

    devShells = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pyAi = pkgs.python3.withPackages (ps: [ ps.openai ps.anthropic ps.google-generativeai ps.black ps.isort ps.ruff ps.yamllint ]);
        corePkgs = with pkgs; [
          git gh curl jq nodejs python3 openssl wget coreutils moreutils gnused gnugrep gawk findutils
          tmux fzf ripgrep fd bat tree htop
          iproute2 iputils traceroute mtr whois lsof ethtool nmap nmap-ncat socat tcpdump
          bind mosh
          pre-commit editorconfig-checker nixfmt-rfc-style
          neovim direnv nix-direnv
          shellcheck shfmt nodePackages.prettier nodePackages.eslint nodePackages.markdownlint-cli stylua
          nodePackages.bash-language-server nodePackages.pyright nodePackages.typescript-language-server nodePackages.yaml-language-server nodePackages.vscode-langservers-extracted nodePackages.dockerfile-language-server-nodejs lua-language-server
        ] ++ [ pyAi ] ++ (pkgs.lib.optional (pkgs ? aider-chat) pkgs.aider-chat);
      in {
        default = devenv.lib.mkShell { inherit pkgs; modules = [{ languages.nix.enable = true; packages = corePkgs; }]; };
      }
    );

    formatter = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in pkgs.nixfmt-rfc-style
    );
  };
}
