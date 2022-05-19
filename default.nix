{ pkgs ? import <nixpkgs>{} , revision ? "" }:
let
  inherit (pkgs)
    stdenv
    ansifilter
    bashInteractive # required for read() `-i` flag
    cacert
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
    nixUnstable
    pandoc
    which
    unixutils
    ;
  inherit (pkgs.unixtools) getent;
  nixPatched = nixUnstable.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [ ./CmdProfileBuild.patch ];
  });

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.1${revision}";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ ansifilter bashInteractive cacert coreutils dasel findutils getent git gh gnused gzip jq nixPatched ];
  makeFlags = [
    "PREFIX=$(out)"
    "FLOXPATH=${lib.makeBinPath buildInputs}"
    "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
  ];
}
