{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in rec {
        formatter = pkgs.alejandra;
        packages = {
          wazuh-agent = pkgs.callPackage ./pkgs/wazuh-agent.nix {};
        };
        overlays = {
          wazuh = _: __: {
            inherit packages;
          };
        };
        nixosModules = {
          wazuh-agent = import ./modules/wazuh-agent;
        };
      }
    );
}
