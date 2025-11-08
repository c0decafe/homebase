{
  description = "homebase — clean & DRY (with skopeo)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, systems, devenv, ... }:
  let
    forAll = nixpkgs.lib.genAttrs (import systems);
    mkPkgs = system: import nixpkgs { inherit system; config.allowUnfree = true; };

    toolset = pkgs: with pkgs; [
      bash coreutils findutils git curl wget
      jq skopeo
      ripgrep fd bat tmux htop mtr traceroute whois lsof nmap socat tcpdump bind.dnsutils
      rclone rsync
      neovim direnv nix-direnv shellcheck shfmt stylua marksman
      nodePackages.bash-language-server
      nodePackages.typescript-language-server
      nodePackages.yaml-language-server
      nodePackages.vscode-langservers-extracted
      lua-language-server
      nodePackages.wrangler
    ];

    mkEditorSettings = pkgs:
      pkgs.writeText "editor-settings.json" (builtins.toJSON {
        "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
        "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
        "prettier.prettierPath" = "${pkgs.nodePackages.prettier}/bin/prettier";
        "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";
        "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
      });
  in {
    packages = forAll (system:
      let
        pkgs = mkPkgs system;
        settings = mkEditorSettings pkgs;
        rootfs = pkgs.buildEnv { name = "homebase-rootfs"; paths = toolset pkgs; };
        settingsRoot = pkgs.runCommand "editor-settings-root" {} ''
          install -Dm0644 ${settings} $out/opt/homebase/editor-settings.json
        '';
        image = pkgs.dockerTools.streamLayeredImage {
          name = "homebase";
          tag  = "latest";
          contents = [ rootfs settingsRoot ];
          config = {
            WorkingDir = "/workspace";
            Cmd = [ "${pkgs.bash}/bin/bash" "-l" ];
            Env = [ "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
            Labels = {
              "org.opencontainers.image.title" = "homebase";
              "org.opencontainers.image.description" = "Slim Nix-powered dev container with Wrangler, skopeo and LSPs";
              "org.opencontainers.image.source" = "https://github.com/c0decafe/homebase";
            };
          };
        };
      in { homebase = image; editor-settings = settings; }
    );

    devShells = forAll (system:
      let pkgs = mkPkgs system;
      in {
        default = devenv.lib.mkShell { inherit pkgs; modules = [{ languages.nix.enable = true; packages = toolset pkgs; }]; };
      }
    );

    formatter = forAll (system: (mkPkgs system).nixfmt-rfc-style);
  };
}
