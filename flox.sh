#!/bin/sh
#
# flox.sh - Flox CLI
#

# Ensure that the script dies on any error.
set -e
set -o pipefail

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
. $_lib/init.sh

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
		verbose=1
		shift
		;;
	--debug)
		set -x
		debug=1
		verbose=1
		shift
		;;
	--version)
		echo "Version: @@VERSION@@"
		exit 0
		;;
	-h | --help)
		usage
		exit 0
		;;
	*) break ;;
	esac
done

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

# Nix and Flox commands which take a (-p|--profile) profile argument.
activate | history | install | list | remove | rollback | \
	switch-generation | upgrade | wipe-history | \
	generations | git | push | pull | sync) # Flox commands

	# Look for the --profile argument(s).
	args=()
	while test $# -gt 0; do
		case "$1" in
		-p | --profile)
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
	profileUserName=$($_basename $($_dirname $profile))
	profileMetaDir="$FLOX_PROFILEMETA/$profileUserName"
	profileStartGen=$(profileGen "$profile")

	[ -z "$verbose" ] || [ "$subcommand" = "activate" ] || echo Using profile: $profile >&2

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
			[ -d "$i/." ] || warn "INFO profile not found: $i"
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
			cmd=("invoke" "${cmdArgs[@]}")
		else
			case "$SHELL" in
			*bash)
				if [ -t 1 ]; then
					cmd=("invoke" "$SHELL" "--rcfile" "$_etc/flox.bashrc")
				else
					echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\"; source $_etc/flox.profile"
					exit 0
				fi
				;;
			*zsh)
				if [ -t 1 ]; then
					if [ -n "$ZDOTDIR" ]; then
						export FLOX_ORIG_ZDOTDIR="$ZDOTDIR"
					fi
					export ZDOTDIR="$_etc/flox.zdotdir"
					cmd=("invoke" "$SHELL")
				else
					echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\"; source $_etc/flox.profile"
					exit 0
				fi
				;;
			*)
				error "unsupported shell: \"$SHELL\"" </dev/null
				;;
			esac
		fi

		# Finally, undefine $profile so we don't audit profiles.
		profile=
		;;

	# Commands which accept a flox package reference.
	install | remove | upgrade)
		pkgArgs=()
		pkgNames=()
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
		logMessage="$FLOX_USER $(pastTense $subcommand) ${pkgNames[@]}"
		cmd=($invoke_nix -v profile "$subcommand" --profile "$profile" "${pkgArgs[@]}")
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
		logMessage="$FLOX_USER $(pastTense $subcommand) $targetGeneration"
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
		cat <<EOF
Profile
  Name      $profileName
  System    $NIX_CONFIG_system
  Path      $FLOX_PROFILES/$FLOX_USER/$profileName
  Curr Gen  $profileStartGen

Packages
EOF
		manifest $profile/manifest.json listProfile "${args[@]}" | $_sed 's/^/  /'
		;;

	history)
		if [[ "$profile" =~ ^$FLOX_PROFILES ]]; then
			# Default log format only includes subject %s.
			logFormat="format:%cd %C(cyan)%s%Creset"

			# Step through args looking for (-v|--verbose).
			for arg in ${args[@]}; do
				case "$arg" in
				-v | --verbose)
					# If verbose then add body as well.
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
		metaGit "$profile" "$NIX_CONFIG_system" ${invocation_args[@]}
		;;

	push | pull)
		pushpullMetadata "$subcommand" "$profile" "$NIX_CONFIG_system"
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
profiles)
	branches=$(metaGit $(profileArg "default") "$NIX_CONFIG_system" branch | $_awk -F. "/$NIX_CONFIG_system/ {print \$NF}")
	for b in $branches; do
		g=$($_readlink $FLOX_PROFILES/$FLOX_USER/$b | $_awk -F- '{print $(NF-1)}')
		cat <<EOF
$FLOX_USER/$b
    Name      $b
    Path      $FLOX_PROFILES/$FLOX_USER/$b
    Curr Gen  $g

EOF
	done
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
	cmd=($invoke_nix "$subcommand" "$@")
	;;

develop)
	cmd=($invoke_nix "$subcommand" "$@")
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

packages)
	smokeandmirrorfile=$_share/flox-smoke-and-mirrors/packages-all.txt.gz
	packageregexp=
	for arg in $@; do
		case "$arg" in
		--show-libs)
			smokeandmirrorfile=$_share/flox-smoke-and-mirrors/packages-all-libs.txt.gz
			shift
			;;
		--all)
			packageregexp="."
			shift
			;;
		*)
			packageregexp="^$arg\."
			shift
			break
			;;
		esac
	done
	[ -n "$packageregexp" ] ||
		usage | error "missing channel argument"
	[ -z "$@" ] ||
		usage | error "extra arguments \"$@\""
	cmd=("$_zgrep" "$packageregexp" "$smokeandmirrorfile")
	;;

newpackages)
	# iterate over all known flakes listing valid floxpkgs tuples.
	for flake in $(flakeRegistry get flakes | $_jq -r '.[] | .from.id'); do
		$_nix eval "flake:${flake}#__index.${NIX_CONFIG_system}" --json | jq --stream 'select(length==2)|.[0]|join(".")' -cr
	done
	;;

builds)
		$_nix eval "$floxpkgsUri#cachedPackages.${NIX_CONFIG_system}.$1"  --json --impure --apply 'builtins.mapAttrs (_k: v: v.meta )'  | $_jq -r '["Build Date","Name/Version","Description","Package Ref"], ["-----------","------------","-----------","-------"], ([.[]] | sort_by(.revision_epoch) |.[] |  [(.revision_epoch|(strftime("%Y-%m-%d"))), .name, .description, .flakeref]) | @tsv' | column -ts "$(printf '\t')"
	;;

shell)
	cmd=($invoke_nix "$subcommand" "$@")
	;;

# Special "cut-thru" mode to invoke Nix directly.
nix)
	cmd=($invoke_nix "$@")
	;;

search)
	# FIXME: sed messes up newlines in following output
	# --> will need to fix bug in Nix itself.
	$invoke_nix search $(searchArgs "$@") | \
	  $_sed -E "s%([^'])${catalogAttrPathPrefix}\.%\1%" | \
	  $_sed -e "s%^.*\* %* %" -e "/^$/d"
	;;

update)
	$_nix run floxpkgs#update-versions "$PWD"
	$_nix run floxpkgs#update-extensions "$PWD"
	;;

*)
	cmd=($invoke_nix "$subcommand" "$@")
	;;
esac

[ ${#cmd[@]} -gt 0 ] || exit

"${cmd[@]}"
if [ -n "$profile" ]; then
	profileEndGen=$(profileGen "$profile")
	if [ -n "$profileStartGen" ]; then
		logMessage="Generation ${profileStartGen}->${profileEndGen}: $logMessage"
	else
		logMessage="Generation ${profileEndGen}: $logMessage"
	fi
	if [ "$profileStartGen" != "$profileEndGen" ]; then
		syncMetadata \
			"$profile" \
			"$NIX_CONFIG_system" \
			"$profileStartGen" \
			"$profileEndGen" \
			"$logMessage" \
			"flox $subcommand ${invocation_args[@]}"
		# Follow up action with sync'ing of profiles in reverse.
		syncProfile "$profile" "$NIX_CONFIG_system"
	fi
fi

# vim:ts=4:noet:syntax=bash
