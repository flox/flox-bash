#!/usr/bin/env bats

setup() {
 flox build floxpkgs#flox --override-input flox $PWD
}


@test "flox --stability stable Help" {

  eval "${FLOXPATH}/result/bin/flox --stability stable --help"

  [[ "$status" -eq 0 ]]
}

@test "flox --stability stable install hello" {

  eval "${FLOXPATH}/result/bin/flox --stability stable install stable.nixpkgs.hello"


  [[ "$status" -eq 0 ]]
}

@test "flox --stability stable list after install should contain hello" {

  run result/bin/flox --stability stable list
  [[ "$output" =~ "stable.nixpkgs.hello" ]]

}

@test "flox --stability stable remove hello" {

  eval "${FLOXPATH}/result/bin/flox remove stable.nixpkgs.hello"

  [[ "$status" -eq 0 ]]
}

@test "flox list after remove should not contain hello --stability stable" {

  run  "${FLOXPATH}"/result/bin/flox --stability stable list
  [[ ! "$output" =~ "stable.nixpkgs.hello" ]]

}

@test "flox history should contain the install and removal of stable.nixpkgs.hello --stability stable" {

  run "${FLOXPATH}"/result/bin/flox --stability stable history
  [[ "$output" =~ "flox install stable.nixpkgs.hello" ]]
  [[ "$output" =~ "flox remove stable.nixpkgs.hello" ]]

}

@test "flox generations should contain 1 or more generations after install/remove --stability stable" {

  run "${FLOXPATH}"/result/bin/flox --stability stable generations
  [[ "$output" =~ "Generation" ]]

}


@test "flox profiles should contain at least 1 profile" {

  run "${FLOXPATH}"/result/bin/flox --stability stable profiles
  [[ "$output" =~ "Alias" ]]
  [[ "$output" =~ "Path" ]]
  [[ "$output" =~ "Curr Gen" ]]

}


#TODO manage state for this test in the gh runner machine before running test
#@test "flox rollback should switch to previous profile version" {
#
#  run "${FLOXPATH}"/result/bin/flox --stability stable rollback
#  [[ "$output" =~ "switching profile from version" ]]
#
#}
#
#@test "flox rollback should switch to previous profile version" {
#
#  run result/bin/flox --stability stable rollback
#  [[ "$output" =~ "switching profile from version" ]]

#}

@test "flox search should return expected results" {
  run "${FLOXPATH}"/result/bin/flox --stability stable search "hello"
  [[ "$output" =~ "stable.nixpkgs.hello" ]]
}
