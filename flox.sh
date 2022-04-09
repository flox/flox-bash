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

Profile commands:
    flox activate - fix me
    flox diff-closures - show the closure difference between each version of a profile
    flox history - show all versions of a profile
    flox install - install a package into a profile
    flox list [ --out-path ] - list installed packages
    flox (rm|remove) - remove packages from a profile
    flox rollback - roll back to the previous version or a specified version of a profile
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
			error "missing argument to --date flag" < /dev/null
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
	*) break ;;
	esac
done

# Import library functions.
# . $_lib/registry.sh
# . $_lib/metadata.sh

#
# Subroutines
#

function profile_arg() {
	# flox profiles must resolve to fully-qualified paths within
	# $FLOX_PROFILES. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$FLOX_PROFILES ]]; then
			# Path already a floxpm profile - use it.
			echo "$1"
		elif [[ "$1" =~ ^/nix/store/.*-user-environment ]]; then
			# Path is a user-environment in the store - use it.
			echo "$1"
		elif [[ -L "$1" ]]; then
			# Path is a link - try again with the link value.
			echo $(profile_arg $(readlink "$1"))
		else
			echo ERROR: "$1" is not a Nix profile path >&2
			exit 2
		fi
	elif [[ "$1" =~ \	|\  ]]; then
		echo ERROR: profile "$1" cannot contain whitespace >&2
		exit 2
	else
		# Return default path for the profile directory.
		echo "$FLOX_PROFILES/${FLOX_USER}/$1"
	fi
}

# Package args can take one of 3 formats:
# 1) flake references containing "#" character: return as-is.
# 2) positional integer references containing only numbers [0-9]+.
# 3) paths which resolve to /nix/store/*: return first 3 path components.
# 4) floxpkgs "channel.stability.attrPath" tuple: convert to flox catalog
#    flake reference, e.g. nixpkgs.stable.nyancat -> nixpkgs#stable.nyancat.
function floxpkg_arg() {
	if [[ "$1" == *#* ]]; then
		echo "$1"
	elif [[ "$1" =~ ^[0-9]+$ ]]; then
		echo "$1"
	elif [ -e "$1" ]; then
		_rp=$(realpath "$1")
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
		echo "flake:${floxFlakePrefix}${channel}#${floxFlakeAttrPathPrefix}${stability}.${attrPath}"
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
		error "unrecognised option before subcommand" < /dev/null
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

case "$subcommand" in

# Commands which take a (-p|--profile) profile argument.
activate | history | install | list | remove | rollback | upgrade | wipe-history)

	# Look for the --profile argument.
	profile=""
	args=()
	opts=()
	while test $# -gt 0; do
		case "$1" in
		-p | --profile)
			profile=$(profile_arg $2)
			shift 2
			;;
		-*)
			# FIXME: wrong to assume options take no arguments
			opts+=("$1")
			shift
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	if [ "$profile" == "" ]; then
		profile=$(profile_arg "default")
	fi
	echo Using profile: $profile >&2
	manifest="$profile/manifest.json"

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
		pkgargs=()
		if [ "$subcommand" = "install" ]; then
			# Nix will create a profile directory, but not its parent.
			[ -d $($_dirname $profile) ] ||
				mkdir -v -p $($_dirname $profile)
			for pkg in "${args[@]}"; do
				pkgargs+=($(floxpkg_arg "$pkg"))
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
			for pkg in "${args[@]}"; do
				pkgarg=($(floxpkg_arg "$pkg"))
				if [[ "$pkgarg" == *#* ]]; then
					lookup=$(manifest flakerefToPosition "$pkgarg") || \
						error "package \"$pkg\" not found in profile $profile" < /dev/null
				elif [[ "$pkgarg" =~ ^[0-9]+$ ]]; then
					lookup="$pkgarg"
				else
					lookup=$(manifest storepathToPosition "$pkgarg") || \
						error "package \"$pkg\" not found in profile $profile" < /dev/null
				fi
				pkgargs+=($lookup)
			done
		fi

		cmd=($_nix -v profile "$subcommand" --profile "$profile" "${opts[@]}" "${pkgargs[@]}")
		;;

	list)
		manifest listProfile "${opts[@]}" "${args[@]}"
		exit 0 # N.B. does not return.
		;;

	history | rollback | wipe-history)
		cmd=($_nix profile "$subcommand" --profile "$profile" "${opts[@]}" "${args[@]}")
		;;

	esac
	;;

# The diff-closures command takes two profile arguments.
diff-closures)
	# Step through remaining arguments sorting options from args.
	opts=()
	args=()
	for arg in "$@"; do
		case "$arg" in
		-*)
			opts+=("$1")
			;;
		*)
			args+=$(profile_arg "$1")
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

packages)
	# TODO: iterate over all known flakes listing valid floxpkgs tuples.
	# For now just do nixpkgs alone.
	cmd=($_sh -c "$_nix eval flake:${floxFlakePrefix}nixpkgs#attrnames.@@SYSTEM@@ --json | $_jq -r .[]")
	;;

shell)
	cmd=($_nix "$subcommand" "$@")
	;;

# Special "cut-thru" mode to invoke Nix directly.
nix)
	cmd=($_nix "$@")
	;;

*)
	cmd=($_nix "$subcommand" "$@")
	;;
esac

if [ -n "$verbose" ]; then
	# First turn off set -x (if set) to prevent double-printing.
	set +x
	# pprint "NIX_PATH=$NIX_PATH" "exec" "${cmd[@]}" 1>&2
	pprint NIX_USER_CONF_FILES=$NIX_USER_CONF_FILES "${cmd[@]}" 1>&2
fi

exec "${cmd[@]}"
# vim:ts=4:noet:
