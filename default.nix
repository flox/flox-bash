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
    patches = oldAttrs.patches ++ [ ./CmdProfileImport.patch ];
  });

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ ansifilter bashInteractive coreutils dasel findutils getent git gh jq nix ];
  makeFlags = [ "PREFIX=$(out)" "FLOXPATH=${lib.makeBinPath buildInputs}" ];
}
