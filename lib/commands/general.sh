## General commands

_general_commands+=("channels")
_usage["channels"]="list channel subscriptions"

_general_commands+=("subscribe")
_usage["subscribe"]="subscribe to channel URL"
_usage_options["subscribe"]="[<name> [<url>]]"

_general_commands+=("unsubscribe")
_usage["unsubscribe"]="unsubscribe from channel"
_usage_options["unsubscribe"]="[<name>]"

_general_commands+=("search")
_usage["search"]="search packages in subscribed channels"
_usage_options["search"]="[(-c|--channel) <channel>] [--json] <args>"
function floxSearch() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	packageregexp=
	declare -i jsonOutput=0
	declare refreshArg
	declare -a channels=()
	while test $# -gt 0; do
		case "$1" in
		-c | --channel)
			shift
			channels+=("$1")
			shift
			;;
		--show-libs)
			# Not yet supported; will implement when catalog has hasBin|hasMan.
			shift
			;;
		--all)
			packageregexp="."
			shift
			;;
		--refresh)
			refreshArg="--refresh"
			shift
			;;
		--json)
			jsonOutput=1
			shift
			;;
		*)
			if [ "$subcommand" = "packages" ]; then
				# Expecting a channel name (and optionally a jobset).
				packageregexp="^$1\."
			elif [ -z "$packageregexp" ]; then
				# Expecting a package name (or part of a package name)
				packageregexp="$1"
				# In the event that someone has passed a space or "|"-separated
				# search term (thank you Eelco :-\), turn that into an equivalent
				# regexp.
				if [[ "$packageregexp" =~ [:space:] ]]; then
					packageregexp="(${packageregexp// /|})"
				fi
			else
				usage | error "multiple search terms provided"
			fi
			shift
			;;
		esac
	done
	[ -n "$packageregexp" ] ||
		usage | error "missing channel argument"
	[ -z "$@" ] ||
		usage | error "extra arguments \"$@\""
	if [ -z "$GREP_COLOR" ]; then
		export GREP_COLOR='1;32'
	fi
	if [ $jsonOutput -gt 0 ]; then
		cmd=(searchChannels "$packageregexp" ${channels[@]} $refreshArg)
	else
		# Use grep to highlight text matches, but also include all the lines
		# around the matches by using the `-C` context flag with a big number.
		# It's also unfortunate that the Linux version of `column` which
		# supports the `--keep-empty-lines` option is not available on Darwin,
		# so we instead embed a line with "---" between groupings and then use
		# `sed` below to replace it with a blank line.
		searchChannels "$packageregexp" ${channels[@]} $refreshArg | \
			$_jq -r -f "$_lib/search.jq" | $_column -t -s "|" | $_sed 's/^---$//' | \
			$_grep -C 1000000 --ignore-case --color -E "$packageregexp"
	fi
}

_general_commands+=("config")
_usage["config"]="configure user parameters"

_general_commands+=("gh")
_usage["gh"]="access to the gh CLI"

_general_commands+=("(envs|environments)")
_usage["(envs|environments)"]="list all available environments"
function floxEnvironments() {
	trace "$@"
	local system="$1"; shift
	[ $# -eq 0 ] || usage | error "the 'flox environments' command takes no arguments"
	# For each environmentMetaDir, list environment
	for i in $FLOX_META/*; do
		if [ -d $i ]; then
			[ -L $i ] || listEnvironments $system $i
		fi
	done
}

# vim:ts=4:noet:syntax=bash
