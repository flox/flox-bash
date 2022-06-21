#
# Utility functions.
#
# Track exported environment variables for use in verbose output.
declare -A exported_variables
function hash_commands() {
	set -h # explicitly enable hashing
	local PATH=@@FLOXPATH@@:$PATH
	for i in $@; do
		_i=${i//-/_} # Pesky utilities containing dashes require rewrite.
		hash $i # Dies with useful/precise error on failure when not found.
		declare -g _$_i=$(type -P $i)

		# Define $invoke_<name> variables for those invocations we'd
		# like to wrap with the invoke() subroutine.
		declare -g invoke_$_i="invoke $(type -P $i)"

		# Some commands require certain environment variables to work properly.
		# Make note of them here for displaying verbose output in invoke().
		case $i in
		nix | nix-store)
			exported_variables[$(type -P $i)]="NIX_REMOTE NIX_SSL_CERT_FILE NIX_USER_CONF_FILES" ;;
		*) ;;
		esac
	done
}

# Before doing anything take inventory of all commands required by the script.
# Note that we specifically avoid modifying the PATH environment variable to
# avoid leaking Nix paths into the commands we invoke.
# TODO replace each use of $_cut and $_tr with shell equivalents.
hash_commands ansifilter awk basename cat cmp cp cut dasel date dirname id jq getent gh git \
	ln mkdir mktemp mv nix nix-store pwd readlink realpath rm rmdir sed sh stat touch tr xargs zgrep

# Return full path of first command available in PATH.
#
# Usage: first_in_PATH foo bar baz
function first_in_PATH() {
	set -h # explicitly enable hashing
	local PATH=@@FLOXPATH@@:$PATH
	for i in $@; do
		if hash $i 2>/dev/null; then
			echo $(type -P $i)
			return
		fi
	done
}

bestAvailableEditor=$(first_in_PATH vim vi nano emacs ed)
editorCommand=${EDITOR:-${VISUAL:-${bestAvailableEditor:-vi}}}

# Short name for this script, derived from $0.
me="${0##*/}"
mespaces=$(echo $me | $_tr '[a-z]' ' ')
medashes=$(echo $me | $_tr '[a-z]' '-')

function warn() {
	[ ${#@} -eq 0 ] || echo "$@" 1>&2
}

function error() {
	[ ${#@} -eq 0 ] || warn "ERROR: $@"
	warn "" # Add space before appending output.
	# Relay any STDIN out to STDERR.
	$_cat 1>&2
	# Don't exit from interactive shells (for debugging).
	case "$-" in
	*i*) : ;;
	*) exit 1 ;;
	esac
}

function usage() {
	$_cat <<EOF 1>&2
usage: $me [ (-h|--help) ] [ --version ]
       $medashes
       $me [ (-v|--verbose) ] [ --debug ] <command> [ <args> ]
       $medashes
       $me <development-command> \\
       $mespaces[ --stability (stable|staging|unstable) ] \\
       $mespaces[ (-d|--date) <date_string> ] [ <args> ]
       $me <profile-command> \\
       $mespaces[ (-p|--profile) <profile> ] [ <args> ]
       $medashes

flox general commands:
    flox packages [ --all | channel[.stability[.package]] ] [--show-libs]
        list all packages or filtered by channel[.subchannel[.package]]
        --show-libs: include library packages
    flox builds <channel>.<stability>.<package>
        list all available builds for specified package
    flox profiles
        list available profiles owned by "$FLOX_USER"
    flox activate [ (-p|--profile) <profile> ] - activate profile
      current shell: . <(flox activate)
        in subshell: flox activate
        for command: flox activate -- <command> <args>
    flox config - configure user parameters
    flox gh - access to the gh CLI
    flox git - access to the git CLI

flox development commands:
    flox develop - launch development shell for current project
    flox build - build package from current project
    flox shell - launch build shell for current project

flox profile commands:
    flox generations - list profile generations with contents
    flox push - send profile metadata to remote registry
    flox pull - pull profile metadata from remote registry
    flox sync - synchronize profile metadata and links
    flox cat - display declarative profile manifest
    flox edit - edit declarative profile manifest

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
declare -i minverbosity=1
function invoke() {
	local vars=()
	if [ $verbose -ge $minverbosity ]; then
		for i in ${exported_variables[$1]}; do
			vars+=($(eval "echo $i=\${$i}"))
		done
		pprint "${vars[@]}" "$@" 1>&2
	fi
	"$@"
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

	# Append arg which defines $catalogAttrPathPrefix.
	jqargs+=("--arg" "catalogAttrPathPrefix" "$catalogAttrPathPrefix")

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

	# Finally invoke jq.
	minverbosity=2 $invoke_jq "${jqargs[@]}"
}

#
# manifestTOML(manifest,command,[args])
#
# Accessor method for declarative TOML manifest library functions.
#
function manifestTOML() {
	local manifest="$1"; shift
	# jq args:
	#   -r \                        # raw output (i.e. don't add quotes)
	#   -f $_lib/manifest.jq \      # the manifest processing library
	#   --arg system $system \      # set "$system"
	#   --slurpfile manifest "$1" \ # slurp json into "$manifest"
	local jqargs=("-r" "-f" "$_lib/manifestTOML.jq")

	# Add "slurp" mode for pulling manifest from STDIN.
	jqargs+=("-s")

	# Append various args.
	jqargs+=("--arg" "system" "$NIX_CONFIG_system")
	jqargs+=("--argjson" "verbose" "$verbose")
	jqargs+=("--arg" "profileUserName" "$profileUserName")
	jqargs+=("--arg" "profileName" "$profileName")
	jqargs+=("--arg" "FLOX_PATH_PREPEND" "$FLOX_PATH_PREPEND")

	# Append remaining args using jq "--args" flag and "--" to
	# prevent jq from interpreting provided args as options.
	jqargs+=("--args" "--" "$@")

	# Finally invoke jq.
	minverbosity=2 $invoke_dasel -f "$manifest" -r toml -w json | $invoke_jq "${jqargs[@]}"
}

# boolPrompt($prompt, $default)
#
# Displays prompt, collects boolean "y/n" response,
# returns 0 for yes and 1 for no.
function boolPrompt() {
	local prompt="$1"; shift
	local default="$1"; shift
	local defaultLower=$(echo $default | tr A-Z a-z)
	local defaultrc
	case "$defaultLower" in
	n|no) defaultrc=1 ;;
	y|yes) defaultrc=0 ;;
	*)
		error "boolPrompt() called with invalid default" < /dev/null
		;;
	esac
	local defaultCaps=$(echo $default | tr a-z A-Z)
	local defaultPrompt=$(echo "y/n" | tr "$defaultLower" "$defaultCaps")
	read -e -p "$prompt ($defaultPrompt) " value
	local valueLower=$(echo $value | tr A-Z a-z)
	case "$valueLower" in
	n|no) return 1 ;;
	y|yes) return 0 ;;
	"") return $defaultrc ;;
	*)
		echo "invalid response \"$value\" .. try again" 1>&2
		boolPrompt "$prompt" "$default"
		;;
	esac
}

#
# registry(registry,command,[args])
#
# Accessor method for jq-based registry library functions.
#
# Usage:
#   registry path/to/registry.json 1 (set|setString) a b c
#   registry path/to/registry.json 1 setNumber a b 3
#   registry path/to/registry.json 1 delete a b c
#   registry path/to/registry.json 1 (addArray|addArrayString) d e f
#   registry path/to/registry.json 1 addArrayNumber d e 6
#   registry path/to/registry.json 1 (delArray|delArrayString) d e f
#   registry path/to/registry.json 1 delArrayNumber d e 6
#   registry path/to/registry.json 1 get a b
#   registry path/to/registry.json 1 dump
#
# Global variable for prompting to confirm existing values.
declare -i getPromptSetConfirm=0
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
		elif [ $getPromptSetConfirm -gt 0 ]; then
			read -e -p "$prompt" -i "$value" value
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
			minverbosity=2 $invoke_jq "${jqargs[@]}" > $_tmpfile
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
			minverbosity=2 $invoke_jq "${jqargs[@]}"
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
	local profileMetaDir="$FLOX_PROFILEMETA/$profileUserName"
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
		"--argjson" "now" "$now"
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

function promptTemplate {
	local -a _cline
	local -a _choices

	_choices=($(
		local count=0
		$invoke_nix eval --raw --apply '
		  x: with builtins; concatStringsSep "\n" (
			attrValues (mapAttrs (k: v: k + " " + v.description) x)
		  ) + "\n"
		' "floxpkgs#templates" | while read -a _cline
		do
			count=$(($count+1))
			echo "$count) ${_cline[0]}: ${_cline[@]:1}" 1>&2
			echo "${_cline[0]}"
		done
	))
	local prompt="Choose template by number: "
	local choice
	while true
	do
		read -e -p "$prompt" choice
		choice=$((choice + 0)) # make int
		if [ $choice -gt 0 -a $choice -le ${#_choices[@]} ]; then
			index=$(($choice - 1))
			echo "${_choices[$index]}"
			return
		fi
		warn "Incorrect choice try again"
	done
	# Not reached
}

function pastTense() {
	local subcommand="$1"
	case "$subcommand" in
	install)           echo "installed";;
	remove)            echo "removed";;
	rollback)          echo "switched to generation";;
	upgrade)           echo "upgraded";;
	wipe-history)      echo "wiped history";;
	*)                 echo "$subcommand";;
	esac
}

function removePathDups {
  for varname in "$@"; do
    declare -A __seen
    __rewrite=
    for i in $(local IFS=:; echo ${!varname}); do
      if [ -z "${__seen[$i]}" ]; then
        __rewrite="$__rewrite${__rewrite:+:}$i"
        __seen[$i]=1
      fi
    done
    export $varname="$__rewrite"
    unset __seen
    unset __rewrite
  done
}

function profileArg() {
	# flox profiles must resolve to fully-qualified paths within
	# $FLOX_PROFILES. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$FLOX_PROFILES ]]; then
			# Path already a floxpm profile - use it.
			echo "$1"
		elif [[ "$1" =~ ^/nix/var/nix/profiles/ ]]; then
			# Path already a nix profile - use it.
			echo "$1"
		elif [[ -L "$1" ]]; then
			# Path is a link - try again with the link value.
			echo $(profileArg $(readlink "$1"))
		else
			error "\"$1\" is not a flox profile path" >&2
		fi
	elif [[ "$1" =~ \	|\  ]]; then
		error "profile \"$1\" cannot contain whitespace" >&2
	else
		local old_ifs="$IFS"
		local IFS=/
		declare -a _parts=($1)
		IFS="$old_ifs"
		if [ ${#_parts[@]} -eq 1 ]; then
			# Return default path for the profile directory.
			echo "$FLOX_PROFILES/${FLOX_USER}/$1"
		elif [ ${#_parts[@]} -eq 2 ]; then
			# Return default path for the profile directory.
			echo "$FLOX_PROFILES/$1"
		else
			usage | error "invalid profile \"$1\""
		fi
	fi
}

# Parses generation from profile path.
function profileGen() {
	local profile="$1"
	local profileName=$($_basename $profile)
	if [   -L "$profile" ]; then
		if [[ $($_readlink "$profile") =~ ^${profileName}-([0-9]+)-link$ ]]; then
			echo ${BASH_REMATCH[1]}
			return
		fi
	fi
}

# Identifies max profile generation.
function maxProfileGen() {
	local profile="$1"
	declare -i max=0
	for i in ${profile}-*-link; do
		if [[ $i =~ ^${profile}-([0-9]+)-link$ ]]; then
			if [ ${BASH_REMATCH[1]} -gt $max ]; then
				max=${BASH_REMATCH[1]}
			fi
		fi
	done
	echo $max
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
		echo "${floxpkgsUri}#${catalogAttrPathPrefix}.${channel}.${stability}.${attrPath}"
	fi
}

# Usage: nix search <installable> [<regexp>]
# If the installable (flake reference) is an exact match
# then the regexp is not required.
function searchArgs() {
	case "${#@}" in
	2)	# Prepend floxpkgsUri to the first argument, and
		# if the first arg is a stability then prepend the
		# channel as well.
		case "$1" in
		stable | staging | unstable)
			echo "${floxpkgsUri}#${catalogAttrPathPrefix}.nixpkgs.$@"
			;;
		*)
			echo "${floxpkgsUri}#${catalogAttrPathPrefix}.$@"
			;;
		esac
		;;
	1)	# Only one arg provided means we have to search
		# across all known flakes. Punt on this for the MVP.
		echo "${floxpkgsUri}#${catalogAttrPathPrefix} $@"
		;;
	0)	error "too few arguments to search command" < /dev/null
		;;
	*)	error "too many arguments to search command" < /dev/null
		;;
	esac
}

#
# Convert gitBaseURL to URL for use in flake registry.
# FIXME: implement real URL parser.
#
function gitBaseURLToFlakeURL() {
	local url="$1"; shift
	if [ "$url" = "git+ssh@github.com:" ]; then
		echo "git+ssh://git@github.com/"
	else
		error "Cannot convert to flake URL: \"$url\"" < /dev/null
	fi
}

# validateTOML(path)
function validateTOML() {
	local path="$1"; shift
	# XXX do more here to highlight what the problem is.
	tmpstderr=$($_mktemp)
	if $_cat $path | $_dasel -p toml >/dev/null 2>$tmpstderr; then
		: confirmed valid TOML
		$_rm -f $tmpstderr
		return 0
	else
		warn "'$path' contains invalid TOML syntax - see below:"
		$_cat $tmpstderr 1>&2
		$_rm -f $tmpstderr
		echo "" 1>&2
		return 1
	fi
}

# vim:ts=4:noet:syntax=bash
