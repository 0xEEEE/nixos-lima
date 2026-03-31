{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils, ... }@attrs:
    let
      ful = flake-utils.lib;
      # Build a NixOS system with QCOW2 EFI image output
      mkLimaImage = system: nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = system; }
          ./lima.nix
          ./qcow-efi.nix
        ];
      };
    in
    ful.eachSystem [ ful.system.x86_64-linux ful.system.aarch64-linux ] (system: {
      packages = {
        img = (mkLimaImage system).config.system.build.qcow2;
      };
    }) //
    ful.eachSystem [ ful.system.x86_64-linux ful.system.aarch64-linux ful.system.aarch64-darwin ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            qemu
            lima
          ];
        };
      }) // {
      nixosConfigurations.nixos-aarch64 = nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = "aarch64-linux"; }
          ./lima.nix
        ];
        specialArgs = attrs;
      };
      nixosConfigurations.nixos-x86_64 = nixpkgs.lib.nixosSystem {
        modules = [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          ./lima.nix
        ];
        specialArgs = attrs;
      };

      nixosModules.lima = {
        imports = [ ./lima ];
      };
    };
}
