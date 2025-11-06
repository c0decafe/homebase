{
  description = "Flakes-based Codespaces home base with Nix, devenv, Neovim, and CLI tools";

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
    devShells = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        default = devenv.lib.mkShell {
          inherit pkgs;
          modules = [{
            languages.nix.enable = true;
            packages = with pkgs; [
              git curl jq nodejs python3 direnv
              tmux fzf ripgrep fd bat tree htop neovim wget
            ];
            scripts.hello.exec  = "echo '👋 Welcome to your Nix + Neovim Codespace!'";
            scripts.update.exec = "nix flake update && git add flake.lock && git commit -m 'chore: update flake inputs' || true";
          }];
        };
      });
    formatter = forAllSystems (system:
      let pkgs = import nixpkgs { inherit system; };
      in pkgs.nixfmt-rfc-style
    );
  };
}
