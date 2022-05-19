{
  nixConfig.extra-substituters = ["s3://flox-store-public"];

  inputs.nixpkgs.url = "github:flox/nixpkgs/stable";
  inputs.nix.url = "github:NixOS/nix/2.8.0";
  outputs = {
    self,
    nixpkgs,
    nix,
  }: rec {
    packages = nixpkgs.lib.genAttrs ["aarch64-linux" "x86_64-linux" "x86_64-darwin" "aarch64-darwin"] (system: rec {
      default =
        import ./default.nix
        {
          pkgs = nixpkgs.legacyPackages.${system};
          revision = "-r${toString self.revCount or "dirty"}";
        };
    });
    defaultPackage = {
      x86_64-linux = packages.x86_64-linux.default;
      aarch64-linux = packages.aarch64-linux.default;
      x86_64-darwin = packages.x86_64-darwin.default;
      aarch64-darwin = packages.aarch64-darwin.default;
    };
  };
}
