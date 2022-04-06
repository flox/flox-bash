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

# Short name for this script, derived from $0.
me="${0##*/}"
mespaces=$(echo $me | tr '[a-z]' ' ')
medashes=$(echo $me | tr '[a-z]' '-')

function usage() {
	cat <<EOF 1>&2
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
    flox list - list installed packages
    flox remove - remove packages from a profile
    flox rollback - roll back to the previous version or a specified version of a profile
    flox upgrade - upgrade packages using their most recent flake
    flox wipe-history - delete non-current versions of a profile

Developer environment commands:
    flox develop

EOF
}

function error() {
	if [ -n "$@" ]; then
		echo "ERROR: $@" 1>&2
	fi
	usage
	exit 1;
}

# Before doing anything take inventory of all commands required by the
# script, taking particular note to ensure we use those from the UNCLE
# or from the base O/S as required. Note that we specifically avoid the
# typical method of modifying the PATH environment variable to avoid
# leaking Nix/UNCLE paths into the commands we invoke.

function hash_commands() {
	local PATH=@@FLOXPATH@@:$PATH
	for i in "$@"
	do
		hash $i # Dies with useful/precise error on failure when not found.
		declare -g _$i=$(type -P $i)
	done
}

# Hash commands we expect to find.
hash_commands cat dasel dirname id jq getent nix sh

# If the first arguments are any of -d|--date, -v|--verbose or --debug
# then we consume this (and in the case of --date, its argument) as
# argument(s) to the wrapper and not the command to be wrapped. To send
# either of these arguments to the wrapped command put them at the end.
while [ $# -ne 0 ]; do
	case "$1" in
		--stability)
			shift;
			if [ $# -eq 0 ]; then
				echo "ERROR: missing argument to --stability flag" 1>&2
				exit 1
			fi
			export FLOX_STABILITY="$1";
			shift;;
		-d|--date)
			shift;
			if [ $# -eq 0 ]; then
				error "missing argument to --date flag"
			fi
			export FLOX_RENIX_DATE="$1";
			shift;;
		-v|--verbose)
			verbose=1; shift;;
		--debug)
			set -x; debug=1; verbose=1; shift;;
		*) break;;
	esac
done

#
# Global variables
#

# Parse flox configuration files.
_prefix="@@PREFIX@@"
_prefix=${_prefix:-.}
libexec=$_prefix/libexec
. $libexec/config.sh
eval $(read_flox_conf npfs floxpkgs)

# NIX honors ${USER} over the euid, so make them match.
export USER=$($_id -un)
export HOME=$($_getent passwd ${USER} | cut -d: -f6)

# FLOX_USER can be completely different, e.g. the GitHub user,
# or can be the same as the UNIX $USER. Only flox knows!
export FLOX_USER=$USER # XXX FIXME $(flox whoami)

# Define and create flox metadata cache, data, and profiles directories.
export FLOX_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/flox"
export FLOX_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/flox"
export FLOX_PROFILES="${FLOX_PROFILES:-$FLOX_DATA_HOME/profiles}"
mkdir -p "$FLOX_CACHE_HOME" "$FLOX_DATA_HOME" "$FLOX_PROFILES"

# Prepend FLOX_DATA_HOME to XDG_DATA_DIRS. XXX Why? Probably delete ...
export XDG_DATA_DIRS="$FLOX_DATA_HOME"${XDG_DATA_DIRS:+':'}${XDG_DATA_DIRS}

# Leave it to Bob to figure out that Nix 2.3 has the bug that it invokes
# `tar` without the `-f` flag and will therefore honor the `TAPE` variable
# over STDIN (to reproduce, try running `TAPE=none flox shell`).
# XXX Still needed??? Probably delete ...
if [ -n "$TAPE" ]; then
	unset TAPE
fi

# Import other utility functions.
#. $libexec/convert.sh
#. $libexec/flakes.sh
#. $libexec/foo.sh
#. $libexec/bar.sh

#
# Subroutines
#

function profile_arg {
	# flox profiles must resolve to fully-qualified paths within
	# $FLOX_PROFILES. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$FLOX_PROFILES ]]; then
			# Path already a floxpm profile - use it.
			echo "$1"
		elif [[ "$1" =~ ^/nix/store/.*-user-environment ]]; then
			# Path is a user-environment in the store - use it.
			echo "$1"
		elif [[ -h "$1" ]]; then
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

function pprint {
	# Step through args and encase with single-quotes those which need it.
	result="+"
	for i in "$@"; do
		if [[ "$i" =~ " " ]]; then
			result="$result '$i'"
		else
			result="$result $i"
		fi
	done
	echo $result
}

# Convert floxpkgs "channel.stability.attrPath" tuple to flox catalog
# flake reference, e.g. nixpkgs.stable.nyancat -> nixpkgs#stable.nyancat.
function floxpkgs_to_flakeref() {
	local IFS='.'
	declare -a attrPath 'arr=($1)'
	local channel="${arr[0]}"
	local stability="stable"
	case "${arr[1]}" in
		stable|staging|unstable)
			stability="${arr[1]}"
			attrPath=(${arr[@]:2})
			;;
		*)
			attrPath=(${arr[@]:1})
			;;
	esac
	echo "${channel}#${stability}.${attrPath}"
}

function parse_package_remove() {
	local IFS='.'
	declare -a attrPath 'arr=($1)'
	local channel="${arr[0]}"
	local stability="stable"
	case "${arr[1]}" in
		stable|staging|unstable)
			stability="${arr[1]}"
			attrPath=(${arr[@]:2})
			;;
		*)
			attrPath=(${arr[@]:1})
			;;
	esac
	echo "'.*.${stability}.${attrPath}^'"

}
#
# main()
#

# Start by identifying subcommand to be invoked.
# FIXME: use getopts to properly scan args for first non-option arg.
while test $# -gt 0; do
	case "$1" in
		-*)
			error "unrecognised option before subcommand"
			;;
		*)
			subcommand="$1"
			shift
			break;;
	esac
done
if [ -z "$subcommand" ]; then
	error "command not provided"
fi

case "$subcommand" in

	# Commands which take a (-p|--profile) profile argument.
	activate|history|install|list|remove|rollback|upgrade|wipe-history)

		# Look for the --profile argument.
		profile=""
		args=()
		opts=()
		while test $# -gt 0; do
			case "$1" in
				-p|--profile)
					profile=$(profile_arg $2)
					shift 2;;
				-*)
					# FIXME: wrong to assume options take no arguments
					opts+=("$1")
					shift;;
				*)
					args+=("$1")
					shift;;
			esac
		done
		if [ "$profile" == "" ]; then
			profile=$(profile_arg "default")
		fi
		opts=(--profile "$profile" "${opts[@]}")
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
			install|upgrade)
				# Nix will create a profile directory, but not its parent.  :-\
				if [ "$subcommand" = "install" ]; then
					[ -d $($_dirname $profile) ] || \
						mkdir -v -p $($_dirname $profile)
				fi
				pkgargs=()
				for pkg in "${args[@]}"; do
					pkgargs+=($(floxpkgs_to_flakeref "$pkg"))
				done
				cmd=($_nix profile $subcommand "${opts[@]}" "${pkgargs[@]}")
				;;

			history|list|rollback|wipe-history)
				cmd=($_nix profile $subcommand "${opts[@]}" "${args[@]}")
				;;
			remove)
				for pkg in "${args[@]}"; do
					pkgargs+=($(parse_package_remove "$pkg"))
				done
				cmd=($_nix profile $subcommand "${opts[@]}" "${args[@]}")
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
		cmd=($_nix $subcommand "${opts[@]}" "${args[@]}")
		;;

	build)
		cmd=($_nix $subcommand "$@")
		;;

	# Special "cut-thru" mode to invoke Nix directly.
	nix)
		cmd=($_nix "$@")
		;;

	develop)
		cmd=($_nix "$subcommand" "$@")
		;;

#	packages)
#		cmd=($_sh -c "$_nix eval nixpkgs#attrnames.x86_64-linux --json | $_jq -r .[]")
#
#		;;
	shell)
		cmd=($_nix "$subcommand" "$@")
		;;
#	install)
#		cmd=($_nix profile "$subcommand" --profile "$FLOX_DATA_HOME/$CURR_PROFILE_DIR" $(floxpkgs_to_flakeref "$@"))
#		;;
#	list|remove|upgrade|rollback|history)
#		cmd=($_nix profile "$subcommand" "$@")
#		;;


	*)
		cmd=($_nix $subcommand "$@")
		# error "unknown command: $subcommand"
		;;
esac

# Set base configuration before invoking nix.
export NIX_USER_CONF_FILES=$_prefix/etc/nix.conf

if [ -n "$verbose" ]; then
	# First turn off set -x (if set) to prevent double-printing.
	set +x
	# pprint "NIX_PATH=$NIX_PATH" "exec" "${cmd[@]}" 1>&2
	pprint NIX_USER_CONF_FILES=$NIX_USER_CONF_FILES "${cmd[@]}" 1>&2
fi

exec "${cmd[@]}"
# vim:ts=4:noet:
