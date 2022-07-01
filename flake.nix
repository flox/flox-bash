{
  nixConfig.extra-substituters = [ "s3://flox-store-public" ];
  inputs.capacitor.url = "git+ssh://git@github.com/flox/capacitor?ref=minicapacitor";
  inputs.capacitor.inputs.root.follows = "/";
  outputs =
    { capacitor,... } @ args: capacitor args (_: {
      packages = import ./default.nix;
    });
}
