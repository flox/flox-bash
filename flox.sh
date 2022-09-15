#!/bin/sh
#
# flox.sh - Flox CLI
#

# Ensure that the script dies on any error.
set -e
set -o pipefail

# Declare default values for debugging variables.
declare -i verbose=0
declare -i debug=0

# set -x if debugging, can never remember which way this goes so do both.
# Note need to do this here in addition to "-d" flag to be able to debug
# initial argument parsing.
test -z "${DEBUG_FLOX}" || FLOX_DEBUG="${DEBUG_FLOX}"
test -z "${FLOX_DEBUG}" || set -x

# Similar for verbose.
test -z "${FLOX_VERBOSE}" || verbose=1

# Import configuration, load utility functions, etc.
_prefix="@@PREFIX@@"
_prefix=${_prefix:-.}
_lib=$_prefix/lib
_etc=$_prefix/etc
_share=$_prefix/share

# If the first arguments are any of -d|--date, -v|--verbose or --debug
# then we consume this (and in the case of --date, its argument) as
# argument(s) to the wrapper and not the command to be wrapped. To send
# either of these arguments to the wrapped command put them at the end.
while [ $# -ne 0 ]; do
	case "$1" in
	--stability)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: missing argument to --stability flag" 1>&2
			exit 1
		fi
		export FLOX_STABILITY="$1"
		shift
		;;
	-d | --date)
		shift
		if [ $# -eq 0 ]; then
			error "missing argument to --date flag" </dev/null
		fi
		export FLOX_RENIX_DATE="$1"
		shift
		;;
	-v | --verbose)
		let ++verbose
		shift
		;;
	--debug)
		let ++debug
		[ $debug -le 1 ] || set -x
		let ++verbose
		shift
		;;
	--prefix)
		echo "$_prefix"
		exit 0
		;;
	-V | --version)
		echo "Version: @@VERSION@@"
		exit 0
		;;
	-h | --help)
		# Perform initialization to pull in usage().
		. $_lib/init.sh
		usage
		exit 0
		;;
	*) break ;;
	esac
done

# Perform initialization with benefit of flox CLI args set above.
. $_lib/init.sh

#
# main()
#

# Start by identifying subcommand to be invoked.
# FIXME: use getopts to properly scan args for first non-option arg.
while test $# -gt 0; do
	case "$1" in
	-*)
		error "unrecognised option before subcommand" </dev/null
		;;
	*)
		subcommand="$1"
		shift
		break
		;;
	esac
done
if [ -z "$subcommand" ]; then
	usage | error "command not provided"
fi

# Flox aliases
if [ "$subcommand" = "rm" ]; then
	subcommand=remove
fi

# Store the original invocation arguments.
invocation_args="$@"

# Flox profile path(s).
declare -a profiles=()

# Build log message as we go.
logMessage=

case "$subcommand" in

# Flox commands which take an (-e|--environment) environment argument.
# Also accept (-p|--profile) as the legacy form of this argument.
activate | history | install | list | remove | rollback | \
	switch-generation | upgrade | wipe-history | \
	cat | edit | generations | git | push | pull | destroy | sync)

	# Look for the --profile argument(s).
	args=()
	while test $# -gt 0; do
		case "$1" in
		-e | --environment | -p | --profile)
			profiles+=($(profileArg $2))
			shift 2
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	if [ ${#profiles[@]} -eq 0 ]; then
		profiles+=($(profileArg "default"))
	fi

	# Only the "activate" subcommand accepts multiple profiles.
	if [ "$subcommand" != "activate" -a ${#profiles[@]} -gt 1 ]; then
		usage | error "\"$subcommand\" does not accept multiple -p|--profile arguments"
	fi

	profile=${profiles[0]}
	profileName=$($_basename $profile)
	profileOwner=$($_basename $($_dirname $profile))
	profileMetaDir="$FLOX_META/$profileOwner"
	profileStartGen=$(profileGen "$profile")

	[ $verbose -eq 0 ] || [ "$subcommand" = "activate" ] || echo Using environment: $profile >&2

	case "$subcommand" in

	activate)
		# This is challenging because it is invoked in three contexts:
		# * with arguments: prepend profile bin directories to PATH and
		#   invoke the commands provided, else ...
		# * interactive: we need to take over the shell "rc" entrypoint
		#   so that we can guarantee to prepend to the PATH *AFTER* all
		#   other processing has been completed, else ...
		# * non-interactive: here we simply prepend to the PATH and set
		#   required env variables.

		# Build up string to be prepended to PATH. Add in order provided,
		# and always add "default" to end of the list.
		_flox_path_prepend=
		for i in "${profiles[@]}" $(profileArg "default"); do
			[ -d "$i/." ] || warn "INFO environment not found: $i"
			_flox_path_prepend="${_flox_path_prepend:+$_flox_path_prepend:}$i/bin"
		done
		removePathDups _flox_path_prepend
		export FLOX_PATH_PREPEND="${_flox_path_prepend}"

		cmdArgs=()
		inCmdArgs=0
		for arg in "${args[@]}"; do
			case "$arg" in
			--)
				inCmdArgs=1
				;;
			*)
				if [ $inCmdArgs -eq 1 ]; then
					cmdArgs+=("$arg")
				else
					usage | error "unexpected argument \"$arg\" passed to \"$subcommand\""
				fi
				;;
			esac
		done

		if [ ${#cmdArgs[@]} -gt 0 ]; then
			export PATH="$FLOX_PATH_PREPEND:$PATH"
			. <(manifestTOML "$profileMetaDir/manifest.toml" bashInit)
			cmd=("invoke" "${cmdArgs[@]}")
		else
			case "$SHELL" in
			*bash)
				if [ -t 1 ]; then
					# TODO: export variable for setting flox env from within flox.profile,
					# *after* the PATH has been set.
					. <(manifestTOML "$profileMetaDir/manifest.toml" bashInit)
					cmd=("invoke" "$SHELL" "--rcfile" "$_etc/flox.bashrc")
				else
					echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\"; source $_etc/flox.profile"
					manifestTOML "$profileMetaDir/manifest.toml" bashInit
					exit 0
				fi
				;;
			*zsh)
				if [ -t 1 ]; then
					# TODO: export variable for setting flox env from within flox.profile,
					# *after* the PATH has been set.
					. <(manifestTOML "$profileMetaDir/manifest.toml" bashInit)
					if [ -n "$ZDOTDIR" ]; then
						export FLOX_ORIG_ZDOTDIR="$ZDOTDIR"
					fi
					export ZDOTDIR="$_etc/flox.zdotdir"
					cmd=("invoke" "$SHELL")
				else
					echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\"; source $_etc/flox.profile"
					manifestTOML "$profileMetaDir/manifest.toml" bashInit
					exit 0
				fi
				;;
			*)
				if [ -t 1 ]; then
					warn "unsupported shell: \"$SHELL\""
					warn "Launching bash instead"
					export SHELL="$_bash"
					. <(manifestTOML "$profileMetaDir/manifest.toml" bashInit)
					cmd=("invoke" "$SHELL" "--rcfile" "$_etc/flox.bashrc")
				else
					error "unsupported shell: \"$SHELL\" - please run 'flox activate' in interactive mode" </dev/null
				fi
				;;
			esac
		fi

		# Finally, undefine $profile so we don't audit profiles.
		profile=
		;;

	# Imperative commands which accept a flox package reference.
	install | remove | upgrade)
		pkgArgs=()
		pkgNames=()
		impureArg=
		if [ "$subcommand" = "install" -o "$subcommand" = "upgrade" ]; then
			impureArg="--impure"
		fi
		if [ "$subcommand" = "install" ]; then
			# Nix will create a profile directory, but not its parent.
			[ -d $($_dirname $profile) ] ||
				$_mkdir -v -p $($_dirname $profile) 2>&1 | $_sed -e "s/[^:]*:/${me}:/"
			for pkg in ${args[@]}; do
				case "$pkg" in
				-*) # don't try to interpret option as floxpkgArg.
					pkgArgs+=("$pkg")
					;;
				*)
					pkgArgs+=($(floxpkgArg "$pkg"))
					;;
				esac
			done
			# Infer floxpkg name(s) from floxpkgs flakerefs.
			for pkgArg in ${pkgArgs[@]}; do
				case "$pkgArg" in
				${floxpkgsUri}*)
					# Look up floxpkg name from flox flake prefix.
					pkgNames+=($(manifest $profile/manifest.json flakerefToFloxpkg "$pkgArg")) ||
						error "failed to look up floxpkg reference for flake \"$pkgArg\"" </dev/null
					;;
				*)
					pkgNames+=("$pkgArg")
					;;
				esac
			done
		else
			# The remove and upgrade commands operate on flake references and
			# require the package to be present in the manifest. Take this
			# opportunity to look up the flake reference from the manifest.
			#
			# NIX BUG: the remove and upgrade commands are supposed to
			# accept flake references but those don't work at present.  :(
			# Take this opportunity to look up flake references in the
			# manifest and then remove or upgrade them by position only.
			for pkg in ${args[@]}; do
				case "$pkg" in
				-*) # Don't try to interpret option as floxpkgArg.
					pkgArg="$pkg"
					;;
				*)
					pkgArg=$(floxpkgArg "$pkg")
					;;
				esac
				pkgArg=$(floxpkgArg "$pkg")
				position=
				if [[ "$pkgArg" == *#* ]]; then
					position=$(manifest $profile/manifest.json flakerefToPosition "$pkgArg") ||
						error "package \"$pkg\" not found in profile $profile" </dev/null
				elif [[ "$pkgArg" =~ ^[0-9]+$ ]]; then
					position="$pkgArg"
				else
					position=$(manifest $profile/manifest.json storepathToPosition "$pkgArg") ||
						error "package \"$pkg\" not found in profile $profile" </dev/null
				fi
				pkgArgs+=($position)
			done
			# Look up floxpkg name(s) from position.
			for position in ${pkgArgs[@]}; do
				pkgNames+=($(manifest $profile/manifest.json positionToFloxpkg "$position")) ||
					error "failed to look up package name for position \"$position\" in profile $profile" </dev/null
			done
		fi
		logMessage="$USER $(pastTense $subcommand) ${pkgNames[@]}"
		cmd=($invoke_nix -v profile "$subcommand" --profile "$profile" $impureArg "${pkgArgs[@]}")
		;;

	cat|edit)
		if [ "$subcommand" = "cat" ]; then
			editorCommand="$_cat"
		else
			[ -t 1 ] ||
				usage | error "\"$subcommand\" requires an interactive terminal"
		fi
		metaEdit "$profile" "$NIX_CONFIG_system"

		declare -a installables=($(manifestTOML "$profileMetaDir/manifest.toml" installables))

		# Convert this list of installables to a list of floxpkgArgs.
		declare -a floxpkgArgs
		for i in "${installables[@]}"; do
			floxpkgArgs+=($(floxpkgArg "$i"))
		done

		# Now we use this list of floxpkgArgs to create a temporary profile.
		tmpdir=$($_mktemp -d)
		$invoke_nix profile install --impure --profile $tmpdir/profile "${floxpkgArgs[@]}"

		# If we've gotten this far we have a profile. Follow the links to
		# identify the package, then (carefully) discard the tmpdir.
		profilePackage=$(cd $tmpdir && readlink $(readlink profile))
		$_rm $tmpdir/profile $tmpdir/profile-1-link
		$_rmdir $tmpdir

		# Finally, activate the new generation just as Nix would have done.
		# First check to see if profile has actually changed.
		oldProfilePackage=$($_realpath $profile)
		if [ "$profilePackage" != "$oldProfilePackage" ]; then
			logMessage="$USER edited declarative profile"
			declare -i newgen=$(maxProfileGen $profile)
			let ++newgen
			$invoke_ln -s $profilePackage "${profile}-${newgen}-link"
			$invoke_rm -f $profile
			$invoke_ln -s "${profileName}-${newgen}-link" $profile
		fi

		# Need a command to trigger post-command profile reconciliation.
		cmd=(:) # shell built-in
		;;

	rollback | switch-generation | wipe-history)
		if [ "$subcommand" = "switch-generation" ]; then
			# rewrite switch-generation to instead use the new
			# "rollback --to" command (which makes no sense IMO).
			subcommand=rollback
			args=("--to" "${args[@]}")
		fi
		targetGeneration="UNKNOWN"
		for index in "${!args[@]}"; do
			case "${args[$index]}" in
			--to) targetGeneration="${args[$(($index + 1))]}"; break;;
			   *) ;;
			esac
		done
		logMessage="$USER $(pastTense $subcommand) $targetGeneration"
		cmd=($invoke_nix profile "$subcommand" --profile "$profile" "${args[@]}")
		;;

	list)
		if [ ${#args[@]} -gt 0 ]; then
			# First argument to list can be generation number.
			if [[ ${args[0]} =~ ^[0-9]*$ ]]; then
				if [ -e "$profile-${args[0]}-link" ]; then
					profileStartGen=${args[0]}
					args=(${args[@]:1}) # aka shift
					profile="$profile-$profileStartGen-link"
				fi
			fi
		fi
		_profilePath="$FLOX_ENVIRONMENTS/$profileOwner/$profileName"
		_profileAlias="$profileOwner/$profileName"
		if [ -e "$_profilePath" -a "$($_realpath $_profilePath)" = "$($_realpath $FLOX_ENVIRONMENTS/local/$profileName)" ]; then
			_profileAlias="$profileName"
		fi
		$_cat <<EOF
$profileOwner/$profileName
    Alias     $_profileAlias
    System    $NIX_CONFIG_system
    Path      $FLOX_ENVIRONMENTS/$profileOwner/$profileName
    Curr Gen  $profileStartGen

Packages
EOF
		if [ $verbose -eq 1 ]; then
			# Increase verbosity when invoking list command.
			let ++verbose
		fi
		manifest $profile/manifest.json listProfile "${args[@]}" | $_sed 's/^/    /'
		;;

	history)
		if [[ "$profile" =~ ^$FLOX_ENVIRONMENTS ]]; then
			# Default to verbose log format (like git).
			logFormat="format:%cd %C(cyan)%B%Creset"

			# Step through args looking for (--oneline).
			for arg in ${args[@]}; do
				case "$arg" in
				--oneline)
					# If --oneline then just include log subjects.
					logFormat="format:%cd %C(cyan)%s%Creset"
					;;
				-v | --verbose) # deprecated
					# If verbose (default) then add body as well.
					logFormat="format:%cd %C(cyan)%B%Creset"
					;;
				-*)
					error "unknown option \"$opt\"" </dev/null
					;;
				*)
					error "extra argument \"$opt\"" </dev/null
					;;
				esac
			done
			metaGit "$profile" "$NIX_CONFIG_system" log --pretty="$logFormat"
		else
			# Assume plain Nix profile - launch Nix version.
			cmd=($invoke_nix profile "$subcommand" --profile "$profile" "${args[@]}")
			# Clear $profile to avoid post-processing.
			profile=
		fi
		;;

	# Flox commands

	generations)
		# Infer existence of generations from the registry (i.e. the database),
		# rather than the symlinks on disk so that we can have a history of all
		# generations long after they've been deleted for the purposes of GC.
		profileRegistry "$profile" listGenerations
		;;

	git)
		profileDir=$($_dirname $profile)
		profileName=$($_basename $profile)
		profileOwner=$($_basename $($_dirname $profile))
		profileMetaDir="$FLOX_META/$profileOwner"
		githubHelperGit -C $profileMetaDir ${args[@]}
		;;

	push | pull)
		pushpullMetadata "$subcommand" "$profile" "$NIX_CONFIG_system" ${args[@]}
		;;

	destroy)
		destroyProfile "$profile" "$NIX_CONFIG_system" ${args[@]}
		;;

	sync)
		cmd=(:)
		;;

	*)
		usage | error "Unknown command: $subcommand"
		;;

	esac
	;;

# The profiles subcommand takes no arguments.
envs | environments | profiles)
	listProfiles "$NIX_CONFIG_system"
	;;

# The diff-closures command takes two profile arguments.
diff-closures)
	# Step through remaining arguments sorting options from args.
	opts=()
	args=()
	for arg in $@; do
		case "$arg" in
		-*)
			opts+=("$1")
			;;
		*)
			args+=$(profileArg "$1")
			;;
		esac
	done
	cmd=($invoke_nix "$subcommand" "${opts[@]}" "${args[@]}")
	;;

build)
	cmd=($invoke_nix "$subcommand" "$@" --impure)
	;;

develop)
    #TODO eventually we will only add --impure when using fake derivation.
	cmd=($invoke_nix "$subcommand" "$@" --impure)
	;;

gh)
	cmd=($invoke_gh "$@")
	;;

init)
	if [ -z "$FLOXDEMO" ]; then
		choice=$(promptTemplate)
	else
		choice="python-black"
	fi
	cmd=($invoke_nix flake init --template "floxpkgs#templates.$choice" "$@")
	;;

packages|search)
	packageregexp=
	declare -i jsonOutput=0
	searchCmd="search"
	for arg in "$@"; do
		case "$arg" in
		--show-libs)
			# Not yet supported; will implement when catalog has hasBin|hasMan.
			shift
			;;
		--all)
			packageregexp="."
			shift
			;;
		--refresh)
			searchCmd="search --refresh"
			shift
			;;
		--json)
			jsonOutput=1
			shift
			;;
		*)
			if [ "$subcommand" = "packages" ]; then
				# Expecting a channel name (and optionally a jobset).
				packageregexp="^$arg\."
			elif [ -z "$packageregexp" ]; then
				# Expecting a package name (or part of a package name)
				packageregexp="$arg"
				# In the event that someone has passed a space or "|"-separated
				# search term (thank you Eelco :-\), turn that into an equivalent
				# regexp.
				if [[ "$packageregexp" =~ [:space:] ]]; then
					packageregexp="(${packageregexp// /|})"
				fi
			else
				usage | error "multiple search terms provided"
			fi
			shift
			;;
		esac
	done
	[ -n "$packageregexp" ] ||
		usage | error "missing channel argument"
	[ -z "$@" ] ||
		usage | error "extra arguments \"$@\""
	if [ -z "$GREP_COLOR" ]; then
		export GREP_COLOR='1;32'
	fi
	if [ $jsonOutput -gt 0 ]; then
		cmd=($invoke_nix $searchCmd --json "flake:floxpkgs#$catalogSearchAttrPathPrefix" "$packageregexp")
	else
		# Use grep to highlight text matches, but also include all the lines
		# around the matches by using the `-C` context flag with a big number.
		# It's also unfortunate that the Linux version of `column` which
		# supports the `--keep-empty-lines` option is not available on Darwin,
		# so we instead embed a line with "---" between groupings and then use
		# `sed` below to replace it with a blank line.
		$invoke_nix $searchCmd --json "flake:floxpkgs#$catalogSearchAttrPathPrefix" "$packageregexp" | \
			$_jq -r -f "$_lib/search.jq" | $_column -t -s "|" | $_sed 's/^---$//' | \
			$_grep -C 1000000 --ignore-case --color -E "$packageregexp"
	fi
	;;

nixpackages)
	# iterate over all known flakes listing valid floxpkgs tuples.
	for flake in $(flakeRegistry get flakes | $_jq -r '.[] | .from.id'); do
		$_nix eval "flake:${flake}#__index.${NIX_CONFIG_system}" --json | jq --stream 'select(length==2)|.[0]|join(".")' -cr
	done
	;;

builds)
		$_nix eval "$floxpkgsUri#cachedPackages.${NIX_CONFIG_system}.$1"  --json --impure --apply 'builtins.mapAttrs (_k: v: v.meta )'  | $_jq -r '["Build Date","Name/Version","Description","Package Ref"], ["-----------","------------","-----------","-------"], ([.[]] | sort_by(.revision_epoch) |.[] |  [(.revision_epoch|(strftime("%Y-%m-%d"))), .name, .description, .flakeref]) | @tsv' | $_column -ts "$(printf '\t')"
	;;

shell)
	cmd=($invoke_nix "$subcommand" "$@")
	;;

# Special "cut-thru" mode to invoke Nix directly.
nix)
	cmd=($invoke_nix "$@")
	;;

update)
	$invoke_nix run floxpkgs#update-versions "$PWD"
	$invoke_nix run floxpkgs#update-extensions "$PWD"
	;;

config)
	declare -i configListMode=0
	declare -i configResetMode=0
	for arg in "$@"; do
		case "$arg" in
		--list|-l)
			configListMode=1
			shift
			;;
		--reset|-r)
			configResetMode=1
			shift
			;;
		*)
			usage | error "unexpected argument \"$arg\" passed to \"$subcommand\""
			;;
		esac
	done
	if [ $configResetMode -eq 1 ]; then
		# Easiest way to reset is to simply remove the $floxUserMeta file.
		$invoke_rm -f $floxUserMeta
	fi
	if [ $configListMode -eq 0 ]; then
		# Re-run bootstrap with getPromptSetConfirm=1
		getPromptSetConfirm=1
		. $_lib/bootstrap.sh
	fi
	# Finish by listing values.
	registry $floxUserMeta 1 dump |
		$_jq -r 'del(.version) | to_entries | map("\(.key) = \"\(.value)\"") | .[]'
	exit 0
	;;
publish)
	declare -a binaryCaches=()
	declare -a subs=()
	declare -a substituters=()
	while getopts ":t:f:a:s:b:r:p:" opt; do
		case "${opt}" in
			t) target="$OPTARG";;
			f) remote="$OPTARG";;
			s) subs+=("$OPTARG");;
			b) binaryCaches+=("$OPTARG");; 
			a) attrpath="$OPTARG";;
			r) renderpath="$OPTARG";;
			p) floxpkgs="$OPTARG";;
		esac
	done
	shift $((OPTIND -1))
	for val in "${subs[@]}"; do
			substituters+=("--substituter")
			substituters+=($val)
	done

	if [ -z "$renderpath" ]; then
		renderpath="./catalog"
		warn "No -r argument supplied, using default $renderpath"
	fi
	if [ -z "$remote" ]; then
		remote="./."
		warn "No -f argument supplied, using local directory"
	fi
	if [ -z "$target" ]; then
		target="."
		warn "No -t argument supplied, using local directory"
	fi
	
	warn "Checking build status of this package"
	#TODO implement flox generate-signing-key command
	signingSecretKey="$HOME/.config/flox/secret-key"
	# if [ -f "$signingSecretKey" ]; then
	# warn "$signingSecretKey exists."
	# TODO: fix when stability definition changes in capacitor
	$invoke_nix build "$target#legacyPackages.$attrpath"
	# TODO for now we work with result
	# in the future we may need to output --json on nix build
	# and process the "outputs" array on that data
	if [ -d "./result" ]
	then
		result="./result"
	fi
	if [ -d "./result-bin" ]
	then
		result="./result-bin"
	fi
	#TODO in future iterations, we will clean this up so that make content addressed works
	# this will involve populating a variable ca_out=$($invoke_nix store make-content-addressed ./result --json | jq .rewrites[])
	for substituter in "${binaryCaches[@]}"
	do
		[[ "$substituter" == "--substituter" ]] && continue
		$invoke_nix copy --to $substituter $result
	done
		 
	# else
	# 	error "$signingSecretKey does not exist. please first run flox generate-signing-key"
	# fi

	if [ ! -z "$floxpkgs" ]; then
		gitdir="$(mktemp -d)/"
		$invoke_gh repo clone "$floxpkgs" "$gitdir"
	else
		warn "no remote floxpkgs set, rendering catalog entry locally"
		gitdir="./"
	fi

	warn "Publishing render to $renderpath ..."
	$invoke_nix run "github:flox/catalog-ingest/fix-analyze#analyze" --no-write-lock-file --refresh -- "$target" "$attrpath" "$remote"  \
	|	$invoke_nix run "github:flox/floxpkgs#builtfilter" -- "${substituters[@]}" \
	|	$invoke_nix run "github:flox/catalog-ingest#publish"  --no-write-lock-file -- "$gitdir$renderpath"
	warn "Flox Publish completed"
	$_rm $result

	
	if [ ! -z "$floxpkgs" ]; then
		pushd "$gitdir"
		git add .
		git commit -m "Update Catalog"
		git push
		popd
	fi
	;;

help)
	cmd=($invoke_man -l "$_share/man/man1/flox.1.gz")
	;;

*)
	cmd=($invoke_nix "$subcommand" "$@")
	;;
esac

[ ${#cmd[@]} -gt 0 ] || exit 0

"${cmd[@]}"
if [ -n "$profile" ]; then
	profileEndGen=$(profileGen "$profile")
	if [ -n "$profileStartGen" ]; then
		logMessage="Generation ${profileStartGen}->${profileEndGen}: $logMessage"
	else
		logMessage="Generation ${profileEndGen}: $logMessage"
	fi
	syncMetadata \
		"$profile" \
		"$NIX_CONFIG_system" \
		"$profileStartGen" \
		"$profileEndGen" \
		"$logMessage" \
		"flox $subcommand ${invocation_args[@]}"
	if [ "$profileStartGen" != "$profileEndGen" ]; then
		# Follow up action with sync'ing of profiles in reverse.
		syncProfile "$profile" "$NIX_CONFIG_system"
	fi
fi

# vim:ts=4:noet:syntax=bash
