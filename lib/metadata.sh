#
# Subroutines for management of "floxmeta" environment metadata repo.
#
# This module provides functions to manage the user's environment metadata
# repository in conjunction with the generational links pointing to the flox
# environment packages in the store.
#
# The profile metadata repository contains copies of all source files required
# to create each generation in a subdirectory corresponding with the generation
# number. This includes a flake.{nix,lock} pair which enables the directory to
# be built as a standalone package if desired.
#
# There is one metadata repository per user and each profile is represented
# as a separate branch. See https://github.com/flox/flox/issues/14.
#

# Example hierarchy (temporary during refactoring):
# .
# ├── limeytexan (x86_64-linux.default branch)
# │   ├── 1
# │   │   ├── manifest.toml
# │   │   └── manifest.json
# │   └── metadata.json
# ├── limeytexan (x86_64-linux.toolbox branch)
# │   ├── 1
# │   │   ├── manifest.toml
# │   │   └── manifest.json
# │   ├── 2
# │   │   ├── manifest.toml
# │   │   └── manifest.json
# │   └── metadata.json
# └── tomberek (aarch64-darwin.default branch)
#     ├── 1
#     │   ├── manifest.toml
#     │   └── manifest.json
#     ├── 2
#     │   ├── manifest.toml
#     │   └── manifest.json
#     ├── 3
#     │   ├── manifest.toml
#     │   └── manifest.json
#     └── metadata.json

# Example hierarchy (unification):
# .
# ├── limeytexan (x86_64-linux.default branch)
# │   ├── 1
# │   │   ├── flake.lock
# │   │   ├── flake.nix
# │   │   └── pkgs
# │   │       └── default
# │   │           ├── catalog.json
# │   │           └── flox.nix
# │   └── metadata.json
# ├── limeytexan (x86_64-linux.toolbox branch)
# │   ├── 1
# │   │   ├── flake.lock
# │   │   ├── flake.nix
# │   │   └── pkgs
# │   │       └── default
# │   │           ├── catalog.json
# │   │           └── flox.nix
# │   ├── 2
# │   │   ├── flake.lock
# │   │   ├── flake.nix
# │   │   └── pkgs
# │   │       └── default
# │   │           ├── catalog.json
# │   │           └── flox.nix
# │   └── metadata.json
# └── tomberek (aarch64-darwin.default branch)
#     ├── 1
#     │   ├── flake.lock
#     │   ├── flake.nix
#     │   └── pkgs
#     │       └── default
#     │           ├── catalog.json
#     │           └── flox.nix
#     ├── 2
#     │   ├── flake.lock
#     │   ├── flake.nix
#     │   └── pkgs
#     │       └── default
#     │           ├── catalog.json
#     │           └── flox.nix
#     ├── 3
#     │   ├── flake.lock
#     │   ├── flake.nix
#     │   └── pkgs
#     │       └── default
#     │           ├── catalog.json
#     │           └── flox.nix
#     └── metadata.json

#
# "Public" functions exposed by this module:
#
# * syncEnvironment(): reconciles/updates profile data from metadata repository
# * pullMetadata(): pulls metadata updates from upstream to local cache
# * pushMetadata(): pushes metadata updates from local cache to upstream
# * metaGit():      provides access to git commands for metadata repo
# * metaGitShow():  used to print file contents without checking out branch
#
# Many git conventions employed here are borrowed from Nix's own
# src/libfetchers/git.cc file.
#

snipline="------------------------ >8 ------------------------"
declare protoManifestToml=$($_cat <<EOF
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

# XXX TEMPORARY function to convert old-style "1.json" -> "1/manifest.json"
#     **Delete after 20221215**
function temporaryAssert007Schema {
	trace "$@"
	local repoDir="$1"; shift

	# Use the presence of manifest.toml in the top directory as
	# an indication that the repository has NOT been converted.
	[ -e "$repoDir/manifest.toml" ] || return 0

	# Prompt user to confirm they want to change the format.
	warn "floxmeta repository ($repoDir) using deprecated (<=0.0.6) format."
	$invoke_gum confirm "Convert to latest (>=0.0.7) format?"

	# Rename/move each file.
	for file in $($_git -C "$repoDir" ls-files); do
		case "$file" in
		[0-9]*.json)
			local gen=$($_basename "$file" .json)
			$invoke_mkdir -p "$repoDir/${gen}"
			$invoke_git -C "$repoDir" mv "$file" "${gen}/manifest.json"
			# Constructing the manifest.toml is not as straightforward.
			# The pre-0.0.7 format didn't include a generation-specific
			# manifest.toml, but rather forced you to go back to a previous
			# git commit to find the corresponding version. Worse than that,
			# when doing rollbacks and other generation flips the top half
			# of the manifest.toml didn't change, which was arguably wrong
			# (although appreciated as a feature by some).
			#
			# To create the old generation-specific manifest start by
			# including everything up to the snipline.
			$invoke_git -C "$repoDir" show "HEAD:manifest.toml" | \
				$_awk "{if (/$snipline/) {exit} else {print}}" > "$repoDir/$gen/manifest.toml"
			# Then use the current generation's manifest.json to create
			# the rest.
			echo "# $snipline" >> "$repoDir/$gen/manifest.toml"
			manifest "$repoDir/$gen/manifest.json" listEnvironmentTOML >> "$repoDir/$gen/manifest.toml"
			$invoke_git -C "$repoDir" add "$gen/manifest.toml"
			;;
		manifest.json)
			$invoke_git -C "$repoDir" rm "$file" ;;
		manifest.toml)
			$invoke_git -C "$repoDir" rm "$file" ;;
		metadata.json)
			: leave intact ;;
		*)
			error "unknown file \"$file\" in $repoDir repository" < /dev/null
			;;
		esac
	done

	# Commit, reading commit message from STDIN.
	$invoke_git -C "$repoDir" commit \
		--quiet -m "$USER converted to 0.0.7 floxmeta schema"
	$invoke_git -C $repoDir push --quiet

	warn "Conversion complete. Please re-run command."
	exit 0
}
# /XXX

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

	# Confirm or checkout the desired branch.
	local currentBranch=
	if [ -d "$repoDir" ]; then
		currentBranch=$($_git -C "$repoDir" branch --show-current)
	fi
	[ "$currentBranch" = "$branch" ] || {
		if $_git -C "$repoDir" show-ref --quiet refs/heads/"$branch"; then
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

# githubHelperGit()
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
	local environment="$1"; shift
	local system="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"

	# First verify that the clone is not out of date and check
	# out requested branch.
	gitCheckout "$environmentMetaDir" "${system}.${environmentName}"

	githubHelperGit -C "$environmentMetaDir" "$@"
}

# Performs a 'git show branch:file' for the purpose of fishing
# out a file revision without checking out the branch.
function metaGitShow() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local filename="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"

	# First assert the relevant branch exists.
	if $_git -C "$environmentMetaDir" show-ref --quiet refs/heads/"$branch"; then
		$invoke_git -C "$environmentMetaDir" show "${branch}:${filename}"
	else
		error "environment '$environmentOwner/$environmentName' not found for system '$system'" < /dev/null
	fi
}

#
# syncEnvironment($environment,$system)
#
function syncEnvironment() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local environmentDir=$($_dirname $environment)
	local environmentName=$($_basename $environment)
	local environmentRealDir=$($_readlink -f $environmentDir)
	local environmentOwner=$($_basename $environmentRealDir)
	local environmentMetaDir="$FLOX_META/$environmentOwner"

	# Ensure metadata repo is checked out to correct branch.
	gitCheckout "$environmentMetaDir" "${system}.${environmentName}"

	# Run snippet to generate links using data from metadata repo.
	$_mkdir -v -p "$environmentRealDir" 2>&1 | $_sed -e "s/[^:]*:/${me}:/"

	# Invoking the following autogenerated code snippet will:
	# 1. build all the packages in a [nix] profile
	# 2. build the [nix] profile package itself
	# 3. create the GCroot symlinks and top generational symlink
	local snippet=$(environmentRegistry "$environmentMetaDir"/metadata.json "$environment" syncGenerations)
	eval "$snippet" || true

	# FIXME REFACTOR based on detecting actual change.
	[ -z "$_cline" ] || metaGit "$environment" "$system" add "metadata.json"
}

function commitMessage() {
	trace "$@"
	local environment="$1"; shift
	local -i startGen=$1; shift
	local -i endGen=$1; shift
	local logMessage="$1"; shift
	local invocation="${@}"
	local environmentName=$($_basename $environment)
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
	local tmpDir=$(mkTempDir)
	# `nix profile history` requires generations to be in sequential
	# order, so for the purpose of this invocation we set the generations
	# as 1 and 2 if both are defined, or 1 if there is only one generation.
	local myEndGen=
	if [ $startGen -gt 0 ]; then
		# If there is a start and end generation then set generat
		$invoke_ln -s $($_readlink "${environment}-${startGen}-link") $tmpDir/${environmentName}-1-link
		$invoke_ln -s $($_readlink "${environment}-${endGen}-link") $tmpDir/${environmentName}-2-link
		myEndGen=2
	else
		$invoke_ln -s $($_readlink "${environment}-${endGen}-link") $tmpDir/${environmentName}-1-link
		myEndGen=1
	fi
	$invoke_ln -s ${environmentName}-${myEndGen}-link $tmpDir/${environmentName}

	local _cline
	$_nix profile history --profile $tmpDir/${environmentName} | $_ansifilter --text | \
		$_awk '\
			BEGIN {p=0} \
			/^  flake:/ {if (p==1) {print $0}} \
			/^Version '${myEndGen}' / {p=1}' | \
		while read _cline
		do
			local flakeref=$(echo "$_cline" | $_cut -d: -f1,2)
			local detail=$(echo "$_cline" | $_cut -d: -f3-)
			local floxpkg=$(manifest $environment/manifest.json flakerefToFloxpkg "$flakeref")
			echo "  ${floxpkg}:${detail}"
		done

	$_rm -f \
		$tmpDir/"${environmentName}-1-link" \
		$tmpDir/"${environmentName}-2-link" \
		$tmpDir/"${environmentName}"
	$_rmdir $tmpDir
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
# getSetOrigin($environment)
#
function getSetOrigin() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"

	# Check to see if the origin is already set.
	local origin=$([ -d "$environmentMetaDir" ] && $_git -C "$environmentMetaDir" \
		"config" "--get" "remote.origin.url" || true)
	if [ -z "$origin" ]; then
		# Infer/set origin using a variety of information.
		local environmentName=$($_basename $environment)
		local environmentOwner=$($_basename $($_dirname $environment))
		local defaultOrigin=
		if [ "$environmentOwner" == "local" ]; then
			defaultOrigin=$(promptMetaOrigin)
		else
			# Strange to have a profile on disk in a named without a
			# remote origin. Prompt user to confirm floxmeta repo on
			# github.
			defaultOrigin="${gitBaseURL/+ssh/}$environmentOwner/floxmeta"
		fi

		echo 1>&2
		read -e \
			-p "confirm git URL for storing profile metadata: " \
			-i "$defaultOrigin" origin

		# A few final cleanup steps.
		if [ "$environmentOwner" == "local" ]; then
			local newEnvironmentOwner=$($_dirname $origin); newEnvironmentOwner=${newEnvironmentOwner/*[:\/]/} # XXX hack

			# rename .cache/flox/meta/{local -> owner} &&
			#   replace with symlink from local -> owner
			# use .cache/flox/meta/owner as environmentMetaDir going forward (only for this function though!)
			if [ -d "$FLOX_META/$newEnvironmentOwner" ]; then
				warn "moving profile metadata directory $FLOX_META/$newEnvironmentOwner out of the way"
				$invoke_mv --verbose $FLOX_META/$newEnvironmentOwner{,.$$}
			fi
			if [ -d "$FLOX_META/local" ]; then
				$invoke_mv "$FLOX_META/local" "$FLOX_META/$newEnvironmentOwner"
			fi
			$invoke_ln -s -f $newEnvironmentOwner "$FLOX_META/local"
			environmentMetaDir="$FLOX_META/$newEnvironmentOwner"

			# rename .local/share/flox/environments/{local -> owner}
			#   replace with symlink from local -> owner
			if [ -d "$FLOX_ENVIRONMENTS/$newEnvironmentOwner" ]; then
				warn "moving profile directory $FLOX_ENVIRONMENTS/$newEnvironmentOwner out of the way"
				$invoke_mv --verbose $FLOX_ENVIRONMENTS/$newEnvironmentOwner{,.$$}
			fi
			if [ -d "$FLOX_ENVIRONMENTS/local" ]; then
				$invoke_mv "$FLOX_ENVIRONMENTS/local" "$FLOX_ENVIRONMENTS/$newEnvironmentOwner"
			fi
			$invoke_ln -s -f $newEnvironmentOwner "$FLOX_ENVIRONMENTS/local"

			# perform single commit rewriting all URL references to refer to new home of floxmeta repo
			rewriteURLs "$FLOX_ENVIRONMENTS/local" "$origin"
		fi

		[ -d "$environmentMetaDir" ] || gitInit "$environmentMetaDir"
		$invoke_git -C "$environmentMetaDir" "remote" "add" "origin" "$origin"
	fi

	ensureGHRepoExists "$origin" private "https://github.com/flox/floxmeta-template.git"
	echo "$origin"
}

#
# beginTransaction($environment, $system, $workDir)
#
# This function creates an ephemeral clone for staging commits to
# a floxmeta repository.
#
function beginTransaction() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local workDir="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"

	# Perform a fetch to get remote data into sync.
	githubHelperGit -C "$environmentMetaDir" fetch origin

	# Create an ephemeral clone.
	$invoke_git clone --quiet --shared "$environmentMetaDir" $workDir

	# Check out the relevant branch. Can be complicated in the event
	# that this is the first pull of a brand-new branch.
	if $invoke_git -C "$workDir" show-ref --quiet refs/heads/"$branch"; then
		$invoke_git -C "$workDir" checkout --quiet "$branch"
	elif $invoke_git -C "$workDir" show-ref --quiet refs/remotes/origin/"$branch"; then
		$invoke_git -C "$workDir" checkout --quiet --track origin/"$branch"
	else
		$invoke_git -C "$workDir" checkout --quiet --orphan "$branch"
		$invoke_git -C "$workDir" ls-files | $_xargs --no-run-if-empty $_git -C "$workDir" rm --quiet -f
		# A commit is needed in order to make the branch visible.
		$invoke_git -C "$workDir" commit --quiet --allow-empty \
			-m "$USER created environment"
		$invoke_git -C "$workDir" push --quiet --set-upstream origin "$branch"
	fi

	# XXX Temporary covering transition from 0.0.6 -> 0.0.7
	temporaryAssert007Schema "$workDir"
	# /XXX

	# Any function calling this one will probably be wanting to make
	# some sort of change that will generate a new generation, so take
	# this opportunity to identify the current and next generations
	# and drop in helper symlinks pointing to the "current" and "next"
	# generations to make it easy for calling functions to make changes.
	# (But don't add them to the git index.)

	# Record starting generation.
	local -i startGen=$(registry "$workDir/metadata.json" 1 currentGen)
	if [ $startGen -gt 0 ]; then
		$invoke_ln -s $startGen "$workDir/current"
	fi

	# Calculate next available generation. Note this is _not_ just
	# (startGen + 1), but rather (max(generations) + 1) as recorded
	# in the environment registry. (We're no longer using symlinks
	# to record this in the floxmeta repo.)
	local -i nextGen=$(registry "$workDir/metadata.json" 1 nextGen)
	$invoke_mkdir -p $workDir/$nextGen
	$invoke_ln -s $nextGen $workDir/next
}

#
# commitTransaction($environment, $workDir, $logMessage)
#
# This function completes the process of committing updates to
# a floxmeta repository from an ephemeral clone.
#
function commitTransaction() {
	trace "$@"
	local environment="$1"; shift
	local workDir="$1"; shift
	local environmentPackage="$1"; shift
	local logMessage="$1"; shift
	local invocation="${@}"
	local environmentName=$($_basename $environment)

	# Glean current and next generations from clone.
	local -i currentGen=$($_readlink $workDir/current || echo 0)
	local -i nextGen=$($_readlink $workDir/next)

	# Activate the new generation just as Nix would have done.
	# First check to see if the environment has actually changed,
	# and if not then return immediately.
	oldEnvPackage=$($_realpath $environment)
	if [ "$environmentPackage" = "$oldEnvPackage" ]; then
		warn "No environment changes detected .. exiting"
		return 0
	fi

	# Update the floxmeta registry to record the new generation.
	registry "$workDir/metadata.json" 1 set currentGen $nextGen

	# Figure out if we're creating or switching to an existing generation.
	local createdOrSwitchedTo="created"
	if $invoke_jq -e --arg gen $nextGen '.generations | has($gen)' $workDir/metadata.json >/dev/null; then
		createdOrSwitchedTo="switched to"
	else
		# Update environment metadata with new end generation information.
		registry "$workDir/metadata.json" 1 set generations \
			${nextGen} path $environmentPackage
		registry "$workDir/metadata.json" 1 addArray generations \
			${nextGen} logMessage "$logMessage"
		registry "$workDir/metadata.json" 1 setNumber generations \
			${nextGen} created "$now"
		registry "$workDir/metadata.json" 1 setNumber generations \
			${nextGen} lastActive "$now"
	fi

	# Also update lastActive time for current generation, if known.
	[ $currentGen -eq 0 ] || \
		registry "$workDir/metadata.json" 1 setNumber generations \
			$currentGen lastActive "$now"

	# Mark the metadata.json file to be included with the commit.
	$invoke_git -C $workDir add "metadata.json"

	# Now that metadata is recorded, actually put the change
	# into effect. Must be done before calling commitMessage().
	if [ "$createdOrSwitchedTo" = "created" ]; then
		$invoke_nix_store --add-root "${environment}-${nextGen}-link" \
			-r $environmentPackage >/dev/null
	fi
	$invoke_rm -f $environment
	$invoke_ln -s "${environmentName}-${nextGen}-link" $environment

	# Commit, reading commit message from STDIN.
	commitMessage \
		"$environment" $currentGen $nextGen \
		"$logMessage" "${invocation[@]}" | \
		$invoke_git -C $workDir commit --quiet -F -
	$invoke_git -C $workDir push --quiet

	warn "$createdOrSwitchedTo generation $nextGen"
}

#
# listEnvironments($system)
#
function listEnvironments() {
	trace "$@"
	local system="$1"; shift
	local environmentMetaDir="$1"; shift
	local environmentOwner=$($_basename $environmentMetaDir)

	# Quick sanity check .. is this a git repo?
	[ -d "$environmentMetaDir/.git" ] || \
		error "not a git clone? Please remove: $environmentMetaDir" < /dev/null

	# Start by updating all remotes in the clone dir.
	githubHelperGit -C $environmentMetaDir fetch --quiet --all

	# Derive all known branches. Recall branches will be of the form:
	#   remotes/origin/x86_64-linux.default
	#   remotes/upstream/x86_64-linux.default
	local -A _branches
	local -A _local
	local -A _origin
	local -a _cline
	. <($invoke_git -C $environmentMetaDir branch -av | $_sed 's/^\*//' | while read -a _cline
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
					warn "unexpected remote '$_remote' in $environmentMetaDir clone ... ignoring"
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
		local __path="$FLOX_ENVIRONMENTS/$environmentOwner/$__name"
		local __alias="$environmentOwner/$__name"
		local __localEnvironmentOwner="local"
		if [ -L "$FLOX_ENVIRONMENTS/local" ]; then
			__localEnvironmentOwner=$($_readlink "$FLOX_ENVIRONMENTS/local")
		fi
		if [ "$__localEnvironmentOwner" = "$environmentOwner" ]; then
			__alias="$__name"
		fi
		if [ -n "$__local" ]; then
			local __metadata=$(mkTempFile)
			if $invoke_git -C $environmentMetaDir show $__local:metadata.json > $__metadata 2>/dev/null; then
				__commit="$__local"
				__generation=$($invoke_jq -r .currentGen $__metadata)
			fi
		fi
		if [ -n "$__origin" -a "$__origin" != "$__local" ]; then
			local __metadata=$(mkTempFile)
			if $invoke_git -C $environmentMetaDir show $__origin:metadata.json > $__metadata 2>/dev/null; then
				__commit="$__commit (remote $__origin)"
				__printCommit=1
				__generation=$($invoke_jq -r .currentGen $__metadata)
			fi
		fi
		$_cat <<EOF
$environmentOwner/$__name
    Alias     $__alias
    System    $system
    Path      $FLOX_ENVIRONMENTS/$environmentOwner/$__name
    Curr Gen  $__generation
EOF
		if [ $verbose -eq 0 ]; then
			[ $__printCommit -eq 0 ] || echo "    Commit    $__commit"
		else
			$_cat <<EOF
    Branch    $environmentOwner/$_branch
    Commit    $__commit
EOF
		fi
		echo ""
	done
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
