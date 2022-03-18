#!/bin/bash
#
# flox.sh - Flox CLI
#
# Michael Brantley Tue Mar  8 09:53:36 AM UTC 2022
#

# Ensure that the script dies on any error.
set -e
set -o pipefail

# set -x if debugging, can never remember which way this goes so do both.
# Note need to do this here in addition to "-d" flag to be able to debug
# initial argument parsing.
test -z "${DEBUG_FLOX}" || FLOX_DEBUG="${DEBUG_FLOX}"
test -z "${FLOX_DEBUG}" || set -x

# Store the invocation arguments for reporting
invocation_args="$@"

# Short name for this script, derived from $0.
me="${0##*/}"

function usage() {
	echo "usage: $me TODO ..." 1>&2
}

function error() {
	if [ -n "$@" ]; then
		echo "ERROR: $@" 1>&2
	fi
	usage
	exit 1;
}


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

# Parse flox configuration files.
prefix="@@PREFIX@@"
prefix=${prefix:-.}
libexec=$prefix/libexec
. $libexec/config.sh
eval $(read_flox_conf nix-wrapper floxpkgs)

# Some defaults.
nix_package_bin=${NIX_PACKAGE_BIN:-@@NIX@@/bin}
floxpm_profile_dir=/nix/profiles

# NIX honors ${USER} over the euid, so make them match.
export USER=$(id -un)
export HOME=$(getent passwd ${USER} | cut -d: -f6)
export FLOX_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}/flox
mkdir -p "$FLOX_DATA_HOME"
export XDG_DATA_DIRS="$FLOX_DATA_HOME/default/share/:${XDG_DATA_DIRS}"

# Leave it to Bob to figure out that Nix 2.3 has the bug that it invokes
# `tar` without the `-f` flag and will therefore honor the `TAPE` variable
# over STDIN (to reproduce, try running `TAPE=none nix-shell`).
if [ -n "$TAPE" ]; then
	unset TAPE
fi

function profile_arg {
	# flox profiles must resolve to fully-qualified paths within the
	# floxpm_profile_dir. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$floxpm_profile_dir ]]; then
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
		echo "$floxpm_profile_dir/${FLOXUSER}/$1"
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

# Step through supplied nix_path redacting missing paths and duplicate
# namespaces.
function clean_nix_path {
	_path="$1"
	# Create variable for holding new path.
	newpath=
	# Keep track of namespaces encountered and redact duplicates.
	declare -A _namespaces_seen
	# Split _path on colons.
	local IFS=:
	# Iterate over components of path keeping those that exist.
	for i in $_path; do
		# NIX_PATH components can be of the form "foo=/path", in which case
		# we only want to verify the right-hand side of the string.
		path_element=""
		path_to_verify="$i"
		if [[ "$i" =~ ^([^/]*)=(.*)$ ]]; then
			path_element=${BASH_REMATCH[1]}
			if [ -n "${_namespaces_seen[$path_element]}" ]; then
				# Already seen this one - clear path_to_verify to skip.
				path_to_verify=""
			else
				_namespaces_seen["$path_element"]=1
				path_to_verify=${BASH_REMATCH[2]}
			fi
		fi
		if [ -n "$path_to_verify" -a -e "$path_to_verify" ]; then
			# Append colon, but not on first iteration
			[ -z "$newpath" ] || newpath="${newpath}:"
			newpath="${newpath}${path_element:+$path_element=}${path_to_verify}"
		fi
	done
	# Return updated path.
	echo "$newpath"
}

# main()

# Nix trips over nonexistent elements in the NIX_PATH - take this
# opportunity to remove them and any duplicate namespaces we find.
NIX_PATH=$(clean_nix_path "$NIX_PATH")

# Export the final NIX_PATH to be used.
export NIX_PATH

# Identify subcommand to be invoked.
subcommand="$1"
if [ -z "$subcommand" ]; then
	error "command not provided"
fi
shift

# Determine handling based on command invoked.
# Start by setting base nix invocation.
export NIX_USER_CONF_FILES=@@PREFIX@@/etc/nix.conf

nixcmd="$nix_package_bin/nix"
case "$subcommand" in
	activate)
		#export XDG_OTHER
		# FLOX_DATA_HOME/flox-profile/default/nix-support/bin/activate
		# FLOX_DATA_HOME/flox-profile/default/nix-support/etc/hooks
		# FLOX_DATA_HOME/flox-profile/default/nix-support/etc/environment
		# FLOX_DATA_HOME/flox-profile/default/nix-support/etc/profile
		# FLOX_DATA_HOME/flox-profile/default/nix-support/etc/systemd
		# or put these mechanisms behind a "flox-support" dir?
		# open new shell?
		export PATH="$FLOX_DATA_HOME/default/bin:$PATH"
		#cmd=("$FLOX_DATA_HOME"/flox-profile/default/nix-support/flox/bin/activate)
		cmd=("$SHELL")
		;;

	build)
		cmd=($nixcmd $subcommand "$@")
		;;

	# Special "cut-thru" mode to invoke Nix directly.
	nix)
		cmd=($nixcmd "$@")
		;;

	develop)
		cmd=($nixcmd "$subcommand" "$@")
		;;

	packages)
		## Assumption of jq and bat
		cmd=(sh -c "$nixcmd eval flox-lib#builtPackages.x86_64-linux --apply builtins.attrNames --json | jq -r '.[]' | bat")

		;;

	shell)
		cmd=($nixcmd "$subcommand" "$@")
		;;

	install|list|remove|upgrade|rollback|history)
		cmd=($nixcmd profile "$subcommand" --profile "$FLOX_DATA_HOME"/default "$@")
		;;

	*)
		cmd=($nixcmd $subcommand "$@")
		# error "unknown command: $subcommand"
		;;
esac

if [ -n "$verbose" ]; then
	# First turn off set -x (if set) to prevent double-printing.
	set +x
	# pprint "NIX_PATH=$NIX_PATH" "exec" "${cmd[@]}" 1>&2
	pprint NIX_USER_CONF_FILES=@@PREFIX@@/etc/nix.conf "${cmd[@]}" 1>&2
fi

exec "${cmd[@]}"
# vim:ts=4:noet:
