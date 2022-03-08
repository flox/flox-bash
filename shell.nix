{ nixpkgs ? import <nixpkgs> { } }:

nixpkgs.pkgs.mkShell {
  buildInputs = with nixpkgs.pkgs; [ dasel pandoc ];
}
