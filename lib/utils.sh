#
# Utility functions.
#

function hash_commands() {
	set -h # explicitly enable hashing
	local PATH=@@FLOXPATH@@:$PATH
	for i in "$@"; do
		hash $i # Dies with useful/precise error on failure when not found.
		declare -g _$i=$(type -P $i)
	done
}

# Before doing anything take inventory of all commands required by the script.
# Note that we specifically avoid modifying the PATH environment variable to
# avoid leaking Nix paths into the commands we invoke.
# TODO replace each use of $_cut and $_tr with shell equivalents.
hash_commands basename cat cmp cp cut dasel dirname id jq getent mktemp mv nix rm sh tr

function warn() {
	if [ -n "$@" ]; then
		echo "$@" 1>&2
	fi
}

function error() {
	if [ -n "$@" ]; then
		warn "ERROR: $@"
	fi
	# Relay any STDIN out to STDERR.
	$_cat 1>&2
	# Don't exit from interactive shells (for debugging).
	case "$-" in
	*i*) : ;;
	*) exit 1 ;;
	esac
}

function pprint() {
	# Step through args and encase with single-quotes those which need it.
	local result="+"
	for i in "$@"; do
		if [[ "$i" =~ " " ]]; then
			result="$result '$i'"
		else
			result="$result $i"
		fi
	done
	echo $result
}

#
# manifest(manifest,command,[args])
#
# Accessor method for jq-based manifest library functions.
# N.B. requires $manifest variable pointing to manifest.json file.
#
function manifest() {
	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/manifest.jq \      # the manifest processing library
	#   --arg system $system \      # set "$system"
	#   --slurpfile manifest "$1" \ # slurp json into "$manifest"
	[ ! -e "$manifest" ] || (
		[ -z "$verbose" ] || set -x
		$_jq -n -e -r -f $_lib/manifest.jq --slurpfile manifest "$manifest" \
		  --arg system "$NIX_CONFIG_system" \
		  --args -- "$@"            # function and arguments
	)
}

#
# registry(registry,command,[args])
#
# Accessor method for jq-based registry library functions.
# N.B. requires $registry variable pointing to registry.json file.
#
# Usage:
#   registry set a b c d
#   registry get a b c
#   registry setNumber a b c 3
#   registry del a b c
#   registry dump
#
function registry() {
	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/registry.jq \      # the registry processing library
	#   --slurpfile registry "$1" \ # slurp json into "$registry"
	local jqargs=("-n" "-e" "-r" "-f" "$_lib/registry.jq")

	# N.B. library automatically initializes registry data structure
	# if not provided, but jq aborts if it cannot slurp the file.
	# If the registry file doesn't already exist (with nonzero size)
	# then don't add that to the arguments.
	if [ -s "$registry" ]; then
		jqargs+=("--slurpfile" "registry" "$registry")
	else
		jqargs+=("--argjson" "registry" '[{"version": 1}]')
	fi

	foobar="$1"
	case "$1" in
		# Methods which update the registry.
		set|setNumber|setString|del)
			local _tmpfile=$($_mktemp)
			$_jq "${jqargs[@]}" --args -- "$@" > $_tmpfile
			if [ -s "$_tmpfile" ]; then
				$_cmp -s $_tmpfile $registry || $_mv $_tmpfile $registry
				$_rm -f $_tmpfile
			else
				error "something went wrong" < /dev/null
			fi
		;;

		# All others return data from the registry.
		*)
			$_jq "${jqargs[@]}" --args -- "$@"
		;;
	esac
}

# vim:ts=4:noet:
