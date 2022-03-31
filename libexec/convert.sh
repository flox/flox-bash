#!/usr/bin/env bash
export FLOX_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/flox"
export FLOX_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/flox"
PROFILE_DIR="$FLOX_CACHE"/profiles

# Get this from somewhere
GIT_REMOTE=https://github.com/tomberek/profile-test

function sync_repo() {
    mkdir -p "$FLOX_CACHE"
    # TODO: ensure repo is initialized and/or created
    if [ ! -d "$PROFILE_DIR" ]; then
        $_git clone "$GIT_REMOTE" "$FLOX_CACHE"
        pushd "$FLOX_CACHE"/profiles || return 1
    else
        pushd "$FLOX_CACHE"/profiles || return 1
        $_git pull
    fi
}

function parse_profile_link() {
    local path="$1"
    if [[ "$path" =~ ^(.*)-([0-9]+)-link$ ]]; then
        local prefix=${BASH_REMATCH[1]}
        local gen=${BASH_REMATCH[2]}
        local tgtpath="$prefix-$gen-link"  # == $path
        echo "$tgtpath"
    else
        return 1
    fi
}

## given a repo, render profiles
function render_profiles() {
    local PROFILE_NAME="$1"
    for profile in "$FLOX_DATA_HOME"/profiles/"$PROFILE_NAME"-*-link; do
        tgtpath=$(parse_profile_link "$profile")
        echo "$tgtpath"
        # TODO: save all the manifest.json into {1,2,3}.json
    done
}


## TODO: make a repo from existing profiles
function import_profiles() {
    echo not implemented
    exit 1
}

"$@"
