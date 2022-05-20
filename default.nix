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
    hostPlatform
    jq
    lib
    nixUnstable
    pandoc
    which
    writeText
    unixutils
    ;
  inherit (pkgs.unixtools) getent;
  nixPatched = nixUnstable.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [ ./CmdProfileBuild.patch ];
  });
  # TODO: create floxProfile for other shell dialects (e.g. csh).
  floxProfile = writeText "flox.profile" (''
    # Nix packages rely on "system" files that are found in different
    # locations on different operating systems and distros, and many of
    # these packages employ environment variables for overriding the
    # default locations for such files.
    #
    # In general there are two approaches for defining these variables:
    #
    # 1. Local: whereby the application itself is built wrapped in a script
    #    which sets the required variables.
    # 2. Global: operating systems have the facility for setting system-wide
    #    environment variables which affect all processes.
    #
    # This file provides a place for defining global environment variables
    # and borrows liberally from the set of default environment variables
    # set by NixOS, the principal proving ground for Nix packaging efforts.
    export PATH=$FLOX_PATH_PREPEND:$PATH
  '' + lib.optionalString hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"
  '' + lib.optionalString hostPlatform.isDarwin ''
    export NIX_COREFOUNDATION_RPATH="${pkgs.darwin.CF}/Library/Frameworks"
    export PATH_LOCALE="${pkgs.darwin.locale}/share/locale"
  '');

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
    "FLOX_PROFILE=${floxProfile}"
  ];
}
