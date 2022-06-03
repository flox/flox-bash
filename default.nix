{ pkgs ? import <nixpkgs>{} , revision ? "" }:
let
  inherit (pkgs)
    stdenv
    ansifilter
    cacert
    coreutils
    dasel
    fetchpatch
    findutils
    gnused
    gzip
    hostPlatform
    jq
    lib
    makeWrapper
    nixUnstable
    pandoc
    which
    writeText
    unixutils
    ;

  # bashInteractive required for read() `-i` flag.
  # Override --localedir attribute to avoid warnings on distros
  # with locale directories in different places.
  bashInteractive' = pkgs.bashInteractive.overrideAttrs (oldAttrs: {
    configureFlags = oldAttrs.configureFlags ++ [
      "--localedir=${pkgs.glibcLocales}/lib/locale/locale-archive"
    ];
  });
  inherit (pkgs.unixtools) getent;

  # Choose a smaller version of git.
  git' = pkgs.gitMinimal;

  # gh cannot find fallback versions of git without being wrapped.
  # It also needs to find ssh, codesign and a few other things, but
  # less confident about providing Nix versions of those packages.
  gh' = pkgs.gh.overrideAttrs (oldAttrs: rec {
    nativeBuildInputs = ( oldAttrs.nativeBuildInputs or [] ) ++ [ makeWrapper ];
    buildInputs = ( oldAttrs.buildInputs or [] ) ++ [ git' ];
    postInstall = ( oldAttrs.postInstall or "" ) + ''
      wrapProgram $out/bin/gh --suffix PATH : "${lib.makeBinPath(buildInputs)}"
    '';
  });

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
  buildInputs = [ ansifilter bashInteractive' cacert coreutils dasel findutils getent git' gh' gnused gzip jq nixPatched ];
  makeFlags = [
    "PREFIX=$(out)"
    "FLOXPATH=${lib.makeBinPath buildInputs}"
    "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    "FLOX_PROFILE=${floxProfile}"
  ];
}
