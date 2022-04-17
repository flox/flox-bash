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
. $_lib/init.sh

# Short name for this script, derived from $0.
me="${0##*/}"
mespaces=$(echo $me | $_tr '[a-z]' ' ')
medashes=$(echo $me | $_tr '[a-z]' '-')

function usage() {
	$_cat <<EOF 1>&2
usage: $me [ --stability (stable|staging|unstable) ]
       $mespaces [ (-d|--date) <date_string> ]
       $mespaces [ (-v|--verbose) ] [ --debug ] <command>
       $medashes
       $me [ (-h|--help) ] [ --version ]

Flox profile commands:
    flox activate - fix me
    flox gh - access to the gh CLI
    flox git - access to the git CLI
    flox generations - list profile generations with contents
    flox push - send profile metadata to remote registry
    flox pull - pull profile metadata from remote registry
    flox sync - synchronize profile metadata and links

Nix profile commands:
    flox diff-closures - show the closure difference between each version of a profile
    flox history - show all versions of a profile
    flox install - install a package into a profile
    flox list [ --out-path ] - list installed packages
    flox (rm|remove) - remove packages from a profile
    flox rollback - roll back to the previous generation of a profile
    flox switch-generation - switch to a specific generation of a profile
    flox upgrade - upgrade packages using their most recent flake
    flox wipe-history - delete non-current versions of a profile

Developer environment commands:
    flox develop

EOF
}

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
	nix-build 	shift
		;;
	-v | --verbose)
		verbose=1
		_xargs="$_xargs --verbose"
		shift
		;;
	--debug)
		set -x
		debug=1
		verbose=1
		_xargs="$_xargs --verbose"
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
# Subroutines
#

function profileArg() {
	# flox profiles must resolve to fully-qualified paths within
	# $FLOX_PROFILES. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$FLOX_PROFILES ]]; then
			# Path already a floxpm profile - use it.
			echo "$1"
		elif [[ -L "$1" ]]; then
			# Path is a link - try again with the link value.
			echo $(profileArg $(readlink "$1"))
		else
			error "\"$1\" is not a Flox profile path" >&2
		fi
	elif [[ "$1" =~ \	|\  ]]; then
		error "profile \"$1\" cannot contain whitespace" >&2
	else
		# Return default path for the profile directory.
		echo "$FLOX_PROFILES/${FLOX_USER}/$1"
	fi
}

# Parses generation from profile path.
function profileGen() {
	local profile="$1"
	local profileName=$($_basename $profile)
	if [ -L "$profile" ]; then
		if [[ $($_readlink "$profile") =~ ^${profileName}-([0-9]+)-link$ ]]; then
			echo ${BASH_REMATCH[1]}
			return
		fi
	fi
}

# Package args can take one of 3 formats:
# 1) flake references containing "#" character: return as-is.
# 2) positional integer references containing only numbers [0-9]+.
# 3) paths which resolve to /nix/store/*: return first 3 path components.
# 4) floxpkgs "channel.stability.attrPath" tuple: convert to flox catalog
#    flake reference, e.g. nixpkgs.stable.nyancat -> nixpkgs#stable.nyancat.
function floxpkgArg() {
	if [[ "$1" == *#* ]]; then
		echo "$1"
	elif [[ "$1" =~ ^[0-9]+$ ]]; then
		echo "$1"
	elif [ -e "$1" ]; then
		_rp=$($_realpath "$1")
		if [[ "$_rp" == /nix/store/* ]]; then
			echo "$_rp" | $_cut -d/ -f1-4
		fi
	else
		local IFS='.'
		declare -a attrPath 'arr=($1)'
		local channel="${arr[0]}"
		local stability="stable"
		case "${arr[1]}" in
		stable | staging | unstable)
			stability="${arr[1]}"
			attrPath=(${arr[@]:2})
			;;
		*)
			attrPath=(${arr[@]:1})
			;;
		esac
		echo "flake:${floxFlakePrefix}#${floxFlakeAttrPathPrefix}.${channel}.${stability}.${attrPath}"
	fi
}

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

# Flox profile path.
profile=

# Build log message as we go.
logMessage=

case "$subcommand" in

# Nix and Flox commands which take a (-p|--profile) profile argument.
activate | history | install | list | remove | rollback | \
	switch-generation | upgrade | wipe-history | \
	generations | git | push | pull | sync) # Flox commands

	# Look for the --profile argument.
	profile=""
	args=()
	while test $# -gt 0; do
		case "$1" in
		-p | --profile)
			profile=$(profileArg $2)
			shift 2
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	if [ "$profile" == "" ]; then
		profile=$(profileArg "default")
		profileName=$($_basename $profile)
		profileUserName=$($_basename $($_dirname $profile))
		profileMetaDir="$FLOX_METADATA/$profileUserName"
		profileStartGen=$(profileGen "$profile")
	fi
	echo Using profile: $profile >&2

	case "$subcommand" in

	activate)
		#export XDG_OTHER
		# FLOX_PROFILES/default/nix-support/bin/activate
		# FLOX_PROFILES/default/nix-support/etc/hooks
		# FLOX_PROFILES/default/nix-support/etc/environment
		# FLOX_PROFILES/default/nix-support/etc/profile
		# FLOX_PROFILES/default/nix-support/etc/systemd
		# or put these mechanisms behind a "flox-support" dir?
		# open new shell?

		#cmd=("$profile/nix-support/flox/bin/activate) ?

		export PATH="$profile/bin:$PATH"
		cmd=("$SHELL")
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
				-*) # Don't try to interpret option as floxpkgArg.
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
				flake:${floxFlakePrefix}*)
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
		cmd=($_nix -v profile "$subcommand" --profile "$profile" "${opts[@]}" "${pkgArgs[@]}")
		;;

	rollback | switch-generation | wipe-history)
		logMessage="$FLOX_USER $(pastTense $subcommand)"
		if [ "$subcommand" = "switch-generation" ]; then
			# rewrite switch-generation to instead use the new
			# "rollback --to" command (which makes no sense IMO).
			subcommand=rollback
			opts=("--to" "${args[0]}" "${opts[@]}")
			args=("${args[@]:1}")
		fi
		cmd=($_nix profile "$subcommand" --profile "$profile" "${opts[@]}" "${args[@]}")
		;;

	list)
		manifest $profile/manifest.json listProfile "${opts[@]}" "${args[@]}"
		;;

	history)
		# Nix history is not a history! It's just a diff of successive generations.
		#cmd=($_nix profile "$subcommand" --profile "$profile" "${opts[@]}" "${args[@]}")

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
	cmd=($_nix "$subcommand" "${opts[@]}" "${args[@]}")
	;;

build)
	cmd=($_nix "$subcommand" "$@")
	;;

develop)
	cmd=($_nix "$subcommand" "$@")
	;;

gh)
	cmd=($_gh "$@")
	;;

packages)
	# iterate over all known flakes listing valid floxpkgs tuples.
	for flake in $(flakeRegistry get flakes | $_jq -r '.[] | .from.id'); do
		$_nix eval "flake:${flake}#attrnames.${NIX_CONF_system}" --json | \
			$_jq -r ".[]"
	done
	;;

shell)
	cmd=($_nix "$subcommand" "$@")
	;;

# Special "cut-thru" mode to invoke Nix directly.
nix)
	cmd=($_nix "$@")
	;;

search)
    echo "TEST"
	cmd=($_nix "$subcommand" "$@")
	;;
*)
	cmd=($_nix "$subcommand" "$@")
	;;
esac

[ ${#cmd[@]} -gt 0 ] || exit

invoke "${cmd[@]}"
if [ -n "$profile" ]; then
	profileEndGen=$(profileGen "$profile")
	if [ -n "$profileStartGen" ]; then
		logMessage="Generation ${profileStartGen}->${profileEndGen}: $logMessage"
	else
		logMessage="Generation ${profileEndGen}: $logMessage"
	fi
	[ "$profileStartGen" = "$profileEndGen" ] ||
		syncMetadata \
			"$profile" \
			"$NIX_CONFIG_system" \
			"$profileStartGen" \
			"$profileEndGen" \
			"$logMessage" \
			"flox $subcommand ${invocation_args[@]}"
	# Always follow up action with sync'ing of profiles in reverse.
	syncProfile "$profile" "$NIX_CONFIG_system"
fi

# vim:ts=4:noet:
