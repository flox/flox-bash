{
  inputs.nixpkgs.url = "github:flox/nixpkgs/stable";
  outputs = {
    self,
    nixpkgs,
  }: rec {
    packages = nixpkgs.lib.genAttrs ["aarch64-linux" "x86_64-linux" "x86_64-darwin" "aarch64-darwin"] (system: {
      default =
        import ./default.nix
        {
          pkgs = nixpkgs.legacyPackages.${system};
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
