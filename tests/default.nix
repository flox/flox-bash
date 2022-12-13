with import <nixpkgs> { };

let
  tests = stdenv.mkDerivation {
    pname = "tests";
    version = "1.2.3";
    src = ./.;
    buildPhase = ''
      mkdir $out
      touch $out/done
    '';
  };

in { inherit tests; }
