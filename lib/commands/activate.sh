## Environment commands

# "flox activate" is invoked in three contexts:
# * with arguments: prepend environment bin directories to PATH and
#   invoke the commands provided, else ...
# * interactive: we need to take over the shell "rc" entrypoint
#   so that we can guarantee to prepend to the PATH *AFTER* all
#   other processing has been completed, else ...
# * non-interactive: here we simply prepend to the PATH and set
#   required env variables.

_environment_commands+=("activate")
_usage["activate"]="activate environment:
        in current shell: . <(flox activate)
        in subshell: flox activate
        for command: flox activate -- <command> <args>"

function floxActivate() {
	trace "$@"
	local -a environments=($1); shift
	local system="$1"; shift
	local -a invocation=("$@")

	# The $FLOX_ACTIVE_ENVIRONMENTS variable is colon-separated (like $PATH)
	# and contains the list of fully-qualified active environments by path,
	# e.g. /Users/floxfan/.local/share/flox/environments/local/default.
	# Load this variable into an associative array for convenient lookup.
	declare -A _flox_active_environments
	declare -a _environments_to_activate
	for i in $(IFS=:; echo $FLOX_ACTIVE_ENVIRONMENTS); do
		_flox_active_environments[$i]=1
	done

	# Identify each environment to be activated, taking note to avoid
	# attempting to activate an environment that has already been
	# activated.
	for i in "${environments[@]}"; do
		if [ -z "${_flox_active_environments[$i]}" ]; then
			# Only warn if it's not the default environment.
			if [ "$i" != "$defaultEnv" ]; then
				[ -d "$i/." ] || warn "INFO environment not found: $i"
			fi
			_environments_to_activate+=("$i")
			_flox_active_environments[$i]=1
		elif [ "$i" != "$defaultEnv" ]; then
			# Only throw an error if in an interactive session, and don't
			# throw an error when attempting to activate the default env.
			if [ $interactive -eq 1 ]; then
				error "$i environment already active" < /dev/null
			fi
		fi
	done

	# Add "default" to end of the list if it's not already there.
	# Do this separately from loop above to detect when people
	# explicitly attempt to activate default env twice.
	if [ -z "${_flox_active_environments[$defaultEnv]}" ]; then
		_environments_to_activate+=("$defaultEnv")
		_flox_active_environments[$defaultEnv]=1
	fi

	# Build up string to be prepended to PATH. Add in order provided.
	# Also similarly configure the FLOX_ACTIVE_ENVIRONMENTS variables
	# for each environment to be activated.
	FLOX_PATH_PREPEND=
	FLOX_XDG_DATA_DIRS_PREPEND=
	_flox_active_environments_prepend=
	FLOX_BASH_INIT_SCRIPT=$(mkTempFile)
	for i in "${_environments_to_activate[@]}"; do
		FLOX_PATH_PREPEND="${FLOX_PATH_PREPEND:+$FLOX_PATH_PREPEND:}$i/bin"
		FLOX_XDG_DATA_DIRS_PREPEND="${FLOX_XDG_DATA_DIRS_PREPEND:+$FLOX_XDG_DATA_DIRS_PREPEND:}$i/share"
		_flox_active_environments_prepend="${_flox_active_environments_prepend:+$_flox_active_environments_prepend:}${i}"
		# Activate environment using version-specific logic.
		if [ -f "$i/catalog.json" ]; then
			# New v2 format.
			# Just append the pre-compiled activation script. Lest you be
			# tempted to simply copy this script (as I was) recall that we
			# are appending to a single script containing initialization
			# actions for _all_ environments to be activated.
			$invoke_cat $i/activate >> $FLOX_BASH_INIT_SCRIPT || :
		else
			# Original v1 format.
			# Use 'git show' to grab the correct manifest.toml without checking
			# out the branch, and if the branch or manifest.toml file does not
			# exist then carry on.
			(metaGitShow $i $system manifest.toml 2>/dev/null | manifestTOML bashInit) >> $FLOX_BASH_INIT_SCRIPT || :
		fi
	done
	FLOX_ACTIVE_ENVIRONMENTS=${_flox_active_environments_prepend}${FLOX_ACTIVE_ENVIRONMENTS:+:}${FLOX_ACTIVE_ENVIRONMENTS}
	unset _flox_active_environments_prepend

	# Set the init script to self-destruct upon activation (unless debugging).
	# Very James Bond.
	[ $debug -gt 0 ] || \
		echo "$_rm $FLOX_BASH_INIT_SCRIPT" >> $FLOX_BASH_INIT_SCRIPT

	# FLOX_PROMPT_ENVIRONMENTS is a space-separated list of the
	# abbreviated "alias" names of activated environments for
	# inclusion in the prompt.
	FLOX_PROMPT_ENVIRONMENTS=
	for i in $(IFS=:; echo $FLOX_ACTIVE_ENVIRONMENTS); do
		# Redact $FLOX_ENVIRONMENTS from the path for named environments.
		i=${i/$FLOX_ENVIRONMENTS\//}
		# Redact "$environmentOwner/" from the beginning.
		i=${i/$environmentOwner\//}
		# Anything else containing more than one "/" must be a project env.
		# Replace everything up to the last "/" with "...".
		if [[ "$i" == */*/?* ]]; then
			i=.../${i//*\//}
		fi
		FLOX_PROMPT_ENVIRONMENTS="${FLOX_PROMPT_ENVIRONMENTS:+$FLOX_PROMPT_ENVIRONMENTS }${i}"
	done

	if [ ${#_environments_to_activate[@]} -eq 0 ]; then
		# Only throw an error if an interactive session, otherwise
		# exit quietly.
		if [ $interactive -eq 1 -o $verbose -gt 0 ]; then
			warn "no new environments to activate (active environments: $FLOX_PROMPT_ENVIRONMENTS)"
		fi
		exit 0
	fi

	export FLOX_ACTIVE_ENVIRONMENTS FLOX_PROMPT_ENVIRONMENTS FLOX_PATH_PREPEND FLOX_XDG_DATA_DIRS_PREPEND FLOX_BASH_INIT_SCRIPT
	# Export FLOX_ACTIVATE_VERBOSE for use within flox.profile.
	[ $verbose -eq 0 ] || export FLOX_ACTIVATE_VERBOSE=$verbose

	cmdArgs=()
	inCmdArgs=0
	for arg in "${invocation[@]}"; do
		case "$arg" in
		--)
			inCmdArgs=1
			;;
		*)
			if [ $inCmdArgs -eq 1 ]; then
				cmdArgs+=("$arg")
			else
				usage | error "unexpected argument \"$arg\" passed to \"$subcommand\""
			fi
			;;
		esac
	done

	if [ ${#cmdArgs[@]} -gt 0 ]; then
		export PATH="$FLOX_PATH_PREPEND:$PATH"
		export XDG_DATA_DIRS="$FLOX_XDG_DATA_DIRS_PREPEND:$XDG_DATA_DIRS"

		export FLOX_PATH_PREPEND FLOX_BASH_INIT_SCRIPT \
			FLOX_ACTIVE_ENVIRONMENTS FLOX_PROMPT_ENVIRONMENTS \
			FLOX_XDG_DATA_DIRS_PREPEND
		source "$_etc/flox.profile"
		[ $verbose -eq 0 ] || pprint "+$colorBold" exec "${cmdArgs[@]}" "$colorReset" 1>&2
		exec "${cmdArgs[@]}"
	else
		case "$SHELL" in
		*bash)
			if [ $interactive -eq 1 ]; then
				# TODO: export variable for setting flox env from within flox.profile,
				# *after* the PATH has been set.
				[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$SHELL" "--rcfile" "$_etc/flox.bashrc" "$colorReset" 1>&2
				exec "$SHELL" "--rcfile" "$_etc/flox.bashrc"
			else
				echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\""
				echo "export FLOX_XDG_DATA_DIRS_PREPEND=\"$FLOX_XDG_DATA_DIRS_PREPEND\""
				echo "export FLOX_BASH_INIT_SCRIPT=\"$FLOX_BASH_INIT_SCRIPT\""
				echo "export FLOX_ACTIVE_ENVIRONMENTS=\"$FLOX_ACTIVE_ENVIRONMENTS\""
				echo "export FLOX_PROMPT_ENVIRONMENTS=\"$FLOX_PROMPT_ENVIRONMENTS\""
				echo "source $_etc/flox.profile"
				exit 0
			fi
			;;
		*zsh)
			if [ $interactive -eq 1 ]; then
				# TODO: export variable for setting flox env from within flox.profile,
				# *after* the PATH has been set.
				if [ -n "$ZDOTDIR" ]; then
					[ $verbose -eq 0 ] || warn "+ export FLOX_ORIG_ZDOTDIR=\"$ZDOTDIR\""
					export FLOX_ORIG_ZDOTDIR="$ZDOTDIR"
				fi
				[ $verbose -eq 0 ] || warn "+ export ZDOTDIR=\"$_etc/flox.zdotdir\""
				export ZDOTDIR="$_etc/flox.zdotdir"
				[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$SHELL" "$colorReset" 1>&2
				exec "$SHELL"
			else
				echo "export FLOX_PATH_PREPEND=\"$FLOX_PATH_PREPEND\""
				echo "export FLOX_XDG_DATA_DIRS_PREPEND=\"$FLOX_XDG_DATA_DIRS_PREPEND\""
				echo "export FLOX_BASH_INIT_SCRIPT=\"$FLOX_BASH_INIT_SCRIPT\""
				echo "export FLOX_ACTIVE_ENVIRONMENTS=\"$FLOX_ACTIVE_ENVIRONMENTS\""
				echo "export FLOX_PROMPT_ENVIRONMENTS=\"$FLOX_PROMPT_ENVIRONMENTS\""
				echo "source $_etc/flox.profile"
				exit 0
			fi
			;;
		*)
			if [ $interactive -eq 1 ]; then
				warn "unsupported shell: \"$SHELL\""
				warn "Launching bash instead"
				export SHELL="$_bash"
				[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$SHELL" "--rcfile" "$_etc/flox.bashrc" "$colorReset" 1>&2
				exec "$SHELL" "--rcfile" "$_etc/flox.bashrc"
			else
				error "unsupported shell: \"$SHELL\" - please run 'flox activate' in interactive mode" </dev/null
			fi
			;;
		esac
	fi
}

# vim:ts=4:noet:syntax=bash
