let
  pkgs = import <nixpkgs> {};
  inherit (pkgs)
    stdenv
    ansifilter
    bashInteractive # required for read() `-i` flag
    coreutils
    dasel
    fetchpatch
    findutils
    git
    gh
    jq
    lib
    nixUnstable
    pandoc
    which
    unixutils
    ;
  inherit (pkgs.unixtools) getent;
  nix = nixUnstable.overrideAttrs (oldAttrs: {
    patches = oldAttrs.patches ++ [
      (fetchpatch {
        url = "https://github.com/flox/nix/commit/07f1513e74230e3aecf9af2fb8b578b99644565f.patch";
        sha256 = "sha256-nxzHrae0x0I2m0ub5gJObq50yzFl8vfuYzPFbEJuox0=";
      })
      # This doesn't work; insists upon an "installable" argument. So we'll have
      # to build all the flakerefs independently.
      #(fetchpatch {
      #  url = "https://github.com/flox/nix/commit/90eea2e1085c85e1fb3d9709bd9a41d8cad4c58f.patch";
      #  sha256 = "sha256-73XgxVlG06TH/gljlRivWC33MWCUF7yfwFoWDFkVCEo=";
      #})
    ];
  });

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ ansifilter bashInteractive coreutils dasel findutils getent git gh jq nix ];
  makeFlags = [ "PREFIX=$(out)" "FLOXPATH=${lib.makeBinPath buildInputs}" ];
}
