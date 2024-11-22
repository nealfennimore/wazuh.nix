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
    {
      overlays = {
        wazuh = final: prev: {
          wazuh-agent = final.callPackage ./pkgs/wazuh-agent.nix {};
        };
      };
      nixosModules = {
        wazuh-agent = import ./modules/wazuh-agent;
      };
    } // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        with pkgs;
        {
          formatter = alejandra;
          packages.wazuh-agent = pkgs.callPackage ./pkgs/wazuh-agent.nix {};
        }
    );
}
