{
  description = "nix-homebase: flake-only env + OCI images with template";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org/"
      "https://cache.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cachix.org-1:bfVvKxB9...REPLACEME..."
    ];
    http-connections = 50;
    warn-dirty = false;
    fallback = true;
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

        # Build-time VS Code settings with pinned store paths
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

        # Core toolset
        pyAi = pkgs.python3.withPackages (ps: [
          ps.openai ps.anthropic ps.google-generativeai
          ps.black ps.isort ps.ruff ps.yamllint
        ]);

        corePkgs = with pkgs; [
          # core
          bashInteractive coreutils gnused gnugrep findutils procps shadow
          git gh curl jq nodejs python3 openssl wget
          tmux fzf ripgrep fd bat tree htop
          # network + diagnostics
          iproute2 iputils traceroute mtr whois lsof ethtool nmap nmap-ncat socat tcpdump
          bind mosh
          # hygiene
          pre-commit editorconfig-checker nixfmt-rfc-style
          # editor/env tools
          neovim direnv nix-direnv
          # formatters/linters
          shellcheck shfmt nodePackages.prettier nodePackages.eslint
          nodePackages.markdownlint-cli stylua
          # LSPs
          nodePackages.bash-language-server
          nodePackages.pyright
          nodePackages.typescript-language-server
          nodePackages.yaml-language-server
          nodePackages.vscode-langservers-extracted # html/css/json
          nodePackages.dockerfile-language-server-nodejs
          lua-language-server
        ] ++ [ pyAi ]
          ++ (pkgs.lib.optional (pkgs ? aider-chat) pkgs.aider-chat);

        cloudPkgs = with pkgs; [
          google-cloud-sdk awscli2 flyctl cloudflared nodePackages.wrangler
        ];

        # Helper: build a layered image with /opt/homebase-template and a welcome script
        mkImage = name: extraPkgs:
          pkgs.dockerTools.buildLayeredImage {
            inherit name;
            tag = "latest";
            contents = corePkgs ++ extraPkgs ++ [
              (pkgs.writeShellScriptBin "homebase-welcome" ''
                echo "Welcome to ${name}!"
                echo "A project template is available at /opt/homebase-template"
                echo "You can copy it to start a new project:"
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
                "PATH=/bin:/usr/bin:/sbin:/usr/sbin:${pkgs.coreutils}/bin"
                "HOME=/root"
              ];
              WorkingDir = "/workspace";
              Cmd = [ "${pkgs.bashInteractive}/bin/bash" "-lc" "homebase-welcome && exec bash" ];
              Labels = {
                "org.opencontainers.image.title" = name;
                "org.opencontainers.image.source" = "https://github.com/owner/repo";
              };
            };
          };

      in {
        editor-settings = editor-settings;
        homebase-core-image  = mkImage "nix-homebase-core"  [ ];
        homebase-cloud-image = mkImage "nix-homebase-cloud" cloudPkgs;
      }
    );

    devShells = forAllSystems (system:
      let
        pkgs = import nixpkgs { inherit system; };
        pyAi = pkgs.python3.withPackages (ps: [
          ps.openai ps.anthropic ps.google-generativeai
          ps.black ps.isort ps.ruff ps.yamllint
        ]);
        corePkgs = with pkgs; [
          git gh curl jq nodejs python3 openssl wget coreutils moreutils gnused gnugrep gawk findutils
          tmux fzf ripgrep fd bat tree htop
          iproute2 iputils traceroute mtr whois lsof ethtool nmap nmap-ncat socat tcpdump
          bind mosh
          pre-commit editorconfig-checker nixfmt-rfc-style
          neovim direnv nix-direnv
          shellcheck shfmt nodePackages.prettier nodePackages.eslint nodePackages.markdownlint-cli stylua
          nodePackages.bash-language-server nodePackages.pyright nodePackages.typescript-language-server nodePackages.yaml-language-server nodePackages.vscode-langservers-extracted nodePackages.dockerfile-language-server-nodejs lua-language-server
        ] ++ [ pyAi ]
          ++ (pkgs.lib.optional (pkgs ? aider-chat) pkgs.aider-chat);

        cloudPkgs = with pkgs; [ google-cloud-sdk awscli2 flyctl cloudflared nodePackages.wrangler ];
      in {
        default = devenv.lib.mkShell { inherit pkgs; modules = [{ languages.nix.enable = true; packages = corePkgs; }]; };
        cloud   = devenv.lib.mkShell { inherit pkgs; modules = [{ languages.nix.enable = true; packages = corePkgs ++ cloudPkgs; }]; };
      }
    );

    formatter = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in pkgs.nixfmt-rfc-style
    );
  };
}
