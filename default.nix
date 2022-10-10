{pkgs, revision, ...}:
let
  inherit (pkgs)
    stdenv
    ansifilter
    bashInteractive
    coreutils
    dasel
    diffutils
    fetchpatch
    findutils
    gawk
    gh
    gnugrep
    gnused
    gum
    gzip
    hostPlatform
    jq
    lib
    libossp_uuid
    makeWrapper
    man
    nixUnstable
    pandoc
    parallel
    shfmt
    util-linuxMinimal
    which
    writeText
    unixutils
    ;

  # The getent package can be found in pkgs.unixtools.
  inherit (pkgs.unixtools) getent;

  # Choose a smaller version of git.
  git = pkgs.gitMinimal;

  nixPatched = nixUnstable.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or []) ++ [ ./nix-patches/CmdProfileBuild.patch ./nix-patches/CmdSearchAttributes.patch ];
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
    export SSL_CERT_FILE="''${SSL_CERT_FILE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}"
    export NIX_SSL_CERT_FILE="''${NIX_SSL_CERT_FILE:-$SSL_CERT_FILE}"
  '' + lib.optionalString hostPlatform.isLinux ''
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"
  '' + lib.optionalString hostPlatform.isDarwin ''
    export NIX_COREFOUNDATION_RPATH="${pkgs.darwin.CF}/Library/Frameworks"
    export PATH_LOCALE="${pkgs.darwin.locale}/share/locale"
  '');

in stdenv.mkDerivation rec {
  pname = "flox";
  version = "0.0.5${revision}";
  src = ./.;
  nativeBuildInputs = [ makeWrapper pandoc shfmt which ];
  buildInputs = [
    ansifilter bashInteractive coreutils dasel diffutils
    findutils gawk getent git gh gnugrep gnused gum gzip jq
    libossp_uuid man nixPatched parallel util-linuxMinimal
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
  '';
}
