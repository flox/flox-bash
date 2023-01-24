## Environment commands

#
# bashRC($@)
#
# Takes a list of environments and emits bash commands to configure each
# of them in the order provided.
#
function bashRC() {
	trace "$@"
	# Start with required platform-specific Nixpkgs environment variables.
	$_grep -v '^#' $_lib/commands/shells/activate.bash | $_grep -v '^$'
	# Add computed environment variables.
	for i in PATH XDG_DATA_DIRS FLOX_ACTIVE_ENVIRONMENTS FLOX_PROMPT_ENVIRONMENTS FLOX_PROMPT_COLOR_{1,2}; do
		printf 'export %s="%s"\n' $i "${!i}"
	done
	# Add environment-specific activation commands.
	for i in "$@"; do
		if [ -f "$i/activate" ]; then
			$_cat $i/activate
		elif [ -f "$i/manifest.toml" ]; then
			# Original v1 format to be deprecated.
			(metaGitShow $i manifest.toml 2>/dev/null | manifestTOML bashInit) || :
		fi
	done
}

#
# Regardless of the context in which "flox activate" is invoked it does
# three things, although it may not do all of these in every context:
#
#   I. sets environment variables
#   II. runs hooks
#   III. invokes a _single_ command
#
# ... and "flox activate" can be invoked in the following contexts:
#
#   A. with arguments denoting a command to be invoked
#      1. creates an "rc" script in bash (i.e. flox CLI shell)
#      2. if NOT environment already active
#        - appends commands (I && II) to the "rc" script
#      3. source "rc" script directly and exec() $cmdArgs (III)
#   B. in an interactive context
#      1. creates an "rc" script in the language of the user's $SHELL
#      2. if NOT environment already active
#        - appends commands (I && II) to the "rc" script
#      3. exec() $SHELL (III) with "rc" configured to source script
#   C. in a non-interactive context
#      0. confirms the running shell (cannot trust $SHELL)
#      1. creates an "rc" script in the language of the running shell
#      2. if NOT environment already active
#        - appends commands (I && II) to the "rc" script
#      3. cat() contents of "rc" script to stdout (does not invoke anything)
#      4. remove "rc" script
#
# Breaking it down in this way allows us to employ common logic across
# all cases. In the B and C cases we take over the shell "rc" entrypoint
# so that we can guarantee that flox environment directories are prepended
# to the PATH *AFTER* all other processing has been completed. This is
# particularly important in the case of Darwin which has a "path_helper"
# that re-orders the PATH in a decidedly "unhelpful" way with each new
# shell invocation.
#

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
	local -A _flox_active_environments_hash
	local -a _flox_original_active_environments_array
	local -a _environments_to_activate

	local -a cmdArgs=()
	local -i inCmdArgs=0
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

	# The $FLOX_ACTIVE_ENVIRONMENTS variable is colon-separated (like $PATH)
	# and contains the list of fully-qualified active environments by path,
	# e.g. /Users/floxfan/.local/share/flox/environments/local/default.
	# Load this variable into an associative array for convenient lookup.
	for i in $(IFS=:; echo $FLOX_ACTIVE_ENVIRONMENTS); do
		_flox_active_environments_hash["$i"]=1
		_flox_original_active_environments_array+=("$i")
	done

	# Identify each environment to be activated, taking note to avoid
	# attempting to activate an environment that has already been
	# activated.
	for i in "${environments[@]}"; do
		if [ -z "${_flox_active_environments_hash[$i]}" ]; then
			# Only warn if it's not the default environment.
			if [ "$i" != "$defaultEnv" ]; then
				[ -d "$i/." ] || warn "INFO environment not found: $i"
			fi
			_environments_to_activate+=("$i")
			_flox_active_environments_hash["$i"]=1
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
	if [ -z "${_flox_active_environments_hash[$defaultEnv]}" ]; then
		_environments_to_activate+=("$defaultEnv")
		_flox_active_environments_hash["$defaultEnv"]=1
	fi

	# Before possibly bailing out, check to see if any of the active or
	# about-to-be-activated environments have updates pending.
	for environment in "${_environments_to_activate[@]}" "${_flox_original_active_environments_array[@]}"; do
		local -i autoUpdate=$(doAutoUpdate "$environment")
		if [ $autoUpdate -ne 0 ]; then
			local -i updateGen=$(updateAvailable "$environment")
			if [ $updateGen -gt 0 ]; then
				if [ $autoUpdate -eq 1 ]; then
					# set $branchName,$environment{Dir,Name,Alias,Owner,System,MetaDir}
					eval $(decodeEnvironment "$environment")
					if $_gum confirm "'$environmentAlias' is at generation $updateGen, pull latest version?"; then
						floxPushPull pull "$environment" "$system" ${invocation[@]}
					fi
				else # $autoUpdate == 2, aka always pull without prompting
					floxPushPull pull "$environment" "$system" ${invocation[@]}
				fi
			fi
		fi
	done
	trailingAsyncFetch "${_environments_to_activate[@]}" "${_flox_original_active_environments_array[@]}"

	# Warn and exit 0 if interactive and nothing to do.
	if [ $interactive -eq 1 -a ${#cmdArgs[@]} -eq 0 -a ${#_environments_to_activate[@]} -eq 0 ]; then
		warn "no new environments to activate (active environments: $FLOX_PROMPT_ENVIRONMENTS)"
		exit 0
	fi

	# Determine shell language to be used for "rc" script.
	local rcShell
	if [ ${#cmdArgs[@]} -gt 0 ]; then
		rcShell=$_bash # i.e. language of this script
	elif [ $interactive -eq 1 ]; then
		rcShell=$SHELL # i.e. the shell we will be invoking
	else
		# Non-interactive. In this case it's really important to emit commands
		# using the correct syntax, so start by doing everything possible to
		# accurately identify the currently-running (parent) shell.
		rcShell=$(identifyParentShell)
		# Just in case we got it wrong, only trust $rcShell if it "smells like
		# a shell", which AFAIK is best expressed as ending in "sh".
		case "$rcShell" in
		*sh) : ;;
		*) # Weird ... this warrants a warning.
			warn "WARNING: calling process '$rcShell' does not look like a shell .. using '$SHELL' syntax"
			rcShell=$SHELL
			;;
		esac
	fi

	# Build up strings to be prepended to environment variables.
	# Note the requirement to prepend in the order provided, e.g.
	# if activating environments 'A' and 'B' in that order then
	# the string to be prepended to PATH is 'A/bin:B/bin'.
	local -a path_prepend=()
	local -a xdg_data_dirs_prepend=()
	local -a flox_active_environments_prepend=()
	local -a flox_prompt_environments_prepend=()
	for i in "${_environments_to_activate[@]}"; do
		path_prepend+=("$i/bin")
		xdg_data_dirs_prepend+=("$i/share")
		flox_active_environments_prepend+=("$i")
		j=$(environmentPromptAlias "$i")
		flox_prompt_environments_prepend+=("$j")
	done
	export PATH="$(joinString ':' "${path_prepend[@]}" "$PATH")"
	export XDG_DATA_DIRS="$(joinString ':' "${xdg_data_dirs_prepend[@]}" "$XDG_DATA_DIRS")"
	export FLOX_ACTIVE_ENVIRONMENTS="$(joinString ':' "${flox_active_environments_prepend[@]}" "$FLOX_ACTIVE_ENVIRONMENTS")"
	export FLOX_PROMPT_ENVIRONMENTS="$(joinString ' ' "${flox_prompt_environments_prepend[@]}" "$FLOX_PROMPT_ENVIRONMENTS")"

	# Darwin has a "path_helper" which indiscriminately reorders the path to
	# put the Apple-preferred items first in the PATH, which completely breaks
	# the user's ability to manage their PATH in subshells, e.g. when using tmux.
	#
	# Trouble is, there's really no way to undo the damage done by the "path_helper"
	# apart from inflicting the similarly heinous approach of again reordering the
	# PATH to put flox environments at the front. It's fighting fire with fire, but
	# unless we want to risk even further breakage by disabling path_helper in
	# /etc/zprofile this is the best workaround we've come up with.
	#
	# https://discourse.floxdev.com/t/losing-part-of-my-shell-environment-when-using-flox-develop/556/2
	if [[ -x /usr/libexec/path_helper && "$PATH" =~ ^/usr/local/bin: ]]; then
		if [ ${#cmdArgs[@]} -eq 0 -a $interactive -eq 0 ]; then
			case "$rcShell" in
			*bash|*zsh)
				export PATH="$(echo $PATH | $_awk -v shellDialect=bash -f $_libexec/flox/darwin-path-fixer.awk)"
				;;
			esac
		fi
	fi

	# Create "rc" script.
	local rcScript=$(mktemp) # cleans up after itself, do not use mkTempFile()
	case $rcShell in
	*bash)
		bashRC "${_environments_to_activate[@]}" >> $rcScript
		;;
	*zsh)
		# The zsh fpath variable must be prepended with each new subshell.
		local -a fpath_prepend=()
		for i in "${_environments_to_activate[@]}" "${_flox_original_active_environments_array[@]}"; do
			# Add to fpath irrespective of whether the directory exists at
			# activation time because people can install to an environment
			# while it is active and immediately benefit from commandline
			# completion.
			fpath_prepend+=("$i"/share/zsh/site-functions "$i"/share/zsh/vendor-completions)
		done
		if [ ${#fpath_prepend[@]} -gt 0 ]; then
			echo "fpath=(${fpath_prepend[@]} \$fpath)" >> $rcScript
			echo "autoload -U compinit && compinit" >> $rcScript
		fi
		bashRC "${_environments_to_activate[@]}" >> $rcScript
		;;
	*csh|*fish)
		error "unsupported shell: $rcShell" < /dev/null
		;;
	*)
		error "unknown shell: $rcShell" < /dev/null
		;;
	esac

	# Set the init script to self-destruct upon activation (unless debugging).
	# Very James Bond.
	[ $debug -gt 0 ] || echo "$_rm $rcScript" >> $rcScript

	# If invoking a command, go ahead and exec().
	if [ ${#cmdArgs[@]} -gt 0 ]; then
		# Command case - source "rc" script and exec command.
		source $rcScript
		[ $verbose -eq 0 ] || pprint "+$colorBold" exec "${cmdArgs[@]}" "$colorReset" 1>&2
		exec "${cmdArgs[@]}" # Does not return.
	fi

	# Add commands to configure prompt for interactive shells. The
	# challenge here is that this code can be called one or two
	# times for a single activation, i.e. person can do one or
	# both of the following:
	#
	# - invoke 'flox activate -e foo'
	# - have '. <(flox activate)' in .zshrc
	#
	# Our only real defense against this sort of "double activation"
	# is to put guards around our configuration, just as C include
	# files have had since the dawn of time.
	if [ -z "$FLOX_PROMPT_DISABLE" ]; then
		case "$rcShell" in
		*bash)
			cat $_etc/flox.prompt.bashrc >> $rcScript
			;;
		*zsh)
			cat $_etc/flox.zdotdir/prompt.zshrc >> $rcScript
			;;
		esac
	fi

	# Address possibility of corrupt /etc/zshrc* files on Darwin.
	[ "$($_uname -s)" != "Darwin" ] || darwinRepairFiles

	# Activate.
	if [ $interactive -eq 1 ]; then
		# Interactive case - launch subshell.
		case "$rcShell" in
		*bash)
			export FLOX_BASH_INIT_SCRIPT=$rcScript
			[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$rcShell" "--rcfile" "$_etc/flox.bashrc" "$colorReset" 1>&2
			exec "$rcShell" "--rcfile" "$_etc/flox.bashrc"
			;;
		*zsh)
			export FLOX_ZSH_INIT_SCRIPT=$rcScript
			if [ -n "$ZDOTDIR" ]; then
				[ $verbose -eq 0 ] || warn "+ export FLOX_ORIG_ZDOTDIR=\"$ZDOTDIR\""
				export FLOX_ORIG_ZDOTDIR="$ZDOTDIR"
			fi
			[ $verbose -eq 0 ] || warn "+ export ZDOTDIR=\"$_etc/flox.zdotdir\""
			export ZDOTDIR="$_etc/flox.zdotdir"
			[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$rcShell" "$colorReset" 1>&2
			exec "$rcShell"
			;;
		*)
			warn "unsupported shell: \"$rcShell\""
			warn "Launching bash instead"
			[ $verbose -eq 0 ] || pprint "+$colorBold" exec "$rcShell" "--rcfile" "$_etc/flox.bashrc" "$colorReset" 1>&2
			exec "$rcShell" "--rcfile" "$_etc/flox.bashrc"
			;;
		esac
	else
		# Non-interactive case - print out commands to be sourced.
		local _flox_activate_verbose=/dev/null
		[ $verbose -eq 0 ] || _flox_activate_verbose=/dev/stderr
		case "$rcShell" in
		*bash|*zsh)
			$_cat $rcScript | $_tee $_flox_activate_verbose
			;;
		*)
			error "unsupported shell: \"$rcShell\" - please run 'flox activate' in interactive mode" </dev/null
			;;
		esac
	fi
}

# vim:ts=4:noet:syntax=bash
