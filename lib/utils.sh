#
# Utility functions.
#

function hash_commands() {
	set -h # explicitly enable hashing
	local PATH=@@FLOXPATH@@:$PATH
	for i in $@; do
		_i=${i//-/_} # Pesky utilities containing dashes require rewrite.
		hash $i # Dies with useful/precise error on failure when not found.
		declare -g _$_i=$(type -P $i)
	done
}

# Before doing anything take inventory of all commands required by the script.
# Note that we specifically avoid modifying the PATH environment variable to
# avoid leaking Nix paths into the commands we invoke.
# TODO replace each use of $_cut and $_tr with shell equivalents.
hash_commands ansifilter awk basename cat cmp cp cut dasel date dirname id jq getent gh git \
	ln mkdir mktemp mv nix nix-store readlink realpath rm rmdir sed sh stat touch tr xargs

function warn() {
	[ ${#@} -eq 0 ] || echo "$@" 1>&2
}

function error() {
	[ ${#@} -eq 0 ] || warn "ERROR: $@"
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
	for i in $@; do
		if [[ "$i" =~ " " ]]; then
			result="$result '$i'"
		else
			result="$result $i"
		fi
	done
	echo $result
}

#
# invoke(${cmd_and_args[@]})
#
# Helper function to print invocation to terminal when
# running with verbose flag.
#
function invoke() {
	local vars=()
	if [ -n "$verbose" ]; then
		for i in ${exported_variables[@]}; do
			vars+=($(eval "echo $i=\${$i}"))
		done
		pprint "${vars[@]}" "$@" 1>&2
	fi
	"$@" 1>&2
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
	local version="$1"; shift

	# The "getPromptSet" subcommand is a special-case function which
	# first attempts to get a value and if not found will then
	# prompt the user with a default value to set.
	if [ "$1" = "getPromptSet" ]; then
		shift
		local prompt="$1"; shift
		local defaultVal="$1"; shift
		local value=$(registry "$registry" "$version" "get" "$@" || true)
		if [ -z "$value" ]; then
			read -e -p "$prompt" -i "$defaultVal" value
			registry "$registry" "$version" "set" "$@" "$value"
		fi
		echo "$value"
		return
	fi

	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/registry.jq \      # the registry processing library
	#   --slurpfile registry "$1" \ # slurp json into "$registry"
	#	--arg version "$2" \        # required schema version
	local jqargs=("-n" "-e" "-r" "-f" "$_lib/registry.jq" "--arg" "version" "$version")

	# N.B jq invocation aborts if it cannot slurp a file, so if the registry
	# doesn't already exist (with nonzero size) then replace with bootstrap.
	if [ -s "$registry" ]; then
		jqargs+=("--slurpfile" "registry" "$registry")
	else
		jqargs+=("--argjson" "registry" "[{\"version\": $version}]")
	fi

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

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
				local dn=$($_dirname $registry)
				[ ! -e "$dn/.git" ] || \
					$_git -C $dn add $($_basename $registry)
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

function flakeRegistry() {
	registry "$_etc/nix/registry.json" 2 "$@"
}

#
# profileRegistry($profile,command,[args])
# XXX refactor; had to duplicate above to add $profileName.  :-\
#
function profileRegistry() {
	local profile="$1"; shift
	local profileDir=$($_dirname $profile)
	local profileName=$($_basename $profile)
	local profileUserName=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_METADATA/$profileUserName"
	local registry="$profileMetaDir/metadata.json"
	local version=1
	# jq args:
	#   -n \                        # null input
	#   -e \                        # exit nonzero on errors
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/registry.jq \      # the registry processing library
	#   --slurpfile registry "$1" \ # slurp json into "$registry"
	#	--arg version "$2" \        # required schema version
	local jqargs=(
		"-n" "-e" "-r" "-f" "$_lib/profileRegistry.jq"
		"--arg" "version" "$version"
		"--arg" "profileDir" "$profileDir"
		"--arg" "profileName" "$profileName"
		"--arg" "profileMetaDir" "$profileMetaDir"
	)

	# N.B jq invocation aborts if it cannot slurp a file, so if the registry
	# doesn't already exist (with nonzero size) then replace with bootstrap.
	if [ -s "$registry" ]; then
		jqargs+=("--slurpfile" "registry" "$registry")
	else
		jqargs+=("--argjson" "registry" "[{\"version\": $version, \"generations\": {}}]")
	fi

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

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
				local dn=$($_dirname $registry)
				[ ! -e "$dn/.git" ] || \
					$_git -C $dn add $($_basename $registry)
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
	install)           echo "installed";;
	remove)            echo "removed";;
	rollback)          echo "rolled back a generation";;
	switch-generation) echo "switched generations";;
	upgrade)           echo "upgraded";;
	wipe-history)      echo "wiped history";;
	*)                 echo "$subcommand";;
	esac
}

# vim:ts=4:noet:
