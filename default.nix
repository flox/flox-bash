let
  pkgs = import <nixpkgs> {};
  inherit (pkgs)
    stdenv
    coreutils
    dasel
    git
    jq
    lib
    nixUnstable
    pandoc
    which
    unixutils
    ;
  inherit (pkgs.unixtools) getent;
  nix = nixUnstable;

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ coreutils dasel getent git jq nix ];
  makeFlags = [ "PREFIX=$(out)" "FLOXPATH=${lib.makeBinPath buildInputs}" ];
}
