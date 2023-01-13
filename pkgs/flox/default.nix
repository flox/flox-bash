{ self
, stdenv
, inputs
, getRev ? inputs.flox-floxpkgs.lib.getRev

, ansifilter
, bashInteractive
, coreutils
, curl
, dasel
, diffutils
, entr
, expect
, findutils
, gawk
, gh
, gnugrep
, gnused
, gnutar
, gum
, gzip
, hostPlatform
, jq
, less # Required by man, believe it or not  :-(
, lib
, libossp_uuid
, makeWrapper
, man
, nix-editor
, nixStable
, pandoc
, parallel
, pkgs
, shfmt
, util-linuxMinimal
, which
, writeText
}:

let

  # The getent package can be found in pkgs.unixtools.
  inherit (pkgs.unixtools) getent;

  # Choose a smaller version of git.
  git = pkgs.gitMinimal;

  nixPatched = nixStable.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [
      ./nix-patches/CmdProfileBuild.patch
      ./nix-patches/CmdSearchAttributes.patch
      ./nix-patches/update-profile-list-warning.patch
      ./nix-patches/multiple-github-tokens.patch
      ./nix-patches/curl_flox_version.patch
      ./nix-patches/no-default-prefixes-hash.patch
    ];
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
    _flox_activate_verbose=/dev/null
    if [ -n "$FLOX_ACTIVATE_VERBOSE" ]; then
        _flox_activate_verbose=/dev/stderr
        echo "prepending \"$FLOX_PATH_PREPEND\" to \$PATH" 1>&2
        echo "prepending \"$FLOX_XDG_DATA_DIRS_PREPEND\" to \$XDG_DATA_DIRS" 1>&2
    fi
    export PATH="$FLOX_PATH_PREPEND":"$PATH"
    export XDG_DATA_DIRS="$FLOX_XDG_DATA_DIRS_PREPEND":"$XDG_DATA_DIRS"
    source <(${coreutils}/bin/tee $_flox_activate_verbose <<EOF
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
    export NIX_SSL_CERT_FILE="''${NIX_SSL_CERT_FILE:-$SSL_CERT_FILE}"
  '' + lib.optionalString hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"
  '' + lib.optionalString hostPlatform.isDarwin ''
    export NIX_COREFOUNDATION_RPATH="${pkgs.darwin.CF}/Library/Frameworks"
    export PATH_LOCALE="${pkgs.darwin.locale}/share/locale"
  '' + ''
    if [ -n "$FLOX_BASH_INIT_SCRIPT" ]; then
        . "$FLOX_BASH_INIT_SCRIPT"
    fi
    EOF
    )
    unset FLOX_PATH_PREPEND FLOX_ACTIVATE_VERBOSE FLOX_BASH_INIT_SCRIPT
  '');

  bats = pkgs.bats.withLibraries (p: [ p.bats-support p.bats-assert ]);

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.9-${getRev src}";
  src = self;
  nativeBuildInputs = [ bats entr expect makeWrapper pandoc shfmt which ];
  buildInputs = [
    ansifilter bashInteractive coreutils curl dasel diffutils
    findutils gawk getent git gh gnugrep gnused gnutar gum gzip jq
    less libossp_uuid man nixPatched nix-editor parallel
    util-linuxMinimal
  ];
  makeFlags = [
    "PREFIX=$(out)"
    "VERSION=${version}"
    "FLOXPATH=$(out)/libexec/flox:${lib.makeBinPath buildInputs}"
    "NIXPKGS_CACERT_BUNDLE_CRT=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    "FLOX_PROFILE=${floxProfile}"
  ] ++ lib.optionals hostPlatform.isLinux [
    "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
  ] ++ lib.optionals hostPlatform.isDarwin [
    "NIX_COREFOUNDATION_RPATH=${pkgs.darwin.CF}/Library/Frameworks"
    "PATH_LOCALE=${pkgs.darwin.locale}/share/locale"
  ];
  postInstall = ''
    # Some programs cannot function without git, ssh, and other
    # programs in their PATH. We have gone gone to great lengths
    # to avoid leaking /nix/store paths into PATH, so in order
    # to correct for these shortcomings we need to arrange for
    # flox to invoke our wrapped versions of these programs in
    # preference to the ones straight from nixpkgs.
    #
    # Note that we must prefix the path to avoid prompting the
    # user to download XCode at runtime on MacOS.
    #
    # TODO: replace "--argv0 '$0'" with "--inherit-argv0" once Nix
    #       version advances to the version that supports it.
    #
    mkdir -p $out/libexec
    makeWrapper ${nixPatched}/bin/nix $out/libexec/flox/nix --argv0 '$0' \
      --prefix PATH : "${lib.makeBinPath([ git ])}"
    makeWrapper ${gh}/bin/gh $out/libexec/flox/gh --argv0 '$0' \
      --prefix PATH : "${lib.makeBinPath([ git ])}"

    # Rewrite /bin/sh to the full path of bashInteractive.
    # Use --host to resolve using the runtime path.
    patchShebangs --host $out/libexec/flox/flox
  '';

  doInstallCheck = ! stdenv.isDarwin;
  postInstallCheck = ''
    # Quick unit test to ensure that we are not using any "naked"
    # commands within our scripts. Doesn't hit all codepaths but
    # catches most of them.
    env -i USER=`id -un` HOME=$PWD $out/bin/flox help > /dev/null
  '';
}
