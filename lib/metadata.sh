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
# ├── limeytexan (x86_64-linux.default branch)
# │   ├── 1.json
# │   ├── 2.json
# │   ├── 3.json
# │   ├── registry.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 3.json
# ├── limeytexan (x86_64-linux.toolbox branch)
# │   ├── 1.json
# │   ├── 2.json
# │   ├── registry.json
# │   ├── flake.json
# │   ├── flake.nix
# │   └── manifest.json -> 2.json
# └── tomberek (aarch64-darwin.default branch)
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
# gitInit($repoDir,$defaultBranch)
#
function gitInit() {
	trace "$@"
	local repoDir="$1"; shift
	local defaultBranch="$1"; shift
	# Set initial branch with `-c init.defaultBranch=` instead of
	# `--initial-branch=` to stay compatible with old version of
	# git, which will ignore unrecognized `-c` options.
	$_git -c init.defaultBranch="${defaultBranch}" init --quiet "$repoDir"
}

#
# gitCheckout($repoDir,$branch)
#
function gitCheckout() {
	trace "$@"
	local repoDir="$1"; shift
	local branch="$1"; shift
	[ -d "$repoDir" ] || gitInit "$repoDir" "$branch"
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
			$_git -C "$repoDir" ls-files | $_xargs $_git -C "$repoDir" rm -f
			# A commit is needed in order to make the branch visible.
			$_git -C "$repoDir" commit --quiet --allow-empty \
				-m "$FLOX_USER created profile"
		fi
	}
}

function metaGit() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_PROFILEMETA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	# For github.com specifically, set authentication helper.
	$invoke_git \
		-c "credential.https://github.com.helper=!$_gh auth git-credential" \
		-C $profileMetaDir "$@"
}

snipline="------------------------ >8 ------------------------"
protoManifestToml=$(cat <<EOF
# This is a prototype profile declarative manifest in TOML format,
# supporting comments and the ability to invoke "shellHook" commands
# upon profile activation. See the flox(1) man page for more details.

# [environment]
#   LANG = "en_US.UTF-8"
#   LC_ALL = "\$LANG"
#
# [aliases]
#   foo = "bar"
#   baz = "bing"
#
# [hooks]
#   sayhi = """
#     echo "Supercharged by flox!" 1>&2
#   """
#
# Edit below the "--- >8 ---" delimiter to define the list of packages to
# be installed, but note that comments and the ordering of packages will
# *not* be preserved with updates.
#
# Example package with optional constraints:
#   [packages."curl"]
#     channel = "nixpkgs"
#     stability = "staging"
#     version = "7.79"

# $snipline
EOF
)

# metaEdit($profile, $system)
#
# Edits profile declarative manifest. Is only invoked from an
# interactive terminal.
function metaEdit() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_PROFILEMETA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch. This is essential because we're
	# about to edit a file in that directory and it needs to be
	# the correct version.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	# Create a temp file for editing.
	tmpfile=$($_mktemp)

	# If the declarative manifest does not yet exist then we need
	# to initialize it first with a blank version
	if [ -f "$profileMetaDir/manifest.toml" ]; then
		cp "$profileMetaDir/manifest.toml" $tmpfile
	else
		$_cat > $tmpfile <<EOF
$protoManifestToml

EOF
		# If manifest.json already exists then append current package manifest.
		if [ -f "$profileMetaDir/manifest.json" ]; then
			manifest $profile/manifest.json listProfileTOML >> $tmpfile
		fi
	fi

	# Edit
	while true; do
		$editorCommand $tmpfile

		# Verify valid TOML syntax
		[ -s $tmpfile ] || (
			$_rm -f $tmpfile
			error "editor returned empty manifest .. aborting" < /dev/null
		)
		if validateTOML $tmpfile; then
			: confirmed valid TOML
			break
		else
			if boolPrompt "Try again?" "yes"; then
				: will try again
			else
				$_rm -f $tmpfile
				error "editor returned invalid TOML .. aborting" < /dev/null
			fi
		fi
	done

	# We copy rather than move to preserve bespoke ownership and mode.
	if $_cmp -s $tmpfile "$profileMetaDir/manifest.toml"; then
		$_rm -f $tmpfile
		if [ "$editorCommand" != "$_cat" ]; then
			warn "no changes detected ... exiting"
		fi
		exit 0
	else
		$_cp $tmpfile "$profileMetaDir/manifest.toml"
		$_rm -f $tmpfile
		metaGit "$profile" "$system" add "manifest.toml"
	fi
}

#
# syncProfile($profile,$system)
#
function syncProfile() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileDir=$($_dirname $profile)
	local profileName=$($_basename $profile)
	local profileUserName=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_PROFILEMETA/$profileUserName"

	# Ensure metadata repo is checked out to correct branch.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	# Run snippet to generate links using data from metadata repo.
	$_mkdir -v -p "$profileDir" 2>&1 | $_sed -e "s/[^:]*:/${me}:/"

	local snippet=$(profileRegistry "$profile" syncGenerations)
	eval "$snippet" || true

	# FIXME REFACTOR based on detecting actual change.
	[ -z "$_cline" ] || metaGit "$profile" "$system" add "metadata.json"
}

#
# syncProfiles($userName)
#
# The analog of syncMetadata(), this populates profile data using
# information found in the metadata repository and registers a
# GCRoot for the profile directory.
#
function syncProfiles() {
	trace "$@"
	local userName="$1"
	local profileMetaDir="$FLOX_PROFILEMETA/$userName"

	local branches=$($_git -C "$profileMetaDir" branch --format="%(refname:short)")
	for branch in "${branches}"; do
		syncProfile "$profileMetaDir" "$branch" || true # keep going
	done
}

function commitMessage() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local startGen="$1"; shift
	local endGen="$1"; shift
	local logMessage="$1"; shift
	local invocation="${@}"
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
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local startGen="$1"; shift
	local endGen="$1"; shift
	local logMessage="$1"; shift
	local invocation="${@}"
	local profileName=$($_basename $profile)
	local userName=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_PROFILEMETA/$userName"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	# Now reconcile the data.
	for i in ${profile}-+([0-9])-link; do
		local gen_link=${i#${profile}-} # remove prefix
		local gen=${gen_link%-link} # remove suffix
		if [ -e "$i/manifest.json" ]; then
			[ -e "$profileMetaDir/${gen}.json" ] || {
				$_cp "$i/manifest.json" "$profileMetaDir/${gen}.json"
				metaGit "$profile" "$system" add "${gen}.json"
			}
			# Upgrade manifest.json with change of schema version.
			$_cmp -s "$i/manifest.json" "$profileMetaDir/${gen}.json" || \
				metaGit "$profile" "$system" add "${gen}.json"
		fi
	done

	# Update manifest.json to point to current generation.
	local endMetaGeneration
	[ ! -e "$profileMetaDir/manifest.json" ] || \
		endMetaGeneration=$($_readlink "$profileMetaDir/manifest.json")
	[ "$endMetaGeneration" = "${endGen}.json" ] || {
		$_ln -f -s "${endGen}.json" "$profileMetaDir/manifest.json"
		metaGit "$profile" "$system" add "manifest.json"
	}
	profileRegistry "$profile" set currentGen "${endGen}"

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

	# Update package contents of declarative manifest.
	tmpfile=$($_mktemp)
	# Generate declarative manifest with packages section removed.
	if [ -f "$profileMetaDir/manifest.toml" ]; then
		# Include everything up to the snipline.
		$_awk "{if (/$snipline/) {exit} else {print}}" "$profileMetaDir/manifest.toml" > $tmpfile
	else
		# Bootstrap with prototype manifest.
		$_cat > $tmpfile <<EOF
$protoManifestToml
EOF
	fi
	# Append empty line if it doesn't already end with one.
	$_tail -1 $tmpfile | $_grep -q '^$' || ( echo >> $tmpfile )
	# Append updated packages list.
	echo "# $snipline" >> $tmpfile
	manifest "$profileMetaDir/manifest.json" listProfileTOML >> $tmpfile

	# Verify valid TOML syntax
	if validateTOML $tmpfile; then
		: confirmed valid TOML
	else
		$_rm -f $tmpfile
		error "program autogenerated invalid TOML .. aborting" < /dev/null
	fi

	if [ "$profileMetaDir/manifest.toml" ]; then
		if $_cmp -s "$profileMetaDir/manifest.toml" $tmpfile; then
			: no changes
		else
			$_cp -f $tmpfile "$profileMetaDir/manifest.toml"
			metaGit "$profile" "$system" add "manifest.toml"
		fi
	else
		$_cp -f $tmpfile "$profileMetaDir/manifest.toml"
		metaGit "$profile" "$system" add "manifest.toml"
	fi
	$_rm -f $tmpfile

	# Commit, reading commit message from STDIN.
	commitMessage \
		"$profile" "$system" "$startGen" "$endGen" \
		"$logMessage" "${invocation[@]}" | \
		metaGit "$profile" "$system" commit --quiet -F -
}

#
# setGitRemote($profile)
#
function setGitRemote() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local branch="${system}.${profileName}"

	# Check to see if the origin is already set.
	local origin=$(metaGit "$profile" "$system" \
		"config" "--get" "remote.origin.url" || true)
	if [ -z "$origin" ]; then
		# Proceed to set origin using a variety of defaults.
		local profileName=$($_basename $profile)
		local userName=$($_basename $($_dirname $profile))
		# HACK: redact "+ssh" from the origin for use with gh
		# find better way ...
		local defaultOrigin="${gitBaseURL/+ssh/}$userName/floxmeta"
		origin=$(registry ${FLOX_DATA_HOME}/metadata.json 1 \
			getPromptSet "git URL for storing profile metadata: " $defaultOrigin \
			profiles $userName $profileName origin)
		metaGit "$profile" "$system" "remote" "add" "origin" "$origin"
	fi

	# If using github, ensure that user is logged into gh CLI
	# and confirm that repository exists.
	if [[ "${origin,,}" =~ github ]]; then
		( $_gh auth status >/dev/null 2>&1 ) ||
			$_gh auth login
		( $_gh repo view "$origin" >/dev/null 2>&1 ) || (
			set -x
			$_gh repo create --private "$origin"
		)
	fi
}

#
# pushpullMetadata("(push|pull)",$profile)
#
function pushpullMetadata() {
	trace "$@"
	local action="$1"; shift
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local branch="${system}.${profileName}"

	[ $action = "push" -o $action = "pull" ] ||
		error "pushpullMetadata(): first arg must be (push|pull)"

	# First verify that the clone has an origin defined.
	setGitRemote "$profile" "$system"

	# Then push or pull.
	if [ "$action" = "push" ]; then
		metaGit "$profile" "$system" "$action" -u origin $branch
	elif [ "$action" = "pull" ]; then
		metaGit "$profile" "$system" "$action" origin $branch
		syncProfile "$profile" "$system"
	fi
}

# vim:ts=4:noet:syntax=bash
