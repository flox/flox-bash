#!/usr/bin/env bats

setup() {
  nix-build .
}

setup

@test "1 - Flox Help" {

  eval "result/bin/flox --help"
  echo $output

  [[ "$status" -eq 0 ]]
}
