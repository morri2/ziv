{
  description = "Civ V clone environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    zig-overlay.url = "github:mitchellh/zig-overlay";

    zls.url = "github:zigtools/zls";
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
        zigpkg = zig-overlay.packages.${system}.master;
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
