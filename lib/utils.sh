#
# Utility functions.
#

# Color highlighting variables.
ESC="\x1b["

# flox color palette.
#201e7b, nearest named: midnight blue(HTML104), dark slate blue(HTML122)*
DARKBLUE="32;30;123"
DARKBLUE256=17 # NavyBlue, by eye
#58569c, nearest named: dark slate blue(HTML122), slate blue(HTML123)*
LIGHTBLUE="88;86;156"
LIGHTBLUE256=61 # SlateBlue3
#ffceac, nearest named: peach puff(HTML32)*, navajo white(HTML40)
LIGHTPEACH="255;206;172"
LIGHTPEACH256=223 # NavajoWhite1
#ffb990, nearest named: dark salmon(HTML11), light salmon(HTML9)*
DARKPEACH="255;185;144"
DARKPEACH256=216 # LightSalmon1
# 256-color terminal escape sequences.
floxDarkBlue="${ESC}38;5;${DARKBLUE256}m"
floxLightBlue="${ESC}38;5;${LIGHTBLUE256}m"
floxDarkPeach="${ESC}38;5;${DARKPEACH256}m"
floxLightPeach="${ESC}38;5;${LIGHTPEACH256}m"

# Standard 16-color escape sequences.
colorBlack="${ESC}0;30m"
colorDarkGray="${ESC}1;30m"
colorRed="${ESC}0;31m"
colorLightRed="${ESC}1;31m"
colorGreen="${ESC}0;32m"
colorLightGreen="${ESC}1;32m"
colorOrange="${ESC}0;33m"
colorYellow="${ESC}1;33m"
colorBlue="${ESC}0;34m"
colorLightBlue="${ESC}1;34m"
colorPurple="${ESC}0;35m"
colorLightPurple="${ESC}1;35m"
colorCyan="${ESC}0;36m"
colorLightCyan="${ESC}1;36m"
colorLightGray="${ESC}0;37m"
colorWhite="${ESC}1;37m"

# Simple font effects.
colorReset="${ESC}0m"
colorBold="${ESC}1m"
colorFaint="${ESC}2m"
colorItalic="${ESC}3m"
colorUnderline="${ESC}4m"
colorSlowBlink="${ESC}5m"
colorRapidBlink="${ESC}6m"
colorReverseVideo="${ESC}7m"

# Set gum color palette.
# GUM_SPIN_* buggy in v0.4.0
export GUM_SPIN_FOREGROUND=$DARKPEACH256
export GUM_CHOOSE_CURSOR_FOREGROUND="$DARKPEACH256"
export GUM_CHOOSE_PROMPT_FOREGROUND="$LIGHTBLUE256"
export GUM_CHOOSE_SELECTED_CURSOR_FOREGROUND="$DARKPEACH256"
export GUM_CHOOSE_SELECTED_PROMPT_FOREGROUND="$LIGHTBLUE256"

export GUM_FILTER_INDICATOR_FOREGROUND="$LIGHTBLUE256"
export GUM_FILTER_MATCH_FOREGROUND="$DARKPEACH256"
export GUM_FILTER_PROMPT_FOREGROUND="$DARKBLUE256"

export GUM_INPUT_CURSOR_FOREGROUND="$DARKPEACH256"
export GUM_INPUT_PROMPT_FOREGROUND="$DARKPEACH256"

function pprint() {
	# Step through args and encase with single-quotes those which need it.
	local space=""
	for i in "$@"; do
		if [ -z "$i" ]; then
			# empty arg
			echo -e -n "$space''"
		elif [[ "$i" =~ ^\'.*\'$ ]]; then
			# already quoted
			echo -e -n "$space$i"
		elif [[ "$i" =~ ^\".*\"$ ]]; then
			# already quoted(?)
			echo -e -n "$space$i"
		elif [[ "$i" =~ ([ !()|]) ]]; then
			echo -e -n "$space'$i'"
		else
			echo -e -n "$space$i"
		fi
		space=" "
	done
	echo ""
}

#
# trace( <args> )
#
# Utility function which prints to STDERR a colorized call stack
# along with the supplied args.
filecolor=$colorBold
funccolor=$colorCyan
argscolor=$floxLightPeach
function trace() {
	[ $debug -gt 0 ] || return 0
	echo -e "trace:${filecolor}${BASH_SOURCE[2]}:${BASH_LINENO[1]}${colorReset} ${funccolor}${FUNCNAME[1]}${colorReset}( ${argscolor}"$(pprint "$@")"${colorReset} )" 1>&2
}

# Track exported environment variables for use in verbose output.
declare -A exported_variables
function hash_commands() {
	trace "$@"
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
			exported_variables[$(type -P $i)]="NIX_REMOTE NIX_SSL_CERT_FILE NIX_USER_CONF_FILES GIT_CONFIG_SYSTEM" ;;
		*) ;;
		esac
	done
}

# Before doing anything take inventory of all commands required by the script.
# Note that we specifically avoid modifying the PATH environment variable to
# avoid leaking Nix paths into the commands we invoke.
# TODO replace each use of $_cut and $_tr with shell equivalents.
hash_commands \
	ansifilter awk basename bash cat chmod cmp column cp cut dasel date dirname \
	id jq getent gh git gum grep ln man mkdir mktemp mv nix nix-store parallel pwd \
	readlink realpath rm rmdir sed sh sleep sort stat tail touch tr xargs zgrep

# Return full path of first command available in PATH.
#
# Usage: first_in_PATH foo bar baz
function first_in_PATH() {
	trace "$@"
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

# info() prints to STDERR
function info() {
	trace "$@"
	[ ${#@} -eq 0 ] || echo "$@" 1>&2
}

# warn() prints to STDERR in bold color
function warn() {
	trace "$@"
	[ ${#@} -eq 0 ] || echo -e "${colorBold}${@}${colorReset}" 1>&2
}

# error() prints spaces around the arguments, prints to STDERR in
# bold color and then exits nonzero (unless in interactive shell).
function error() {
	trace "$@"
	info "" # Add space before printing error.
	[ ${#@} -eq 0 ] || warn "ERROR: $@"
	info "" # Add space before appending output.
	# Relay any STDIN out to STDERR.
	$_cat 1>&2
	# Don't exit from interactive shells (for debugging).
	case "$-" in
	*i*) : ;;
	*) exit 1 ;;
	esac
}

declare -A _usage
declare -A _usage_options
declare -a _development_commands
declare -a _environment_commands
declare -a _general_commands
function usage() {
	trace "$@"
	$_cat <<EOF 1>&2
usage: $me [ (-h|--help) ] [ --version ] [ --prefix ]
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
    flox packages [ --all | stability[.channel[.package]] ] [--show-libs]
        list all packages or filtered by channel[.subchannel[.package]]
        --show-libs: include library packages
    flox builds <stability>.<channel>.<package>
        list all available builds for specified package
    flox environments
        list all available environments
    flox activate [ (-e|--environment) <environment> ]
        in current shell: . <(flox activate)
        in subshell: flox activate
        for command: flox activate -- <command> <args>
    flox config - configure user parameters
    flox gh - access to the gh CLI
    flox git - access to the git CLI

EOF

	echo "flox development commands:" 1>&2
	for _command in "${_development_commands[@]}"; do
		if [ ${_usage_options["$_command"]+_} ]; then
			echo "    flox $_command ${_usage_options[$_command]}"
			echo "         - ${_usage[$_command]}"
		else
			echo "    flox $_command - ${_usage[$_command]}"
		fi
	done 1>&2
	echo "" 1>&2

	echo "flox environment commands:" 1>&2
	for _command in "${_environment_commands[@]}"; do
		if [ ${_usage_options["$_command"]+_} ]; then
			echo "    flox $_command ${_usage_options[$_command]}"
			echo "         - ${_usage[$_command]}"
		else
			echo "    flox $_command - ${_usage[$_command]}"
		fi
	done 1>&2
	echo "" 1>&2
}

#
# invoke(${cmd_and_args[@]})
#
# Helper function to print invocation to terminal when
# running with verbose flag.
#
declare -i minverbosity=1
function invoke() {
	trace "$@"
	local vars=()
	if [ $verbose -ge $minverbosity ]; then
		for i in ${exported_variables[$1]}; do
			vars+=($(eval "echo $i=\${$i}"))
		done
		pprint "+$colorBold" "${vars[@]}" "$@" "$colorReset" 1>&2
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
	trace "$@"
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

	# Append arg which defines $catalogEvalAttrPathPrefix.
	jqargs+=("--arg" "catalogEvalAttrPathPrefix" "$catalogEvalAttrPathPrefix")

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
	trace "$@"
	local manifest="$1"; shift
	# Bootstrap: will not exist at first for a new user/environment.
	[ -e "$manifest" ] || return
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
	jqargs+=("--arg" "profileOwner" "$profileOwner")
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
	trace "$@"
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
	local value
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

# gitConfigSet($varname, $default)
function gitConfigSet() {
	trace "$@"
	local varname="$1"; shift
	local prompt="$1"; shift
	local default="$1"; shift
	local value="$default"
	while true
	do
		read -e -p "$prompt" -i "$value" value
		if boolPrompt "OK to invoke: 'git config --global $varname \"$value\"'" "yes"; then
			$_git config --global "$varname" "$value"
			break
		else
			info "OK, will try that again"
		fi
	done
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
	trace "$@"
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
	trace "$@"
	registry "$_etc/nix/registry.json" 2 "$@"
}

#
# profileRegistry($profile,command,[args])
# XXX refactor; had to duplicate above to add $profileName.  :-\
#
function profileRegistry() {
	trace "$@"
	local profile="$1"; shift
	local profileDir=$($_dirname $profile)
	local profileName=$($_basename $profile)
	local profileOwner=$($_basename $($_dirname $profile))
	local profileMetaDir="$FLOX_META/$profileOwner"
	local registry="$profileMetaDir/metadata.json"
	local version=1

	# First verify that the clone is not out of date and check
	# out requested branch.
	# XXX refactor: migrate this to lib/metadata.sh?
	gitCheckout "$profileMetaDir" "${NIX_CONFIG_system}.${profileName}"

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

#
# multChoice($prompt $thing)
#
# usage: multChoice "Your favorite swear variable" "variable" \
#   "foo: description of foo" "bar: description of bar"
#
function multChoice {
	trace "$@"

	local prompt="$1"; shift
	local thing="$1"; shift
	# ... choices follow in "$@"

	local -a _choices

	echo 1>&2
	echo "$prompt" 1>&2
	_choices=($(
		local -i count=0
		while [ $# -gt 0 ]
		do
			let ++count
			# Prompt user to STDERR
			echo "$count) $1" 1>&2
			# Echo choice to STDOUT
			echo "${1//:*/}"
			shift
		done
	))

	local choice
	while true
	do
		read -e -p "Choose $thing by number: " choice
		choice=$((choice + 0)) # make int
		if [ $choice -gt 0 -a $choice -le ${#_choices[@]} ]; then
			index=$(($choice - 1))
			echo "${_choices[$index]}"
			return
		fi
		info "Incorrect choice try again"
	done
	# Not reached
}

function promptTemplate {
	trace "$@"
	local IFS=$'\n'
	local -a args=( $( $_nix eval --no-write-lock-file --raw --apply '
	  x: with builtins; concatStringsSep "\n" (
		attrValues (mapAttrs (k: v: k + ": " + v.description) x)
	  )
	' "flox#templates" ) )
	multChoice "" "template" "${args[@]}"
}

function pastTense() {
	trace "$@"
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
	trace "$@"
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
	trace "$@"
	# flox profiles must resolve to fully-qualified paths within
	# $FLOX_ENVIRONMENTS. Resolve paths in a variety of ways:
	if [[ ${1:0:1} = "/" ]]; then
		if [[ "$1" =~ ^$FLOX_ENVIRONMENTS ]]; then
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
			echo "$FLOX_ENVIRONMENTS/$profileOwner/$1"
		elif [ ${#_parts[@]} -eq 2 ]; then
			# Return default path for the profile directory.
			echo "$FLOX_ENVIRONMENTS/$1"
		else
			usage | error "invalid profile \"$1\""
		fi
	fi
}

# Parses generation from profile path.
function profileGen() {
	trace "$@"
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
	trace "$@"
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

# Package args can take one of the following formats:
# 1) flake references containing "#" character: return as-is.
# 2) positional integer references containing only numbers [0-9]+.
# 3) paths which resolve to /nix/store/*: return first 3 path components.
# 4) floxpkgs "[[stability.]channel.]attrPath" tuple: convert to flox catalog
#    flake reference, e.g.
#      stable.nixpkgs.yq ->
#        flake:nixpkgs#catalog.aarch64-darwin.stable.yq
function floxpkgArg() {
	trace "$@"
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
		# Derive fully-qualified floxTuple.
		local IFS='.'
		local -a input=($1)
		local floxTuple=
		case "${input[0]}" in
		stable | staging | unstable)
			if [ ${validChannels["${input[1]}"]+_} ]; then
				# stability.channel.attrPath
				# They did all the work for us.
				floxTuple="$1"
			else
				# stability.attrPath .. perhaps we shouldn't support this?
				# Inject "nixpkgs" as the default channel.
				floxTuple="${input[0]}.nixpkgs.${input[@]:1}"
			fi
			;;
		*)
			if [ ${validChannels["${input[0]}"]+_} ]; then
				# channel.attrPath
				floxTuple="stable.$1"
			else
				# attrPath
				floxTuple="stable.nixpkgs.$1"
			fi
			;;
		esac

		# Convert "attrPath@x.y.z" to "attrPath.x_y_z" because that
		# is how it appears in the flox catalog.
		if [[ "$floxTuple" =~ ^(.*)@(.*)$ ]]; then
			floxTuple="${BASH_REMATCH[1]}.${BASH_REMATCH[2]//[\.]/_}"
		fi

		# Convert fully-qualified floxTuple:
		#   "<stability>.<channel>.<attrPath>"
		# to flakeref:
		#   "flake:<channel>#${catalogEvalAttrPathPrefix}.<stability>.<attrPath>".
		local flakeref=
		local -a _floxTuple=($floxTuple)
		flakeref="flake:${_floxTuple[1]}#${catalogEvalAttrPathPrefix}.${_floxTuple[0]}.${_floxTuple[@]:2}"

		# Return flakeref.
		echo "$flakeref"
	fi
}

#
# Rudimentary pattern-matching URL parser.
# Surprised there's no better UNIX command for this.
#
# Usage:
#	local urlTransport urlHostname urlUsername
#	eval $(parseURL "$url")
#
function parseURL() {
	trace "$@"
	local url="$1"; shift
	local urlTransport urlHostname urlUsername
	case "$url" in
	git+ssh@*:) # e.g. "git+ssh@github.com:"
		urlTransport="${url//@*/}"
		urlHostname="${url//*@/}"
		urlHostname="${urlHostname//:*/}"
		urlUsername="git"
		;;
	https://*|http://*) # e.g. "https://github.com/"
		urlTransport="${url//:*/}"
		urlHostname="$(echo $url | $_cut -d/ -f3)"
		urlUsername=""
		;;
	*)
		error "parseURL(): cannot parse \"$url\"" < /dev/null
		;;
	esac
	echo urlTransport="\"$urlTransport\""
	echo urlHostname="\"$urlHostname\""
	echo urlUsername="\"$urlUsername\""
}

#
# Convert gitBaseURL to URL for use in flake registry.
#
# Flake URLs are a pain, specifying branches in different ways,
# e.g. these are all equivalent:
#
#   git+ssh://git@github.com/flox/floxpkgs?ref=master
#   https://github.com/flox/floxpkgs/archive/master.tar.gz
#   github:flox/floxpkgs/master
#
# Usage:
#	defaultFlake=$(gitBaseURLToFlakeURL ${gitBaseURL} ${organization}/floxpkgs master)
#
function gitBaseURLToFlakeURL() {
	trace "$@"
	local baseurl="$1"; shift
	local path="$1"; shift
	local ref="$1"; shift
	# parseURL() emits commands to set urlTransport, urlHostname and urlUsername.
	local urlTransport urlHostname urlUsername
	eval $(parseURL "$baseurl") || \
		error "cannot convert to flake URL: \"$baseurl\"" < /dev/null
	case $urlTransport in
	https|http)
		case $urlHostname in
		github.com)
			echo "github:$path/$ref"
			;;
		*)
			echo "$urlTransport://${urlUsername:+$urlUsername@}$urlHostname/$path/$ref"
			;;
		esac
		;;
	git+ssh)
		echo "$urlTransport://${urlUsername:+$urlUsername@}$urlHostname/$path?ref=$ref"
		;;
	esac
}

# validateTOML(path)
function validateTOML() {
	trace "$@"
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

# validateFlakeURL()
#
# Perform basic sanity check of FlakeURL to make sure it exists.
function validateFlakeURL() {
	trace "$@"
	local flakeURL="$1"; shift
	if $invoke_nix flake metadata "$flakeURL" --no-write-lock-file --json >/dev/null; then
		return 0
	else
		return 1
	fi
}

# Populate user-specific flake registry.
function updateFloxFlakeRegistry() {
	# Set default catalog flake entries.
	registry $floxUserMeta 1 set channels flox github:flox/floxpkgs/master
	registry $floxUserMeta 1 set channels nixpkgs github:flox/nixpkgs-flox/master

	# Render Nix flake registry file using user-provided flake entries.
	# Note: avoids problems to let nix create the temporary file.
	tmpFloxFlakeRegistry=$($_mktemp --dry-run --tmpdir=$FLOX_CONFIG_HOME)
	. <(registry $floxUserMeta 1 get channels | $_jq -r '
	  to_entries | sort_by(.key) | map(
	    "minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry \(.key) \(.value) && validChannels[\(.key)]=1"
	  )[]
	')

	# Add courtesy Nix flake entries for accessing nixpkgs of different stabilities.
	minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry nixpkgs-stable github:flox/nixpkgs/stable
	minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry nixpkgs-staging github:flox/nixpkgs/staging
	minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry nixpkgs-unstable github:flox/nixpkgs/unstable

	if $_cmp --quiet $tmpFloxFlakeRegistry $floxFlakeRegistry; then
		$_rm $tmpFloxFlakeRegistry
	else
		$_mv -f $tmpFloxFlakeRegistry $floxFlakeRegistry
	fi
}

#
# searchChannels($regexp)
#
function searchChannels() {
	trace "$@"
	local regexp="$1"; shift
	# XXX Passing optional arguments with bash is .. problematic.
	# XXX Walk through the remaining arguments looking for options
	# XXX and valid channel references.
	local refreshArg
	local -a channels=()
	while test $# -gt 0; do
		case "$1" in
		--refresh)
			refreshArg="--refresh"
			;;
		*)
			if [ ${validChannels["$1"]+_} ]; then
				channels+=("$1")
			else
				error "invalid channel: $1" < /dev/null
			fi
			;;
		esac
		shift
	done

	# If no channels were passed then search them all.
	if [ ${#channels[@]} -eq 0 ]; then
		channels=($(registry $floxUserMeta 1 get channels | $_jq -r 'keys | sort[]' || true))
	fi

	# Nicely print out commands for debugging. We cannot do this with the
	# usual $invoke_* trick because we're burying the invocation in two
	# layers of `gum` and `parallel`.
	local vars=()
	if [ $verbose -ge $minverbosity ]; then
		for i in ${exported_variables[$_nix]}; do
			vars+=($(eval "echo $i=\${$i}"))
		done
		for _i in ${channels[@]}; do
		  for _j in stable staging unstable; do
			pprint "+$colorBold" "${vars[@]}" \
				$_nix search --log-format bar --json --no-write-lock-file $refreshArg \
				"flake:${_i}#$catalogSearchAttrPathPrefix.${_j}" \'"$packageregexp"\' \
				"$colorReset" 1>&2
		  done
		done
	fi

	# TODO: write our own parallel runner, or better yet port the CLI to a
	# real language.
	local _tmpdir=$(mktemp -d)
	local -a _resultDirs=($(for i in ${channels[@]}; do echo \
		$_tmpdir/1/$i/2/{stable,staging,unstable} $_tmpdir/1/$i/2 $_tmpdir/1/$i; \
		done))
	local -a _seqFiles=($(for i in ${channels[@]}; do echo $_tmpdir/1/$i/2/{stable,staging,unstable}/seq; done))
	local -a _stdoutFiles=($(for i in ${channels[@]}; do echo $_tmpdir/1/$i/2/{stable,staging,unstable}/stdout; done))
	local -a _stderrFiles=($(for i in ${channels[@]}; do echo $_tmpdir/1/$i/2/{stable,staging,unstable}/stderr; done))
	# TODO: use log-format internal-json for conveying status
	# gum BUG: writes the spinner to stdout (dumb) - redirect that to stderr
	# gum BUG: doesn't preserve cmdline quoting properly so add extra quoting
	#     that may bite us someday when they fix their bug upstream
	# gum BUG: version 0.4.0 doesn't honor GUM_SPIN_FOREGROUND env variable
	minverbosity=2 $invoke_gum spin \
		--spinner.foreground="$GUM_SPIN_FOREGROUND" \
		--title="Searching channels: ${channels[*]}" 1>&2 -- \
		$_parallel --no-notice --results $_tmpdir -- \
			$_nix search --log-format bar --json --no-write-lock-file $refreshArg \
			"flake:{1}#${catalogSearchAttrPathPrefix}.{2}" \'"$packageregexp"\' \
			::: ${channels[@]} ::: stable staging unstable

	# The results directory is composed of files of the form:
	#     <seq>/<channel>/{seq,stdout,stderr}
	# Use jq to compile a single json stream from results.
	$_grep --no-filename -v \
	  -e "^evaluating 'catalog\." \
	  -e "not writing modified lock file of flake" \
	  -e ".sqlite' is busy" \
	  -e " Added input " \
	  -e " follows " \
	  -e "\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)" \
	  ${_stderrFiles[@]} 1>&2 || true
	$invoke_jq -r -f "$_lib/merge-search-results.jq" ${_stdoutFiles[@]} | \
		$_jq -r -s add && $_rm -f ${_stdoutFiles[@]}
	$_rm -f ${_seqFiles[@]}
	$_rm -f ${_stderrFiles[@]}
	$_rmdir ${_resultDirs[@]} $_tmpdir/1 $_tmpdir
}

#
# Prompts the user for attrPath to be built/published/etc.
#
function lookupAttrPaths() {
	trace "$@"
	minverbosity=2 $invoke_nix eval ".#packages.$NIX_CONFIG_system" --json | $_jq -r 'keys | sort[]'
}

function selectAttrPath() {
	trace "$@"
	local subcommand="$1"; shift
	local -a attrPaths=($(lookupAttrPaths))
	local attrPath
	if [ ${#attrPaths[@]} -eq 0 ]; then
		error "cannot find attribute path - have you run 'flox init'?" < /dev/null
	elif [ ${#attrPaths[@]} -eq 1 ]; then
		echo "${attrPaths[0]}"
	else
		warn "Select package for flox $subcommand"
		attrPath=$($_gum choose ${attrPaths[*]})
		warn ""
		warn "HINT: avoid selecting a package next time with:"
		echo '{{ Color "'$LIGHTPEACH256'" "'$DARKBLUE256'" "$ flox '$subcommand' -A '$attrPath'" }}' \
		    | $_gum format -t template 1>&2
		echo "$attrPath"
	fi
}

function lookupPublishOrigin() {
	local origin
	if origin=$($_nix eval --raw ".#__reflect.finalFlake.config.publish.origin" 2>/dev/null); then
		echo "$origin"
	fi
}

function ensureGHRepoExists() {
	local origin="$1"
	local visibility="$2"
	local template="$3"
	# If using github, ensure that user is logged into gh CLI
	# and confirm that repository exists.
	if [[ "${origin,,}" =~ github ]]; then
		( $_gh auth status >/dev/null 2>&1 ) ||
			$_gh auth login
		( $_gh repo view "$origin" >/dev/null 2>&1 ) || (
			set -x
			$_gh repo create \
				--"$visibility" "$origin" \
				--template "$template"
		)
	fi
}

# vim:ts=4:noet:syntax=bash
