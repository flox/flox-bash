#!/usr/bin/env bats

setup() {
  nix-build .
}

setup

@test "Flox Help" {

  eval "result/bin/flox --help"

  [[ "$status" -eq 0 ]]
}

@test "Flox install hello" {

  eval "result/bin/flox install nixpkgs.stable.hello"


  [[ "$status" -eq 0 ]]
}

@test "Flox list after install should contain hello" {

  run result/bin/flox list
  [[ "${lines[-1]}" = *"nixpkgs.stable.hello"* ]]

}

@test "Flox remove hello" {

  eval "result/bin/flox remove nixpkgs.stable.hello"

  [[ "$status" -eq 0 ]]
}

@test "Flox list after remove should not contain hello" {

  eval "result/bin/flox list"
  [[ "$output" != *"nixpkgs.stable.hello"* ]]

}
