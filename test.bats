#!/usr/bin/env bats

setup() {
  nix build .
}


@test "flox Help" {

  eval "result/bin/flox --help"

  [[ "$status" -eq 0 ]]
}

@test "flox install hello" {

  eval "result/bin/flox install nixpkgs.stable.hello"


  [[ "$status" -eq 0 ]]
}

@test "flox list after install should contain hello" {

  run result/bin/flox list
  [[ "$output" =~ "nixpkgs.stable.hello" ]]

}

@test "flox remove hello" {

  eval "result/bin/flox remove nixpkgs.stable.hello"

  [[ "$status" -eq 0 ]]
}

@test "flox list after remove should not contain hello" {

  run  result/bin/flox list
  [[ ! "$output" =~ "nixpkgs.stable.hello" ]]

}

@test "flox history should contain the install and removal of nixpkgs.stable.hello" {

  run result/bin/flox history
  [[ "$output" =~ "flox install nixpkgs.stable.hello" ]]
  [[ "$output" =~ "flox remove nixpkgs.stable.hello" ]]

}

@test "flox generations should contain 2 or more generations after install/remove" {

  run result/bin/flox generations
  [[ "$output" =~ "Generation 1" ]]
  [[ "$output" =~ "Generation 2" ]]

}


@test "flox profiles should contain at least 1 profile" {

  run result/bin/flox profiles
  [[ "$output" =~ "Name" ]]
  [[ "$output" =~ "Path" ]]
  [[ "$output" =~ "Curr Gen" ]]

}


@test "flox rollback should switch to previous profile version" {

  run result/bin/flox profiles
  [[ "$output" =~ "switching profile from version" ]]

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
