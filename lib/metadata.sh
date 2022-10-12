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
declare defaultBranch="floxmain"
function gitInit() {
	trace "$@"
	local repoDir="$1"; shift
	# Set initial branch with `-c init.defaultBranch=` instead of
	# `--initial-branch=` to stay compatible with old version of
	# git, which will ignore unrecognized `-c` options.
	$invoke_git -c init.defaultBranch="${defaultBranch}" init --quiet "$repoDir"
}

#
# gitCheckout($repoDir,$branch)
#
function gitCheckout() {
	trace "$@"
	local repoDir="$1"; shift
	local branch="$1"; shift
	[ -d "$repoDir" ] || {
		gitInit "$repoDir"
		$_git -C "$repoDir" config pull.rebase true
		# A commit is needed in order to make the branch visible.
		$_git -C "$repoDir" commit --quiet --allow-empty \
			-m "$USER created repository"
	}

	# XXX Temporary: ensure there's an (orphan) floxmain branch in each repository.
	# XXX Delete after 2022: gitInit() takes care of creating the branch going forward,
	# XXX so we won't need this once all existing floxmeta repos have been updated.
	$_git -C "$repoDir" show-ref -q refs/heads/"$defaultBranch" || {
		$_git -C "$repoDir" checkout --quiet --orphan "$defaultBranch"
		$_git -C "$repoDir" ls-files | $_xargs --no-run-if-empty $_git -C "$repoDir" rm --quiet -f
		$_git -C "$repoDir" commit --quiet --allow-empty \
			-m "$USER created repository"
	} # XXX

	# It's somewhat awkward to determine the current branch
	# *before* that first commit. If there's a better git
	# subcommand to figure this out I can't find it.
	local currentBranch=
	if [ -d "$repoDir" ]; then
		currentBranch=$($_git -C "$repoDir" branch --show-current)
	fi
	[ "$currentBranch" = "$branch" ] || {
		if $_git -C "$repoDir" show-ref -q refs/heads/"$branch"; then
			$_git -C "$repoDir" checkout --quiet "$branch"
		else
			$_git -C "$repoDir" checkout --quiet --orphan "$branch"
			$_git -C "$repoDir" ls-files | $_xargs --no-run-if-empty $_git -C "$repoDir" rm --quiet -f
			# A commit is needed in order to make the branch visible.
			$_git -C "$repoDir" commit --quiet --allow-empty \
				-m "$USER created profile"
		fi
	}
}

# githubHelperGit($dir)
#
# Invokes git in provided directory with github helper configured.
function githubHelperGit() {
	trace "$@"
	# For github.com specifically, set authentication helper.
	$invoke_git \
		-c "credential.https://github.com.helper=!$_gh auth git-credential" "$@"
}

function metaGit() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	githubHelperGit -C "$profileMetaDir" "$@"
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
#   gg = "git grep"
#
# [hooks]
#   sayhi = """
#     echo "Supercharged by flox!" 1>&2
#   """
#
# Edit below the "--- >8 ---" delimiter to define the list of packages to
# be installed, but note that comments and the ordering of packages will
# *not* be preserved with updates.

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
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"

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
	local profileRealDir=$($_readlink -f $profileDir)
	local profileOwner=$($_basename $profileRealDir)
	local profileMetaDir="$FLOX_META/$profileOwner"

	# Ensure metadata repo is checked out to correct branch.
	gitCheckout "$profileMetaDir" "${system}.${profileName}"

	# Run snippet to generate links using data from metadata repo.
	$_mkdir -v -p "$profileRealDir" 2>&1 | $_sed -e "s/[^:]*:/${me}:/"

	local snippet=$(profileRegistry "$profile" syncGenerations)
	eval "$snippet" || true

	# FIXME REFACTOR based on detecting actual change.
	[ -z "$_cline" ] || metaGit "$profile" "$system" add "metadata.json"
}

#
# syncProfiles($profileOwner)
#
# The analog of syncMetadata(), this populates profile data using
# information found in the metadata repository and registers a
# GCRoot for the profile directory.
#
function syncProfiles() {
	trace "$@"
	local profileOwner="$1"
	local profileMetaDir="$FLOX_META/$profileOwner"

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
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"

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

function checkGhAuth {
	trace "$@"
	local hostname="$1"; shift
	# Repeat login attempts until we're successfully logged in.
	while ! $_gh auth status -h $hostname >/dev/null 2>&1; do
		initialGreeting
		warn "Invoking 'gh auth login -h $hostname'"
		$_gh auth login -h $hostname
		info ""
	done
}

function getUsernameFromGhAuth {
	trace "$@"
	local hostname="$1"; shift
	# Get github username from gh data, if known.
	[ -s "$HOME/.config/gh/hosts.yml" ]
	$_dasel -f "$HOME/.config/gh/hosts.yml" "${hostname//./\\.}.user"
}

#
# promptMetaOrigin()
#
# Guides user through the process of prompting for and/or creating
# an origin for their floxmeta repository.
#
function promptMetaOrigin() {
	trace "$@"

	local server organization defaultOrigin origin

	echo 1>&2
	echo "flox uses git to store and exchange metadata between users and machines." 1>&2
	server=$(
		multChoice "Where would you like to host your 'floxmeta' repository?" \
			"git server" "github.com" "gitlab.com" "bitbucket.org" "other"
	)

	case "$server" in
	github.com)
		echo "Great, let's start by getting you logged into $server." 1>&2
		# For github.com only, use the `gh` CLI to make things easy.
		checkGhAuth $server
		if organization=$(getUsernameFromGhAuth $server); then
			echo "Success! You are logged into $server as $organization." 1>&2
		else
			echo "Hmmm ... could not log you into $server. No problem, we can find another way." 1>&2
		fi
		;;
	other)
		read -e -p "git server for storing profile metadata: " server
		;;
	esac

	[ -n "$organization" ] ||
		read -e -p "organization (or username) on $server for creating the 'floxmeta' repository: " organization

	local protocol=$(
		multChoice "What is your preferred protocol for Git operations?" \
			"protocol" "https" "ssh+git"
	)

	case "$protocol" in
	https)
		defaultURL="https://$server/"
		;;
	ssh+git)
		defaultURL="git+ssh://git@$server/"
		;;
	esac

	echo "$defaultURL$organization/floxmeta"
}

#
# rewriteURLs()
#
# Function to inspect the entirety of a floxmeta repository and rewrite
# any/all URLs that reference the local disk to instead point to the new
# git remote home.
#
function rewriteURLs() {
	trace "$@"
	# TODO once we've finalised the self-referential TOML->environment renderer.
	# Manifests won't contain any references to the floxmeta repository until then.
	return 0
}

#
# getSetOrigin($profile)
#
function getSetOrigin() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"
	local branch="${system}.${profileName}"

	# Check to see if the origin is already set.
	local origin=$([ -d "$profileMetaDir" ] && $_git -C "$profileMetaDir" \
		"config" "--get" "remote.origin.url" || true)
	if [ -z "$origin" ]; then
		# Infer/set origin using a variety of information.
		local profileName=$($_basename $profile)
		local profileOwner=$($_basename $($_dirname $profile))
		local defaultOrigin=
		if [ "$profileOwner" == "local" ]; then
			defaultOrigin=$(promptMetaOrigin)
		else
			# Strange to have a profile on disk in a named without a
			# remote origin. Prompt user to confirm floxmeta repo on
			# github.
			defaultOrigin="${gitBaseURL/+ssh/}$profileOwner/floxmeta"
		fi

		echo 1>&2
		read -e \
			-p "confirm git URL for storing profile metadata: " \
			-i "$defaultOrigin" origin

		# A few final cleanup steps.
		if [ "$profileOwner" == "local" ]; then
			local newProfileOwner=$($_dirname $origin); newProfileOwner=${newProfileOwner/*[:\/]/} # XXX hack

			# rename .cache/flox/profilemeta/{local -> owner} &&
			#   replace with symlink from local -> owner
			# use .cache/flox/profilemeta/owner as profileMetaDir going forward (only for this function though!)
			if [ -d "$FLOX_META/$newProfileOwner" ]; then
				warn "moving profile metadata directory $FLOX_META/$newProfileOwner out of the way"
				$invoke_mv --verbose $FLOX_META/$newProfileOwner{,.$$}
			fi
			if [ -d "$FLOX_META/local" ]; then
				$invoke_mv "$FLOX_META/local" "$FLOX_META/$newProfileOwner"
			fi
			$invoke_ln -s -f $newProfileOwner "$FLOX_META/local"
			profileMetaDir="$FLOX_META/$newProfileOwner"

			# rename .local/share/flox/environments/{local -> owner}
			#   replace with symlink from local -> owner
			if [ -d "$FLOX_ENVIRONMENTS/$newProfileOwner" ]; then
				warn "moving profile directory $FLOX_ENVIRONMENTS/$newProfileOwner out of the way"
				$invoke_mv --verbose $FLOX_ENVIRONMENTS/$newProfileOwner{,.$$}
			fi
			if [ -d "$FLOX_ENVIRONMENTS/local" ]; then
				$invoke_mv "$FLOX_ENVIRONMENTS/local" "$FLOX_ENVIRONMENTS/$newProfileOwner"
			fi
			$invoke_ln -s -f $newProfileOwner "$FLOX_ENVIRONMENTS/local"

			# perform single commit rewriting all URL references to refer to new home of floxmeta repo
			rewriteURLs "$FLOX_ENVIRONMENTS/local" "$origin"
		fi

		[ -d "$profileMetaDir" ] || gitInit "$profileMetaDir"
		$invoke_git -C "$profileMetaDir" "remote" "add" "origin" "$origin"
	fi

	ensureGHRepoExists "$origin" private "https://github.com/flox/floxmeta-template.git"
	echo "$origin"
}

#
# pushpullMetadata("(push|pull)",$profile,$system)
#
# This function creates an ephemeral clone for reconciling commits before
# pushing the result to either of the local (origin) or remote (upstream)
# repositories.
#
function pushpullMetadata() {
	trace "$@"
	local action="$1"; shift
	local profile="$1"; shift
	local system="$1"; shift
	local profileName=$($_basename $profile)
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"
	local branch="${system}.${profileName}"
	local forceArg=
	for i in "$@"; do
		if [ "$i" = "--force" ]; then
			forceArg="--force"
		else
			usage | error "unknown argument: '$i'"
		fi
	done

	[ $action = "push" -o $action = "pull" ] ||
		error "pushpullMetadata(): first arg must be (push|pull)" < /dev/null

	# First verify that the clone has an origin defined.
	# XXX: BUG no idea why, but this is reporting origin twice
	#      when first creating the repository; hack with sort.
	local origin=$(getSetOrigin "$profile" "$system" | $_sort -u)

	# Perform a fetch to get remote data into sync.
	githubHelperGit -C "$profileMetaDir" fetch origin

	# Create an ephemeral clone with which to perform the synchronization.
	local tmpDir=$($_mktemp -d)
	$invoke_git clone --quiet --shared "$profileMetaDir" $tmpDir

	# Add the upstream remote to the ephemeral clone.
	$invoke_git -C $tmpDir remote add upstream $origin
	githubHelperGit -C $tmpDir fetch --quiet --all

	# Check out the relevant branch. Can be complicated in the event
	# that this is the first pull of a brand-new branch.
	if $invoke_git -C "$tmpDir" show-ref -q refs/heads/"$branch"; then
		$invoke_git -C "$tmpDir" checkout "$branch"
	elif $invoke_git -C "$tmpDir" show-ref -q refs/remotes/origin/"$branch"; then
		$invoke_git -C "$tmpDir" checkout --track origin/"$branch"
	elif $invoke_git -C "$tmpDir" show-ref -q refs/remotes/upstream/"$branch"; then
		$invoke_git -C "$tmpDir" checkout --track upstream/"$branch"
	else
		$invoke_git -C "$tmpDir" checkout --orphan "$branch"
		$invoke_git -C "$tmpDir" ls-files | $_xargs --no-run-if-empty $_git -C "$tmpDir" rm --quiet -f
		# A commit is needed in order to make the branch visible.
		$invoke_git -C "$tmpDir" commit --quiet --allow-empty \
			-m "$USER created profile"
		$invoke_git -C "$tmpDir" push --quiet --set-upstream origin "$branch"
	fi

	# Then push or pull.
	if [ "$action" = "push" ]; then
		githubHelperGit -C $tmpDir push $forceArg upstream origin/"$branch":refs/heads/"$branch" ||
			error "repeat command with '--force' to overwrite" < /dev/null
	elif [ "$action" = "pull" ]; then
		# Slightly different here; we first attempt to rebase and do
		# a hard reset if invoked with --force.
		if $invoke_git -C "$tmpDir" show-ref -q refs/remotes/upstream/"$branch"; then
			if [ -z "$forceArg" ]; then
				$invoke_git -C $tmpDir rebase --quiet upstream/"$branch" ||
					error "repeat command with '--force' to overwrite" < /dev/null
			else
				$invoke_git -C $tmpDir reset --quiet --hard upstream/"$branch"
			fi
			# Set receive.denyCurrentBranch=updateInstead before pushing
			# to update both the bare repository and the checked out branch.
			$invoke_git -C "$profileMetaDir" config receive.denyCurrentBranch updateInstead
			$invoke_git -C $tmpDir push $forceArg origin
			syncProfile "$profile" "$system"
		else
			error "branch '$branch' does not exist on $origin upstream" < /dev/null
		fi
	fi
	$invoke_rm -r -f $tmpDir
}

#
# listProfiles($system)
#
function listProfile() {
	trace "$@"
	local system="$1"; shift
	local profileMetaDir="$1"; shift
	local profileOwner=$($_basename $profileMetaDir)

	# Start by updating all remotes in the clone dir.
	githubHelperGit -C $profileMetaDir fetch --quiet --all

	# Derive all known branches. Recall branches will be of the form:
	#   remotes/origin/x86_64-linux.default
	#   remotes/upstream/x86_64-linux.default
	local -A _branches
	local -A _local
	local -A _origin
	local -a _cline
	. <($invoke_git -C $profileMetaDir branch -av | $_sed 's/^\*//' | while read -a _cline
		do
			_remote=$($_dirname "${_cline[0]}")
			_branch=$($_basename "${_cline[0]}")
			if [[ "$_branch" =~ ^$system.* ]]; then
				_revision="${_cline[1]}"
				case "$_remote" in
				"remotes/origin")
					echo "_branches[\"$_branch\"]=1"
					echo "_origin[\"$_branch\"]=\"$_revision\""
					;;
				"remotes/*")
					warn "unexpected remote '$_remote' in $profileMetaDir clone ... ignoring"
					;;
				*)
					echo "_branches[\"$_branch\"]=1"
					echo "_local[\"$_branch\"]=\"$_revision\""
					;;
				esac
			fi
		done
	)

	# Iterate over branches printing out everything we know.
	for _branch in $(echo ${!_branches[@]} | $_xargs -n 1 | $_sort); do
		local __local="${_local[$_branch]}"
		local __origin="${_origin[$_branch]}"
		local __commit="unknown"
		local -i __printCommit=0
		local __generation="unknown"
		local __name=${_branch##*.}
		local __path="$FLOX_ENVIRONMENTS/$profileOwner/$__name"
		local __alias="$profileOwner/$__name"
		local __localProfileOwner="local"
		if [ -L "$FLOX_ENVIRONMENTS/local" ]; then
			__localProfileOwner=$($_readlink "$FLOX_ENVIRONMENTS/local")
		fi
		if [ "$__localProfileOwner" = "$profileOwner" ]; then
			__alias="$__name"
		fi
		if [ -n "$__local" ]; then
			__commit="$__local"
			__generation=$($invoke_git -C $profileMetaDir show $__local:manifest.json | $_cut -d. -f1)
		fi
		if [ -n "$__origin" -a "$__origin" != "$__local" ]; then
			__commit="$__commit (remote $__origin)"
			__printCommit=1
			__generation="$__generation (remote $($invoke_git -C $profileMetaDir show $__origin:manifest.json | $_cut -d. -f1))"
		fi
		$_cat <<EOF
$profileOwner/$__name
    Alias     $__alias
    System    $system
    Path      $FLOX_ENVIRONMENTS/$profileOwner/$__name
    Curr Gen  $__generation
EOF
		if [ $verbose -eq 0 ]; then
			[ $__printCommit -eq 0 ] || echo "    Commit    $__commit"
		else
			$_cat <<EOF
    Branch    $profileOwner/$_branch
    Commit    $__commit
EOF
		fi
		echo ""
	done
}

#
# listProfiles($system)
#
function listProfiles() {
	trace "$@"
	local system="$1"; shift

	# For each profileMetaDir, list profiles
	for i in $FLOX_META/*; do
		if [ -d $i ]; then
			[ -L $i ] || listProfile $system $i
		fi
	done
}

#
# destroyProfile($profile,$system)
#
# This function entirely removes a profile's manifestation on disk
# and deletes the associated branch from the local floxmeta repository,
# and on the "origin" repository as well if invoked with `--origin`.
#
function destroyProfile() {
	trace "$@"
	local profile="$1"; shift
	local system="$1"; shift
	local profileDir=$($_dirname $profile)
	local profileName=$($_basename $profile)
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"
	local branch="${system}.${profileName}"
	local originArg=
	for i in "$@"; do
		if [ "$i" = "--origin" ]; then
			originArg="--origin"
		else
			usage | error "unknown argument: '$i'"
		fi
	done

	warn "WARNING: you are about to delete the following:"
	warn " - $profileDir/$profileName{,-*-link}"
	warn " - the $branch branch in $profileMetaDir"
	local origin
	[ -z "$originArg" ] || {
		# XXX: BUG no idea why, but this is reporting origin twice
		#      when first creating the repository; hack with sort.
		origin=$(getSetOrigin "$profile" "$system" | $_sort -u)
		warn " - the $branch branch in $origin"
	}
	if boolPrompt "Are you sure?" "no"; then
		# Start by changing to the (default) floxmain branch to ensure
		# we're not attempting to delete the current branch.
		if $invoke_git -C "$profileMetaDir" checkout --quiet "$defaultBranch" 2>/dev/null; then
			# Ensure following commands always succeed so that subsequent
			# invocations can reach the --origin remote removal below.
			$invoke_git -C "$profileMetaDir" branch -D "$branch" || true
			$invoke_git -C "$profileMetaDir" branch -rd origin/"$branch" || true
		fi
		$invoke_rm --verbose -f $profileDir/$profileName{,-*-link} || true
		[ -z "$originArg" ] || \
			githubHelperGit -C "$profileMetaDir" push origin --delete "$branch"
	else
		warn "aborted"
		exit 1
	fi
}

function subscribeFlake() {
	trace "$@"
	local flakeName
	if [ $# -gt 0 ]; then
		flakeName="$1"; shift
	else
		read -e -p "Enter channel name to be added: " flakeName
	fi
	[[ "$flakeName" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] ||
		error "invalid channel name '$flakeName', valid regexp: ^[a-zA-Z][a-zA-Z0-9_-]*$" < /dev/null
	local flakeUrl
	if [ $# -gt 0 ]; then
		flakeUrl="$1"; shift
		validateFlakeURL $flakeUrl || \
			error "could not verify channel URL: \"$flakeUrl\"" < /dev/null
		registry $floxUserMeta 1 set channels "$flakeName" "$flakeUrl"
	else
		flakeUrl=$(registry $floxUserMeta 1 getPromptSet \
			"Enter URL for '$flakeName' channel: " \
			$(gitBaseURLToFlakeURL ${gitBaseURL} ${flakeName}/floxpkgs master) \
			channels "$flakeName")
		validateFlakeURL $flakeUrl || {
			registry $floxUserMeta 1 delete channels "$flakeName"
			error "could not verify channel URL: \"$flakeUrl\"" < /dev/null
		}
	fi
}

function unsubscribeFlake() {
	trace "$@"
	local flakeName
	if [ $# -gt 0 ]; then
		flakeName="$1"; shift
	else
		read -e -p "Enter channel name to be removed: " flakeName
	fi
	if [ ${validChannels["$flakeName"]+_} ]; then
		registry $floxUserMeta 1 delete channels "$flakeName"
	else
		error "invalid channel: $flakeName" < /dev/null
	fi
}

function listChannels() {
	trace "$@"
	local -a rows=($(registry $floxUserMeta 1 get channels | $_jq -r '
	  to_entries | sort_by(.key) | map(
	    "|\(.key)|\(.value)|"
	  )[]
	'))
	$invoke_gum format --type="markdown" -- "|Channel|URL|" "|---|---|" ${rows[@]}
}

# vim:ts=4:noet:syntax=bash
