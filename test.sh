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
  [[ "$status" -eq 0 ]]
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
#TODO make these work and run tests on fresh profile testdir
#@test "Flox rollback should succeed" {
#
#  eval "result/bin/flox rollback"
#  [[ "$status" -eq 0 ]]
#  [[ "${lines[-1]}" = *"switching profile from version"* ]]
#
#}
#@test "Flox list after rollback should contain hello" {
#
#  eval "result/bin/flox list"
#  [[ "$status" -eq 0 ]]
#  [[ "${lines[-1]}" = *"nixpkgs.stable.hello"* ]]
#
#}
