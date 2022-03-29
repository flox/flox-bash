let
  pkgs = import <nixpkgs> {};
  inherit (pkgs)
    stdenv
    coreutils
    dasel
    nix-proxy
    nixUnstable
    pandoc
    which
    jq
    ;
  inherit (pkgs.unixtools) getent;
  nix = nixUnstable;

in stdenv.mkDerivation {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ coreutils dasel getent nix ];
  postPatch = ''
    substituteInPlace flox.sh \
      --replace @@PREFIX@@ "$out" \
      --replace @@DASEL@@ ${dasel} \
      --replace @@NIX@@ ${nix} \
      --replace @@COREUTILS@@ ${coreutils} \
      --replace @@JQ@@ ${jq}/bin/jq \
      --replace getent ${getent}/bin/getent

    substituteInPlace libexec/config.sh \
      --replace @@DASEL@@ ${dasel}

    substituteInPlace etc/nix.conf \
      --replace @@PREFIX@@ "$out"
  '';

  makeFlags = [ "PREFIX=$(out)" ];
}
