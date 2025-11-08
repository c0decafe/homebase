{
  description = "nix homebase — nix2container image + devshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    systems.url = "github:nix-systems/default";

    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";

    n2c.url = "github:nlewo/nix2container";
  };

  outputs = { self, nixpkgs, systems, devenv, n2c, ... }:
  let
    forAll = nixpkgs.lib.genAttrs (import systems);

    mkPkgs = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # Shared toolset used by BOTH the image and devShell (keep things DRY)
    toolset = pkgs:
      with pkgs; [
        bash coreutils findutils git curl wget
        jq skopeo
        ripgrep fd bat tmux htop
        mtr traceroute whois lsof nmap socat tcpdump mosh
        # dig/host (resilient across nixpkgs revs)
        (if pkgs ? bind && pkgs.bind ? dnsutils then pkgs.bind.dnsutils else pkgs.dnsutils)
        rclone rsync
        neovim direnv nix-direnv shellcheck shfmt stylua marksman
        nodePackages.bash-language-server
        nodePackages.typescript-language-server
        nodePackages.yaml-language-server
        nodePackages.vscode-langservers-extracted
        lua-language-server
        wrangler
        nodePackages.prettier
      ];

    # Default VS Code settings baked into the image; bootstrap merges into .vscode/settings.json
    mkEditorSettings = pkgs:
      pkgs.writeText "editor-settings.json" (builtins.toJSON {
        "direnv.path.executable" = "${pkgs.direnv}/bin/direnv";
        "vscode-neovim.neovimExecutablePaths.linux" = "${pkgs.neovim}/bin/nvim";
        "prettier.prettierPath" = "${pkgs.nodePackages.prettier}/bin/prettier";
        "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";
        "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
      });
  in {
    # ---------- Image + aux artifacts ----------
    packages = forAll (system:
      let
        pkgs   = mkPkgs system;
        # Proper nix2container interface: import the package as a function with { pkgs = ... }
        n2cPkg = n2c.packages.${system}.nix2container;
        n2cLib = import n2cPkg { inherit pkgs; };

        settings = mkEditorSettings pkgs;

        # Layers
        rootfs = n2cLib.layer {
          name = "rootfs";
          contents = toolset pkgs;
        };

        settingsLayer = n2cLib.layer {
          name = "editor-settings";
          contents = [
            (pkgs.runCommand "editor-settings-root" {} ''
              install -Dm0644 ${settings} $out/opt/homebase/editor-settings.json
            '')
          ];
        };

        image = n2cLib.buildImage {
          name = "ghcr.io/c0decafe/homebase";
          tag  = "latest";
          maxLayers = 64;
          layers = [ rootfs settingsLayer ];
          config = {
            WorkingDir = "/workspace";
            Cmd = [ "${pkgs.bash}/bin/bash" "-l" ];
            Env = [
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            Labels = {
              "org.opencontainers.image.title" = "homebase";
              "org.opencontainers.image.description" =
                "Slim Nix-powered dev container with Wrangler, skopeo, LSPs, and CLI basics";
              "org.opencontainers.image.source" = "https://github.com/c0decafe/homebase";
            };
          };
        };
      in {
        homebase = image;
        editor-settings = settings;
      }
    );

    # ---------- Push app (uses Skopeo under the hood; no Docker daemon/tarballs) ----------
    apps = forAll (system:
      let
        pkgs   = mkPkgs system;
        n2cPkg = n2c.packages.${system}.nix2container;
        n2cLib = import n2cPkg { inherit pkgs; };
      in {
        push = {
          type = "app";
          program = toString (n2cLib.copyToRegistry {
            image = self.packages.${system}.homebase;
            destination = "docker://ghcr.io/c0decafe/homebase:latest";
          });
        };
      }
    );

    # ---------- DevShell ----------
    devShells = forAll (system:
      let pkgs = mkPkgs system;
      in {
        default = devenv.lib.mkShell {
          inherit pkgs;
          modules = [{
            languages.nix.enable = true;
            packages = toolset pkgs;
          }];
        };
      }
    );

    # ---------- Formatter ----------
    formatter = forAll (system: (mkPkgs system).nixfmt-rfc-style);
  };
}
