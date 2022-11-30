## Development commands

# flox init
_development_commands+=("init")
_usage["init"]="initialize flox expressions for current project"
function floxInit() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local template
	local pname
	while test $# -gt 0; do
		case "$1" in
		-t | --template) # takes one arg
			shift
			template="$1"
			shift
			;;
		-n | --name) # takes one arg
			shift
			pname="$1"
			shift
			;;
		*)
			usage | error "invalid argument: $1"
			shift
			;;
		esac

	done

	# Select template.
	if [[ -z "$template" ]]; then
		template=$($_nix eval --no-write-lock-file --raw --apply '
		  x: with builtins; concatStringsSep "\n" (
			attrValues (mapAttrs (k: v: k + ": " + v.description) (removeAttrs x ["_init"]))
		  )
		' "flox#templates" | $_gum filter | $_cut -d: -f1)
		[ -n "$template" ] || exit 1
	fi

	# Identify pname.
	if [[ -z "$pname" ]]; then
		local origin=$($_git remote get-url origin)
		local bn=${origin//*\//}
		local pname=$($_gum input --value "${bn//.git/}" --prompt "Enter package name: ")
		[ -n "$pname" ] || exit 1
	fi

	# Extract flox _init template if it hasn't already.
	[ -f flox.nix ] || {
		# Start by extracting "_init" template to floxify project.
		$invoke_nix flake init --template "flox#templates._init" "$@"
	}

	# Extract requested template.
	$invoke_nix "${_nixArgs[@]}" flake init --template "flox#templates.$template" "$@"
	if [ -f pkgs/default.nix ]; then
		$invoke_mkdir -p "pkgs/$pname"
		$invoke_git mv pkgs/default.nix "pkgs/$pname/default.nix"
		echo "renamed: pkgs/default.nix -> pkgs/$pname/default.nix" 1>&2
		$invoke_sed -i -e \
			"s/pname = \".*\";/pname = \"$pname\";/" \
			"pkgs/$pname/default.nix"
	fi
}

# flox build
_development_commands+=("build")
_usage["build"]="build package from current project"
function floxBuild() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a buildArgs=()
	local -a installables=()
	while test $# -gt 0; do
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-build option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are `nix build` args.

		# Options taking two args.
		--out-link|-o|--profile|--override-flake|--override-input)
			buildArgs+=("$1"); shift
			buildArgs+=("$1"); shift
			buildArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			buildArgs+=("$1"); shift
			buildArgs+=("$1"); shift
			;;
		# Options taking zero args.
		-*)
			buildArgs+=("$1"); shift
			;;
		# Assume all other options are installables.
		*)
			installables+=("$1"); shift
			;;
		esac

	done

	# If no installables specified then try identifying attrPath from
	# capacitated flake.
	if [ ${#installables[@]} -eq 0 ]; then
		local attrPath="$(selectAttrPath . build)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" build --impure "${buildArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY
}

# flox develop
_development_commands+=("develop")
_usage["develop"]="launch development shell for current project"
function floxDevelop() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a developArgs=()
	local -a installables=()
	local -a remainingArgs=()
	while test $# -gt 0; do
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-build option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are `nix build` args.

		# Options taking two args.
		--redirect|--arg|--argstr|--override-flake|--override-input)
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--keep|-k|--phase|--profile|--unset|-u|--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			;;
		# Options that consume remaining arguments
		--command|-c)
			remainingArgs+=("$@")
			break
			;;
		# Options taking zero args.
		-*)
			developArgs+=("$1"); shift
			;;
		# Assume first unknown option is an installable and the rest are for commands.
		*)
			if [ ${#installables[@]} -eq 0 ]; then
				installables=("$1"); shift
			else
				remainingArgs+=("$1"); shift
			fi
			;;
		esac

	done

	# If no installables specified then try identifying attrPath from
	# capacitated flake.
	if [ ${#installables[@]} -eq 0 ]; then
		local attrPath="$(selectAttrPath . develop)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" develop --impure "${developArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# flox run
_development_commands+=("run")
_usage["run"]="run app from current project"
function floxRun() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a runArgs=()
	local -a installables=()
	local -a remainingArgs=()
	while test $# -gt 0; do
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-run option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are `nix run` args.

		# Options taking two args.
		--arg|--argstr|--override-flake|--override-input)
			runArgs+=("$1"); shift
			runArgs+=("$1"); shift
			runArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			runArgs+=("$1"); shift
			runArgs+=("$1"); shift
			;;
		# Options that consume remaining arguments
		--)
			remainingArgs+=("$@")
			break
			;;
		# Options taking zero args.
		-*)
			runArgs+=("$1"); shift
			;;
		# nix will potentially still grab args after the installable, but we have no need to parse them
		# we aren't grabbing any flox specific args though, so flox run .#installable --arg-for-flox won't
		# work
		*)
			if [ ${#installables[@]} -eq 0 ]; then
				installables=("$1"); shift
			else
				remainingArgs+=("$1"); shift
			fi
			;;
		esac

	done

	# If no installables specified then try identifying attrPath from
	# capacitated flake.
	if [ ${#installables[@]} -eq 0 ]; then
		local attrPath="$(selectAttrPath . run)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" run --impure "${runArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# flox shell
_development_commands+=("shell")
_usage["shell"]="run a shell in which the current project is available"
function floxShell() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a shellArgs=()
	local -a installables=()
	local -a remainingArgs=()
	while test $# -gt 0; do
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-run option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are `nix run` args.

		# Options taking two args.
		--arg|--argstr|--override-flake|--override-input)
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--keep|-k|--unset|-u|--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
			;;
		# Options that consume remaining arguments
		--command|-c)
			remainingArgs+=("$@")
			break
			;;
		# Options taking zero args.
		-*)
			shellArgs+=("$1"); shift
			;;
		# Assume all other options are installables.
		*)
			installables+=("$1"); shift
			;;
		esac

	done

	# If no installables specified then try identifying attrPath from
	# capacitated flake.
	if [ ${#installables[@]} -eq 0 ]; then
		local attrPath="$(selectAttrPath . shell)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" shell --impure "${shellArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# vim:ts=4:noet:syntax=bash
