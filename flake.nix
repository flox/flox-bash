{
  inputs.nixpkgs.url = "github:flox/nixpkgs/stable";
  outputs = {
    self,
    nixpkgs,
  }: {
    packages = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-darwin"] (system: {
      default =
        import ./default.nix
        {
          pkgs = nixpkgs.legacyPackages.${system};
        };
    });
  };
}
