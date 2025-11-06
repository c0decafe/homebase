{
  description = "homebase-project-template";

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
            languages = {
              nix.enable = true;
            };
            packages = with pkgs; [
              git gh curl jq nodejs python3
              tmux fzf ripgrep fd bat htop
              pre-commit editorconfig-checker nixfmt-rfc-style
            ];
            scripts.hello.exec = "echo 'New project ready'";
          }];
        };
      });
  };
}
