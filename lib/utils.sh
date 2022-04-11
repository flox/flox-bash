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
hash_commands basename cat cmp cp cut dasel dirname id jq getent git \
	ln mktemp mv nix readlink realpath rm sh tr

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
	local manifest="$1"; shift
	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/manifest.jq \      # the manifest processing library
	#   --arg system $system \      # set "$system"
	#   --slurpfile manifest "$1" \ # slurp json into "$manifest"
	local jqargs=("-n" "-e" "-r" "-f" "$_lib/manifest.jq")

	# N.B jq invocation aborts if it cannot slurp a file, so if the registry
	# doesn't already exist (with nonzero size) then replace with bootstrap.
	if [ -s "$manifest" ]; then
		jqargs+=("--slurpfile" "manifest" "$manifest")
	else
		jqargs+=("--argjson" "manifest" '[{"elements": [], "version": 1}]')
	fi

	# Append arg which defines $system.
	jqargs+=("--arg" "system" "$NIX_CONFIG_system")

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

	# Finally invoke jq.
	$_jq "${jqargs[@]}"
}

#
# registry(registry,command,[args])
#
# Accessor method for jq-based registry library functions.
# N.B. requires $registry variable pointing to registry.json file.
#
# Usage:
#   registry path/to/registry.json (set|setString) a b c
#   registry path/to/registry.json setNumber a b 3
#   registry path/to/registry.json delete a b c
#   registry path/to/registry.json (addArray|addArrayString) d e f
#   registry path/to/registry.json addArrayNumber d e 6
#   registry path/to/registry.json (delArray|delArrayString) d e f
#   registry path/to/registry.json delArrayNumber d e 6
#   registry path/to/registry.json get a b
#   registry path/to/registry.json dump
#
function registry() {
	local registry="$1"; shift
	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/registry.jq \      # the registry processing library
	#   --slurpfile registry "$1" \ # slurp json into "$registry"
	local jqargs=("-n" "-e" "-r" "-f" "$_lib/registry.jq")

	# N.B jq invocation aborts if it cannot slurp a file, so if the registry
	# doesn't already exist (with nonzero size) then replace with bootstrap.
	if [ -s "$registry" ]; then
		jqargs+=("--slurpfile" "registry" "$registry")
	else
		jqargs+=("--argjson" "registry" '[{"version": 1}]')
	fi

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

	foobar="$1"
	case "$1" in
		# Methods which update the registry.
		set | setNumber | setString | \
		addArray | addArrayNumber | addArrayString | \
		delete | delArray | delArrayNumber | delArrayString)
			local _tmpfile=$($_mktemp)
			$_jq "${jqargs[@]}" > $_tmpfile
			if [ -s "$_tmpfile" ]; then
				$_cmp -s $_tmpfile $registry || $_mv $_tmpfile $registry
				$_rm -f $_tmpfile
			else
				error "something went wrong" < /dev/null
			fi
		;;

		# All others return data from the registry.
		*)
			$_jq "${jqargs[@]}"
		;;
	esac
}

function pastTense() {
	local subcommand="$1"
	case "$subcommand" in
	install)      echo "installed";;
	remove)       echo "removed";;
	rollback)     echo "rolled back";;
	upgrade)      echo "upgraded";;
	wipe-history) echo "wiped history";;
	*)            echo "$subcommand";;
	esac
}

# vim:ts=4:noet:
