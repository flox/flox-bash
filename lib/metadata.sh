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
# │   ├── registry.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 3.json
# ├── limeytexan (toolbox branch)
# │   ├── 1.json
# │   ├── 2.json
# │   ├── registry.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 2.json
# └── tomberek (default branch)
#     ├── 1.json
#     ├── 2.json
#     ├── 3.json
#     ├── 4.json
#     ├── registry.json
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
# * metaGit():      provides access to git commands for metadata repo
#
# Many git conventions employed here are borrowed from Nix's own
# src/libfetchers/git.cc file.
#

#
# gitInit($repoDir)
#
function gitInit() {
	# Set initial branch with `-c init.defaultBranch=` instead of
	# `--initial-branch=` to stay compatible with old version of
	# git, which will ignore unrecognized `-c` options.
	$_git -c init.defaultBranch="default" init "$repoDir"
}

#
# gitCheckout($repoDir,$branch)
#
function gitCheckout() {
	local repoDir="$1"
	local branch="$2"
	[ -d "$repoDir" ] || gitInit "$repoDir"
	[ "$($_git -C "$repoDir" rev-parse --abbrev-ref HEAD)" = "$branch" ] || {
		if $_git -C "$repoDir" show-ref -q refs/heads/"$branch"; then
			$_git -C "$repoDir" checkout "$branch"
		else
			$_git -C "$repoDir" checkout --orphan "$branch"
		fi
	}
}

function metaGit() {
	local profile="$1"; shift
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local metaDir="$FLOX_METADATA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$metaDir" "$profileName"

	$_git -C $metaDir "$@"
}

# XXX For debugging; remove someday.
function metaDebug() {
	local profile="$1"; shift
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local metaDir="$FLOX_METADATA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$metaDir" "$profileName"

	( cd $metaDir && ls -l && $_git status )
}

function syncProfiles() {
:
}

function commitMessage() {
	local profile="$1"
	local startGen="$2"
	local endGen="$3"
	local logMessage="$4"
	local invocation="${@:5:}"
	cat <<EOF
$logMessage

${invocation[@]}
EOF
	[ -z "$startGen" ] || \
		$_nix store diff-closures \
			"${profile}-${startGen}-link" \
			"${profile}-${endGen}-link"
}

#
# syncMetadata($profile)
#
# Expects commit message from STDIN.
#
function syncMetadata() {
	local profile="$1"
	local startGen="$2"
	local endGen="$3"
	local logMessage="$4"
	local invocation="${@:5:}"
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local metaDir="$FLOX_METADATA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$metaDir" "$profileName"

	# Now reconcile the data.
	for i in ${profile}-+([0-9])-link; do
		local gen_link=${i#${profile}-} # remove prefix
		local gen=${gen_link%-link} # remove suffix
		[ -e "$metaDir/${gen}.json" ] || {
			$_cp "$i/manifest.json" "$metaDir/${gen}.json"
			metaGit "$profile" add "${gen}.json"
		}
		# Verify that something hasn't gone horribly wrong.
		$_cmp -s "$i/manifest.json" "$metaDir/${gen}.json" || \
			error "$i/manifest.json and $metaDir/${gen}.json differ"
	done

	# ... and update manifest.json to point to current generation.
	local endMetaGeneration
	[ ! -e "$metaDir/manifest.json" ] || \
		endMetaGeneration=$($_readlink "$metaDir/manifest.json")
	[ "$endMetaGeneration" = "${gen}.json" ] || {
		$_ln -f -s "${gen}.json" "$metaDir/manifest.json"
		metaGit "$profile" add "manifest.json"
	}

	# Commit, reading commit message from STDIN.
	commitMessage "$@" | metaGit "$profile" commit -F -
}

function pullMetadata() {
:
}

function pushMetadata() {
:
}

#function readHead() {
#	local path="$1"
#	$_git -C "$path" rev-parse --abbrev-ref HEAD
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
