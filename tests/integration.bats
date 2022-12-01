#!/usr/bin/env bats
#
# flox CLI tests run in two contexts:
# - unit tests only to be run from within package build
# - unit and integration tests to be run from command line
#
bats_load_library bats-support
bats_load_library bats-assert
bats_require_minimum_version 1.5.0

# setup_file() function run once for a given bats test file.
setup_file() {
	set -x
	if [ -L ./result ]; then
		export FLOX_PACKAGE=$(readlink ./result)
	else
		export FLOX_PACKAGE=$(flox build --print-out-paths --substituters "")
	fi
	export FLOX_CLI=$FLOX_PACKAGE/bin/flox
	export TEST_ENVIRONMENT=_testing_
	export NIX_SYSTEM=$($FLOX_CLI nix --extra-experimental-features nix-command show-config | awk '/system = / {print $NF}')
	# Remove any vestiges of previous test runs.
	$FLOX_CLI destroy -e $TEST_ENVIRONMENT --origin -f
	set +x
}

@test "flox package sanity check" {
  # directories
  [ -d $FLOX_PACKAGE/bin ]
  [ -d $FLOX_PACKAGE/libexec ]
  [ -d $FLOX_PACKAGE/libexec/flox ]
  [ -d $FLOX_PACKAGE/etc ]
  [ -d $FLOX_PACKAGE/etc/flox.zdotdir ]
  [ -d $FLOX_PACKAGE/lib ]
  [ -d $FLOX_PACKAGE/share ]
  [ -d $FLOX_PACKAGE/share/man ]
  [ -d $FLOX_PACKAGE/share/man/man1 ]
  [ -d $FLOX_PACKAGE/share/bash-completion ]
  [ -d $FLOX_PACKAGE/share/bash-completion/completions ]
  # executables
  [ -x $FLOX_CLI ]
  [ -x $FLOX_PACKAGE/libexec/flox/gh ]
  [ -x $FLOX_PACKAGE/libexec/flox/nix ]
  [ -x $FLOX_PACKAGE/libexec/flox/flox ]
  # Could go on ...
}

@test "flox --prefix" {
  run $FLOX_CLI --prefix
  assert_success
  assert_output $FLOX_PACKAGE
}

@test "flox --help" {
  run $FLOX_CLI --help
  assert_success
  assert_output - < tests/usage.out
}

@test "flox subscribe public" {
  run $FLOX_CLI subscribe flox-examples github:flox-examples/floxpkgs
  assert_success
  assert_output - < /dev/null
}

@test "flox unsubscribe public" {
  run $FLOX_CLI unsubscribe flox-examples
  assert_success
  assert_output - < /dev/null
}

@test "flox subscribe private" {
  run $FLOX_CLI subscribe flox-examples-private github:flox-examples/floxpkgs-private
  assert_success
  assert_output - < /dev/null
}

@test "flox unsubscribe private" {
  run $FLOX_CLI unsubscribe flox-examples-private
  assert_success
  assert_output - < /dev/null
}

@test "flox install hello" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT hello
  assert_success
  assert_output --partial "created generation 1"
}

@test "flox install nixpkgs-flox.hello" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT nixpkgs-flox.hello
  assert_success
  assert_output --partial "No environment changes detected"
}

@test "flox install stable.nixpkgs-flox.hello" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT stable.nixpkgs-flox.hello
  assert_success
  assert_output --partial "No environment changes detected"
}

# A rose by any other name ...
@test "flox subscribe nixpkgs-flox-dup" {
  run $FLOX_CLI subscribe nixpkgs-flox-dup github:flox/nixpkgs-flox/master
  assert_success
  assert_output - < /dev/null
}

@test "flox install stable.nixpkgs-flox-dup.hello" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT stable.nixpkgs-flox-dup.hello
  assert_success
  assert_output --partial "No environment changes detected"
}

@test "flox list after install should contain hello" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  1"
  assert_output --partial "0 stable.nixpkgs-flox.hello"
}

@test "flox install cowsay jq dasel" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT cowsay jq dasel
  assert_success
  assert_output --partial "created generation 2"
}

@test "flox list after install should contain cowsay and hello" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  2"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.hello"
  assert_output --partial "3 stable.nixpkgs-flox.jq"
}

@test "flox activate can invoke hello and cowsay" {
  run $FLOX_CLI activate -e $TEST_ENVIRONMENT -- sh -c 'hello | cowsay'
  assert_success
  assert_output - < tests/hello-cowsay.out
}

@test "flox edit remove hello" {
  EDITOR=./tests/remove-hello run $FLOX_CLI edit -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "created generation 3"
}

@test "verify flox edit removed hello from manifest.json" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  3"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
  assert_output --partial "2 stable.nixpkgs-flox.jq"
}

@test "verify flox edit removed hello from manifest.toml" {
  run $FLOX_CLI export -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial '[packages."cowsay"]'
  assert_output --partial '[packages."dasel"]'
  ! assert_output --partial '[packages."hello"]'
  assert_output --partial '[packages."jq"]'
}

@test "flox edit add hello" {
  EDITOR=./tests/add-hello run $FLOX_CLI edit -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "created generation 4"
}

@test "verify flox edit added hello to manifest.json" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  4"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.hello"
  assert_output --partial "3 stable.nixpkgs-flox.jq"
}

@test "verify flox edit added hello to manifest.toml" {
  run $FLOX_CLI export -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial '[packages."cowsay"]'
  assert_output --partial '[packages."dasel"]'
  assert_output --partial '[packages."hello"]'
  assert_output --partial '[packages."jq"]'
}

@test "flox remove hello" {
  run $FLOX_CLI remove -e $TEST_ENVIRONMENT hello
  assert_success
  assert_output --partial "created generation 5"
}

@test "flox list after remove should not contain hello" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  5"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.jq"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "flox list of generation 2 should contain hello" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT 2
  assert_success
  assert_output --partial "Curr Gen  2"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.hello"
  assert_output --partial "3 stable.nixpkgs-flox.jq"
}

@test "flox history should contain the install and removal of stable.nixpkgs-flox.hello" {
  run $FLOX_CLI history -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "removed stable.nixpkgs-flox.hello"
  assert_output --partial "installed stable.nixpkgs-flox.cowsay stable.nixpkgs-flox.jq stable.nixpkgs-flox.dasel"
  assert_output --partial "installed stable.nixpkgs-flox.hello"
  assert_output --partial "created environment"
}

@test "flox rollback" {
  run $FLOX_CLI rollback -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "switched to generation 4"
}

@test "flox list after rollback should reflect generation 2" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  4"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.hello"
  assert_output --partial "3 stable.nixpkgs-flox.jq"
}

@test "flox rollback --to 3" {
  run $FLOX_CLI rollback --to 3 -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "switched to generation 3"
}

@test "flox list after rollback --to 3 should reflect generation 3" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  3"
  assert_output --partial "0 stable.nixpkgs-flox.cowsay"
  assert_output --partial "1 stable.nixpkgs-flox.dasel"
  assert_output --partial "2 stable.nixpkgs-flox.jq"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "flox switch-generation 1" {
  run $FLOX_CLI switch-generation 1 -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "switched to generation 1"
}

@test "flox list after switch-generation 1 should reflect generation 1" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  1"
  assert_output --partial "0 stable.nixpkgs-flox.hello"
  ! assert_output --partial "stable.nixpkgs-flox.cowsay"
  ! assert_output --partial "stable.nixpkgs-flox.dasel"
  ! assert_output --partial "stable.nixpkgs-flox.jq"
}

@test "flox rollback to 0" {
  run $FLOX_CLI rollback -e $TEST_ENVIRONMENT
  assert_failure
  assert_output --partial "ERROR: invalid generation '0'"
}

@test "flox switch-generation 6" {
  run $FLOX_CLI switch-generation 6 -e $TEST_ENVIRONMENT
  assert_failure
  assert_output --partial "ERROR: could not find environment data for generation '6'"
}

@test "flox rollback --to 1" {
  run $FLOX_CLI rollback --to 1 -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "start and target generations are the same"
}

@test "flox generations" {
  run $FLOX_CLI generations -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Generation 1:"
  assert_output --partial "Path:"
  assert_output --partial "Created:"
  assert_output --partial "Last active:"
  assert_output --partial "Log entries:"
  assert_output --partial "installed stable.nixpkgs-flox.hello"
  assert_output --partial "Generation 2:"
  assert_output --partial "installed stable.nixpkgs-flox.cowsay stable.nixpkgs-flox.jq stable.nixpkgs-flox.dasel"
  assert_output --partial "Generation 3:"
  assert_output --partial "edited declarative profile (generation 3)"
  assert_output --partial "Generation 4:"
  assert_output --partial "edited declarative profile (generation 4)"
  assert_output --partial "Generation 5:"
  assert_output --partial "removed stable.nixpkgs-flox.hello"
}

@test "flox environments takes no arguments" {
  run $FLOX_CLI environments -e $TEST_ENVIRONMENT
  assert_failure
  assert_output --partial "ERROR: the 'flox environments' command takes no arguments"
}

@test "flox environments should at least contain $TEST_ENVIRONMENT" {
  run $FLOX_CLI environments
  assert_success
  assert_output --partial "/$TEST_ENVIRONMENT"
  assert_output --partial "Alias     $TEST_ENVIRONMENT"
}

@test "flox push" {
  run $FLOX_CLI push -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "To "
  assert_output --regexp "\* \[new branch\] +origin/.*.$TEST_ENVIRONMENT -> .*.$TEST_ENVIRONMENT"
}

@test "flox destroy local only" {
  run $FLOX_CLI destroy -e $TEST_ENVIRONMENT -f
  assert_success
  assert_output --partial "WARNING: you are about to delete the following"
  assert_output --partial "Deleted branch"
  assert_output --partial "removed"
}

@test "flox pull" {
  run $FLOX_CLI pull -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "To "
  assert_output --regexp "\* \[new branch\] +.*\.$TEST_ENVIRONMENT -> .*\.$TEST_ENVIRONMENT"
}

@test "flox list after flox pull should be exactly as before" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  1"
  assert_output --partial "0 stable.nixpkgs-flox.hello"
  ! assert_output --partial "stable.nixpkgs-flox.cowsay"
  ! assert_output --partial "stable.nixpkgs-flox.dasel"
  ! assert_output --partial "stable.nixpkgs-flox.jq"
}

@test "flox search should return results quickly" {
  # "timeout 15 flox search" does not work? Haven't investigated why, just
  # fall back to doing the math manually and report when it takes too long.
  local -i start=$(date +%s)
  run $FLOX_CLI search hello
  local -i end=$(date +%s)
  assert_success
  assert_output --partial "stable.nixpkgs-flox.hello"
  assert_output --partial "staging.nixpkgs-flox.hello"
  assert_output --partial "unstable.nixpkgs-flox.hello"
  # Assert we spent less than 15 seconds in the process.
  local -i elapsed=$(( $end - $start ))
  echo spent $elapsed seconds
  [ $elapsed -lt 15 ]
}

@test "flox install by /nix/store path" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT $FLOX_PACKAGE
  assert_success
  assert_output --partial "created generation 6"
}

@test "flox list after installing by store path should contain package" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  6"
  assert_output --partial "0 $FLOX_PACKAGE"
  assert_output --partial "1 stable.nixpkgs-flox.hello"
}

@test "flox remove hello again" {
  run $FLOX_CLI remove -e $TEST_ENVIRONMENT hello
  assert_success
  assert_output --partial "created generation 7"
}

@test "flox install by nixpkgs flake" {
  run $FLOX_CLI install -e $TEST_ENVIRONMENT "nixpkgs#hello"
  assert_success
  assert_output --partial "created generation 8"
}

@test "flox list after installing by nixpkgs flake should contain package" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  8"
  assert_output --partial "0 $FLOX_PACKAGE"
  assert_output --partial "1 flake:nixpkgs#legacyPackages.$NIX_SYSTEM.hello"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "flox export after installing by nixpkgs flake should contain package" {
  run $FLOX_CLI export -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial '[packages."legacyPackages.'$NIX_SYSTEM'.hello"]'
  assert_output --partial 'originalUrl = "flake:nixpkgs"'
  assert_output --partial 'attrPath = "legacyPackages.'$NIX_SYSTEM'.hello"'
}

@test "flox remove by nixpkgs flake 1" {
  run $FLOX_CLI remove -e $TEST_ENVIRONMENT "nixpkgs#hello"
  assert_success
  assert_output --partial "created generation 9"
}

@test "flox list after remove by nixpkgs flake 1 should not contain package" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  9"
  assert_output --partial "0 $FLOX_PACKAGE"
  ! assert_output --partial "flake:nixpkgs#legacyPackages.$NIX_SYSTEM.hello"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "flox rollback after flake removal 1" {
  run $FLOX_CLI rollback -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "switched to generation 8"
}

@test "flox remove by nixpkgs flake 2" {
  run $FLOX_CLI remove -e $TEST_ENVIRONMENT "legacyPackages.$NIX_SYSTEM.hello"
  assert_success
  assert_output --partial "created generation 10"
}

@test "flox list after remove by nixpkgs flake 2 should not contain package" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  10"
  assert_output --partial "0 $FLOX_PACKAGE"
  ! assert_output --partial "flake:nixpkgs#legacyPackages.$NIX_SYSTEM.hello"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "flox switch-generation after flake removal 2" {
  run $FLOX_CLI rollback -e $TEST_ENVIRONMENT --to 8
  assert_success
  assert_output --partial "switched to generation 8"
}

@test "flox remove by nixpkgs flake 3" {
  run $FLOX_CLI remove -e $TEST_ENVIRONMENT "flake:nixpkgs#legacyPackages.$NIX_SYSTEM.hello"
  assert_success
  assert_output --partial "created generation 11"
}

@test "flox list after remove by nixpkgs flake 3 should not contain package" {
  run $FLOX_CLI list -e $TEST_ENVIRONMENT
  assert_success
  assert_output --partial "Curr Gen  11"
  assert_output --partial "0 $FLOX_PACKAGE"
  ! assert_output --partial "flake:nixpkgs#legacyPackages.$NIX_SYSTEM.hello"
  ! assert_output --partial "stable.nixpkgs-flox.hello"
}

@test "tear down install test state" {
  run $FLOX_CLI destroy -e $TEST_ENVIRONMENT --origin -f
  assert_output --partial "WARNING: you are about to delete the following"
  assert_output --partial "Deleted branch"
  assert_output --partial "removed"
}

# vim:ts=4:noet:syntax=bash
