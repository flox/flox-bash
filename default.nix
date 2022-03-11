let
  pkgs = import <nixpkgs> {};
  inherit (pkgs)
    stdenv
    coreutils
    dasel
    glibc
    nix-proxy
    nixUnstable
    pandoc
    which;
  nix = nixUnstable;

in stdenv.mkDerivation {
  pname = "flox";
  version = "0.0.1";
  src = ./.;
  nativeBuildInputs = [ pandoc which ];
  buildInputs = [ coreutils dasel glibc.bin nix ];
  postPatch = ''
    substituteInPlace flox.sh \
      --replace @@PREFIX@@ "$out" \
      --replace @@DASEL@@ ${dasel} \
      --replace @@NIX@@ ${nix} \
      --replace @@COREUTILS@@ ${coreutils} \
      --replace getent ${glibc.bin}/bin/getent

    substituteInPlace libexec/config.sh \
      --replace @@DASEL@@ ${dasel}

    substituteInPlace etc/nix.conf \
      --replace @@PREFIX@@ "$out"
  '';

  makeFlags = [ "PREFIX=$(out)" ];
}
