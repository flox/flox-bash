{
  nixConfig.extra-substituters = [ "s3://flox-store-public" ];
  outputs =
    { capacitor,... } @ args: capacitor args (_: {
      packages = import ./default.nix;
    });
}
