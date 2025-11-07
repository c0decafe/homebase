{
  description = "nix-homebase (slim)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
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
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        pyAi = pkgs.python3.withPackages (ps: [ ps.openai ps.anthropic ps.google-generativeai ]);
        toolset = with pkgs; [
          bash coreutils findutils git curl wget
          ripgrep fd bat tmux htop mtr traceroute whois lsof nmap socat tcpdump bind.dnsutils
          rclone rsync
          neovim direnv nix-direnv shellcheck shfmt stylua marksman
          nodePackages.bash-language-server
          nodePackages.typescript-language-server
          nodePackages.yaml-language-server
          nodePackages.vscode-langservers-extracted
          lua-language-server
          nodePackages.wrangler
        ] ++ [ pyAi ];

        settingsJson = builtins.toJSON {
          "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
          "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
          "prettier.prettierPath" = "${pkgs.nodePackages.prettier}/bin/prettier";
          "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";
          "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
          "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python3";
          "black-formatter.path" = "${pkgs.python3Packages.black}/bin/black";
          "isort.path" = "${pkgs.python3Packages.isort}/bin/isort";
          "ruff.path" = "${pkgs.python3Packages.ruff}/bin/ruff";
        };
        editorSettings = pkgs.writeText "editor-settings.json" settingsJson;

        rootfs = pkgs.buildEnv { name = "nix-homebase-rootfs"; paths = toolset; };

        editorSettingsRoot = pkgs.runCommand "editor-settings-root" { } ''
          install -Dm0644 ${editorSettings} $out/opt/homebase/editor-settings.json
        '';

        image = pkgs.dockerTools.streamLayeredImage {
          name = "nix-homebase";
          tag  = "latest";
          contents = [ rootfs editorSettingsRoot ];
          config = {
            WorkingDir = "/workspace";
            Cmd = [ "${pkgs.bash}/bin/bash" "-l" ];
            Env = [ "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
          };
        };
      in {
        homebase-image = image;
        editor-settings = editorSettings;
      }
    );

    devShells = forAllSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        pyAi = pkgs.python3.withPackages (ps: [ ps.openai ps.anthropic ps.google-generativeai ]);
        toolset = with pkgs; [
          bash coreutils findutils git curl wget
          ripgrep fd bat tmux htop mtr traceroute whois lsof nmap socat tcpdump bind.dnsutils
          rclone rsync
          neovim direnv nix-direnv shellcheck shfmt stylua marksman
          nodePackages.bash-language-server
          nodePackages.typescript-language-server
          nodePackages.yaml-language-server
          nodePackages.vscode-langservers-extracted
          lua-language-server
          nodePackages.wrangler
        ] ++ [ pyAi ];
      in {
        default = devenv.lib.mkShell { inherit pkgs; modules = [{ languages.nix.enable = true; packages = toolset; }]; };
      }
    );

    formatter = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
      in pkgs.nixfmt-rfc-style
    );
  };
}
