{
  description = "Civ V clone environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zls = {
      url = "github:zigtools/zls/0.13.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        zig-overlay.follows = "zig-overlay";
      };
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    zls,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        zigpkg = zig-overlay.packages.${system}."0.13.0";
        zlspkg = zls.packages.${system}.zls;
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
              zigpkg
              zlspkg
              libGL
              xorg.libX11
              xorg.libXcursor
              xorg.libXrandr
              xorg.libXinerama
              xorg.libXi
          ];

          hardeningDisable = ["all"];
        };

        devShell = self.devShells.${system}.default;
      }
    );
}
