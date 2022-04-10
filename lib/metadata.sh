#
# Subroutines for management of flox profile metadata cache.
#
# This module provides functions which synchronize the user's profile
# metadata repository following change in profile data, or to populate
# the profile directories from user's profile metadata repository.
#
# The profile metadata repository contains copies of the manifest.json
# files from each generation with the name <generation_number>.json,
# along with a single manifest.json symlink pointing at the current
# version and a rudimentary flake.{nix,json} pair which enables the
# directory to be used as a package collection if desired. There is
# one metadata repository per user and each profile is represented
# as a separate branch. See https://github.com/flox/flox/issues/14.
#
# Example hierarcy:
# .
# ├── limeytexan (default branch)
# │   ├── 1.json
# │   ├── 2.json
# │   ├── 3.json
# │   ├── config.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 3.json
# ├── limeytexan (toolbox branch)
# │   ├── 1.json
# │   ├── 2.json
# │   ├── config.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 2.json
# └── tomberek (default branch)
#     ├── 1.json
#     ├── 2.json
#     ├── 3.json
#     ├── 4.json
#     ├── config.json
#     ├── flake.json
#     ├── flake.nix
#     └── manifest.json -> 4.json
#
# "Public" functions exposed by this module:
#
# * syncProfiles(): reconciles/updates profile data from metadata repository
# * syncMetadata(): reconciles/updates metadata repository from profile data
# * pullMetadata(): pulls metadata updates from upstream to local cache
# * pushMetadata(): pushes metadata updates from local cache to upstream
#
# Many git conventions employed here are borrowed from Nix's own
# src/libfetchers/git.cc file.
#

#
# gitInit($repoDir,$branch)
#
function gitInit() {
	local repoDir="$1"
	local branch="$2"
	# Set initial branch with `-c init.defaultBranch=` instead of
	# `--initial-branch=` to stay compatible with old version of
	# git, which will ignore unrecognized `-c` options.
	$_git -c init.defaultBranch=$branch init $repoDir
}

function syncProfiles() {
:
}

#
# syncMetadata($profile)
#
function syncMetadata() {
	local profile="$1"
	local userName=$($_basename $($_dirname $profile))
	local profileName=$($_basename $profile)
	local metaDir="$FLOX_METADATA/$userName"
	[ -d "$metaDir" ] || gitInit "$metaDir" "$profileName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$metaDir" "$profileName"

	# Now reconcile the data.
	for i in "${profile}-+([0-9])-link"; do
		local gen_link=${i#${profile}-} # remove prefix
		local gen=${gen_link%-link} # remove suffix
		$_cmp "$profile/manifest.json" "$metaDir/${gen}.json" || {
			$_cp "$profile/manifest.json" "$metaDir/${gen}.json"
			gitAdd "$metaDir/${gen}.json"
		}
	done
    local currentGeneration=$($_readlink $profile)
	if [[ "$currentGeneration" =~ ^${profileName}-([0-9]+)-link$ ]]; then
		local gen=${BASH_REMATCH[1]}
		local currentMetaGeneration
		[ ! -e "$metaDir/manifest.json" ] || \
			currentMetaGeneration=$($_readlink "$metaDir/manifest.json")
		[[ "$currentMetaGeneration" == "${gen}.json" ]] || {
			$_ln -f -s "${gen}.json" "$metaDir/manifest.json"
			gitAdd "$metaDir/manifest.json"
		}
	fi

	gitCommit "$metaDir"
}

function pullMetadata() {
:
}

function pushMetadata() {
:
}

#function readHead() {
#	local path="$1"
#    $_git -C "$path" rev-parse --abbrev-ref HEAD
#}

#function isNotDotGitDirectory() {
#	local path="$1"
#	[[ "$path" =~ ^(?:.*/)?\\.git$ ]]
#}

# process of initializing clone
#
# - where is directory? $FLOX_METADATA/<user> (one branch per profile)
# - does directory exist?
#   - yes, continue
#   - no, look up location in "flox registry" (where? $FLOX_CACHE_HOME/flox-registry.json)
#	- if not found then prompt to clone from "canonical" location
#	- if then not exist, then ask them to create manually
#	  - in future we can use `gh` to create URIs containing "github"

# vim:ts=4:noet:
