{ pkgs ? import <nixpkgs>{}, nixPatched}:
let
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
    gnused
    gzip
    jq
    lib
    pandoc
    which
    unixutils
    ;
  inherit (pkgs.unixtools) getent;
in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ ansifilter bashInteractive coreutils dasel findutils getent git gh gnused gzip jq nixPatched ];
  makeFlags = [ "PREFIX=$(out)" "FLOXPATH=${lib.makeBinPath buildInputs}" ];
}
