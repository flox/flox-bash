#!/bin/sh
#
# flox.sh - Flox CLI
#

# Ensure that the script dies on any error.
set -e
set -o pipefail

# Declare default values for debugging variables.
declare -i verbose=0
declare -i debug=0

# Declare global variables
declare -i floxMetricsConsent=0
declare -i educatePublish=0
declare -i interactive=0

# set -x if debugging, can never remember which way this goes so do both.
# Note need to do this here in addition to "-d" flag to be able to debug
# initial argument parsing.
test -z "${DEBUG_FLOX}" || FLOX_DEBUG="${DEBUG_FLOX}"
test -z "${FLOX_DEBUG}" || set -x

# Similar for verbose.
test -z "${FLOX_VERBOSE}" || verbose=1

# Import configuration, load utility functions, etc.
_prefix="@@PREFIX@@"
_prefix=${_prefix:-.}
_lib=$_prefix/lib
_etc=$_prefix/etc
_share=$_prefix/share

# If the first arguments are any of -d|--date, -v|--verbose or --debug
# then we consume this (and in the case of --date, its argument) as
# argument(s) to the wrapper and not the command to be wrapped. To send
# either of these arguments to the wrapped command put them at the end.
while [ $# -ne 0 ]; do
	case "$1" in
	--stability)
		shift
		if [ $# -eq 0 ]; then
			echo "ERROR: missing argument to --stability flag" 1>&2
			exit 1
		fi
		export FLOX_STABILITY="$1"
		shift
		;;
	-d | --date)
		shift
		if [ $# -eq 0 ]; then
			error "missing argument to --date flag" </dev/null
		fi
		export FLOX_RENIX_DATE="$1"
		shift
		;;
	-v | --verbose)
		let ++verbose
		shift
		;;
	--debug)
		let ++debug
		[ $debug -le 1 ] || set -x
		let ++verbose
		shift
		;;
	--prefix)
		echo "$_prefix"
		exit 0
		;;
	-V | --version)
		echo "Version: @@VERSION@@"
		exit 0
		;;
	-h | --help)
		# Perform initialization to pull in usage().
		. $_lib/init.sh
		usage
		exit 0
		;;
	*) break ;;
	esac
done

# Perform initialization with benefit of flox CLI args set above.
. $_lib/init.sh

#
# main()
#

# Start by identifying subcommand to be invoked.
# FIXME: use getopts to properly scan args for first non-option arg.
while test $# -gt 0; do
	case "$1" in
	-*)
		error "unrecognised option before subcommand" </dev/null
		;;
	*)
		subcommand="$1"
		shift
		break
		;;
	esac
done
if [ -z "$subcommand" ]; then
	usage | error "command not provided"
fi

# Flox aliases
if [ "$subcommand" = "rm" ]; then
	subcommand=remove
fi

# Store the original invocation arguments.
declare -a invocation_args=("$@")
declare invocation_string=$(pprint "$me" "$subcommand" "$@")

# Flox environment path(s).
declare -a environments=()

# Build log message as we go.
logMessage=

# Add metric for this invocation in the background.
submitMetric "$subcommand" &

case "$subcommand" in

# Flox commands which take an (-e|--environment) environment argument.
activate | history | install | list | remove | rollback | \
	switch-generation | upgrade | wipe-history | \
	import | export | edit | generations | git | push | pull | destroy)

	# Look for the --environment argument(s).
	args=()
	while test $# -gt 0; do
		case "$1" in
		-e | --environment)
			environments+=($(environmentArg $2))
			shift 2
			;;
		*)
			args+=("$1")
			shift
			;;
		esac
	done
	defaultEnv=$(environmentArg "default")
	if [ ${#environments[@]} -eq 0 ]; then
		environments+=($defaultEnv)
	fi

	# Only the "activate" subcommand accepts multiple environments.
	if [ "$subcommand" != "activate" -a ${#environments[@]} -gt 1 ]; then
		usage | error "\"$subcommand\" does not accept multiple -e|--environment arguments"
	fi

	environment=${environments[0]}
	environmentOwner=$($_basename $($_dirname $environment))
	environmentMetaDir="$FLOX_META/$environmentOwner"
	environmentStartGen=$(environmentGen "$environment")

	[ $verbose -eq 0 ] || [ "$subcommand" = "activate" ] || echo Using environment: $environment >&2

	case "$subcommand" in

	## Environment commands
	# Reminder: "${args[@]}" has the environment arg removed.
	activate)
		floxActivate "${environments[*]}" "$NIX_CONFIG_system" "${args[@]}";;
	destroy)
		floxDestroy "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	edit)
		floxEdit "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	export)
		floxExport "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	generations)
		floxGenerations "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	git)
		floxGit "$environment" "${args[@]}";;
	history)
		floxHistory "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	import)
		floxImport "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	install)
		floxInstall "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	list)
		floxList "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	push | pull)
		floxPushPull "$subcommand" "$environment" "$NIX_CONFIG_system" ${args[@]};;
	remove)
		floxRemove "$environment" "$NIX_CONFIG_system" "${args[@]}";;
	rollback|switch-generation)
		if [ "$subcommand" = "switch-generation" ]; then
			# rewrite switch-generation to instead use the new
			# "rollback --to" command (which makes no sense IMO).
			args=("--to" "${args[@]}")
		fi
		floxRollback "$environment" "$NIX_CONFIG_system" $subcommand "${args[@]}";;
	upgrade)
		floxUpgrade "$environment" "$NIX_CONFIG_system" "${args[@]}";;

	wipe-history)
		error not implemented < /dev/null;;
	*)
		usage | error "Unknown command: $subcommand"
		;;

	esac
	;;

# Flox commands which derive an attribute path from the current directory.
build | develop | eval | publish | run | shell)
	case "$subcommand" in
	build)
		floxBuild "$@"
		;;
	develop)
		floxDevelop "$@"
		;;
	eval)
		floxEval "$@"
		;;
	publish)
		floxPublish "$@"
		;;
	run)
		floxRun "$@"
		;;
	shell)
		floxShell "$@"
		;;
	esac
	;;

# The environments subcommand takes no arguments.
envs | environments)
	floxEnvironments "$NIX_CONFIG_system" "${invocation_args[@]}"
	;;

gh)
	verboseExec $_gh "$@"
	;;

init)
	floxInit "$@"
	;;

packages|search)
	floxSearch "$@"
	;;

# Special "cut-thru" mode to invoke Nix directly.
nix)
	if [ -n "$FLOX_ORIGINAL_NIX_GET_COMPLETIONS" ]; then
		export NIX_GET_COMPLETIONS="$(( FLOX_ORIGINAL_NIX_GET_COMPLETIONS - 1 ))"
	fi
	verboseExec $_nix "$@"
	;;

config)
	declare -i configListMode=0
	declare -i configResetMode=0
	for arg in "$@"; do
		case "$arg" in
		--list|-l)
			configListMode=1
			shift
			;;
		--reset|-r)
			configResetMode=1
			shift
			;;
		--confirm|-c)
			getPromptSetConfirm=1
			shift
			;;
		*)
			usage | error "unexpected argument \"$arg\" passed to \"$subcommand\""
			;;
		esac
	done
	if [ $configListMode -eq 0 ]; then
		if [ $configResetMode -eq 1 ]; then
			# Easiest way to reset is to simply remove the $floxUserMeta file.
			$invoke_rm -f $floxUserMeta
		fi
		bootstrap
	fi
	# Finish by listing values.
	registry $floxUserMeta 1 dump |
		$_jq -r 'del(.version) | to_entries | map("\(.key) = \"\(.value)\"") | .[]'
	;;

subscribe)
	if [ ${#invocation_args[@]} -gt 2 ]; then
		usage | error "extra arguments provided to \"$subcommand\""
	fi
	subscribeFlake ${invocation_args[@]}
	;;

unsubscribe)
	if [ ${#invocation_args[@]} -gt 1 ]; then
		usage | error "extra arguments provided to \"$subcommand\""
	fi
	unsubscribeFlake ${invocation_args[@]}
	;;

channels | list-channels)
	if [ ${#invocation_args[@]} -gt 0 ]; then
		usage | error "extra arguments provided to \"$subcommand\""
	fi
	listChannels
	;;

help)
	# Believe it or not the man package relies on finding both "cat" and
	# "less" in its PATH, and even when we patch the man package it then
	# calls "nroff" (in the groff package) which is similarly broken.
	# So, for this one instance just add coreutils & less to the PATH.
	export PATH="@@FLOXPATH@@"
	verboseExec $_man -l "$_share/man/man1/flox.1.gz"
	;;

*)
	verboseExec $_nix "$subcommand" "$@"
	;;

esac

# vim:ts=4:noet:syntax=bash
