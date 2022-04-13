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
	$_git -c init.defaultBranch="default" init --quiet "$repoDir"
}

#
# gitCheckout($repoDir,$branch)
#
function gitCheckout() {
	local repoDir="$1"
	local branch="$2"
	[ -d "$repoDir" ] || gitInit "$repoDir"
	# It's somewhat awkward to determine the current branch
	# *before* that first commit. If there's a better git
	# subcommand to figure this out I can't find it.
	local currentBranch=
	if [ -d "$repoDir" ]; then
		currentBranch=$($_git -C "$repoDir" status | \
			$_awk '/^On branch / {print $3; exit}')
		# possibly better way to determine current branch after first commit?
		# git branch --format="%(if)%(HEAD)%(then)%(refname:short)%(end)"
	fi
	[ "$currentBranch" = "$branch" ] || {
		if $_git -C "$repoDir" show-ref -q refs/heads/"$branch"; then
			$_git -C "$repoDir" checkout --quiet "$branch"
		else
			$_git -C "$repoDir" checkout --quiet --orphan "$branch"
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

#
# syncProfile($profile)
#
function syncProfile() {
	local profile="$1"
	local profileName=$($_basename $profile)
	local profileUserName=$($_basename $($_dirname $profile))
	local metaDir="$FLOX_METADATA/$profileUserName"

	# Ensure metadata repo is checked out to correct branch.
	gitCheckout "$metaDir" "$profileName"

	# Run snippet to generate links using data from metadata repo.
	local _cline
	profileRegistry "$profile" syncGenerations | while read _cline
	do
		eval "$_cline"
	done
}

#
# syncProfiles($userName)
#
# The analog of syncMetadata(), this populates profile data using
# information found in the metadata repository and registers a
# GCRoot for the profile directory.
#
function syncProfiles() {
	local userName="$1"
	local metaDir="$FLOX_METADATA/$userName"

	local branches=$($_git -C "$metaDir" branch --format="%(refname:short)")
	for branch in "${branches}"; do
		syncProfile "$metaDir" "$branch"
	done
}

function commitMessage() {
	local profile="$1"
	local startGen="$2"
	local endGen="$3"
	local logMessage="$4"
	local invocation="${@:5:}"
	local profileName=$($_basename $profile)
	cat <<EOF
$logMessage

${invocation[@]}
EOF
	#
	# Now we'd like to include a "diff" of the closures for the log.
	# Nix has rich functionality in this regard but with awkward usage:
	#
	# 1. `nix store diff-closures` has the right usage semantics because
	#    it allows you to specify two profile paths, but it reports more
	#    detail than we're looking for.
	# 2. `nix profile history` gives us the information we're looking for
	#    but expects a linear progression of generations only and won't
	#    report differences between arbitrary generations. It also embeds
	#    color characters in the output and doesn't honor the (mandatory)
	#    `--no-colors` flag. And ... it gives flake references that we
	#    need to convert back to floxpkgs package names.
	#
	# ... so, we mock up a tmpDir with the qualities of #2 above.
	# Not fun but better than nothing.
	#
	local tmpDir=$($_mktemp -d)
	# `nix profile history` requires generations to be in sequential
	# order, so for the purpose of this invocation we set the generations
	# as 1 and 2 if both are defined, or 1 if there is only one generation.
	local myEndGen=
	if [ -n "$startGen" ]; then
		# If there is a start and end generation then set generat
		$_ln -s $($_readlink "${profile}-${startGen}-link") $tmpDir/${profileName}-1-link
		$_ln -s $($_readlink "${profile}-${endGen}-link") $tmpDir/${profileName}-2-link
		local myEndGen=2
	else
		$_ln -s $($_readlink "${profile}-${endGen}-link") $tmpDir/${profileName}-1-link
		local myEndGen=1
	fi
	$_ln -s ${profileName}-${myEndGen}-link $tmpDir/${profileName}

	local _cline
	$_nix profile history --profile $tmpDir/${profileName} | $_ansifilter --text | \
		$_awk '\
			BEGIN {p=0} \
			/^  flake:/ {if (p==1) {print $0}} \
			/^Version '${myEndGen}' / {p=1}' | \
		while read _cline
		do
			local flakeref=$(echo "$_cline" | $_cut -d: -f1,2)
			local detail=$(echo "$_cline" | $_cut -d: -f3-)
			local floxpkg=$(manifest $profile/manifest.json flakerefToFloxpkg "$flakeref")
			echo "  ${floxpkg}:${detail}"
		done

	$_rm -f \
		$tmpDir/"${profileName}-1-link" \
		$tmpDir/"${profileName}-2-link" \
		$tmpDir/"${profileName}"
	$_rmdir $tmpDir
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
			error "$i/manifest.json and $metaDir/${gen}.json differ" < /dev/null
	done

	# Update manifest.json to point to current generation.
	local endMetaGeneration
	[ ! -e "$metaDir/manifest.json" ] || \
		endMetaGeneration=$($_readlink "$metaDir/manifest.json")
	[ "$endMetaGeneration" = "${endGen}.json" ] || {
		$_ln -f -s "${endGen}.json" "$metaDir/manifest.json"
		metaGit "$profile" add "manifest.json"
	}

	# Update profile metadata with end generation information.
	profileRegistry "$profile" set generations \
		${endGen} path $($_readlink ${profile}-${endGen}-link)
	profileRegistry "$profile" addArray generations \
		${endGen} logMessage "$logMessage"
	profileRegistry "$profile" setNumber generations \
		${endGen} created $($_stat --format=%Y ${profile}-${endGen}-link)
	profileRegistry "$profile" setNumber generations \
		${endGen} lastActive "$now"

	# Also update lastActive time for starting generation, if known.
	[ -z "${startGen}" ] || \
		profileRegistry "$profile" setNumber generations \
			${startGen} lastActive "$now"

	# Commit, reading commit message from STDIN.
	commitMessage "$@" | metaGit "$profile" commit --quiet -F -
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
