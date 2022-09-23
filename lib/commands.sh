#
# lib/commands.sh: one function for each subcommand
#
# The design of this library is that common options are first parsed
# in flox.sh, then any command-specific handling is performed from
# within functions in this file.
#
# * functions use local variable declarations wherever possible
# * functions in this file are sorted alphabetically (usage will match!)
# * functions are named "floxCommand" to match the corresponding command
# * _usage* variables are mandatory, defined immediately prior to functions
#   - usage sections (not sorted): general, environment, development
# * functions return a command array to be invoked in the calling function
# named "floxCommand" to match the corresponding command
# * cargo cult: use tabs, comments, formatting, etc. to match existing examples
#

# This first function sorts the provided options and arguments into
# those supported by the top level `nix` command as opposed to its
# various subcommands, as parsed in each of the functions below this
# one. It employs global variables because it's not easy to return
# two output streams with bash.
declare -a _nixArgs
declare -a _cmdArgs
function parseNixArgs() {
	_nixArgs=()
	_cmdArgs=()
	while test $# -gt 0; do
		case "$1" in
		# Options taking two args.
		--option)
			_nixArgs+=("$1"); shift
			_nixArgs+=("$1"); shift
			_nixArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--access-tokens | --allowed-impure-host-deps | --allowed-uris | \
		--allowed-users | --bash-prompt | --bash-prompt-prefix | \
		--bash-prompt-suffix | --build-hook | --build-poll-interval | \
		--build-users-group | --builders | --commit-lockfile-summary | \
		--connect-timeout | --cores | --diff-hook | \
		--download-attempts | --experimental-features | --extra-access-tokens | \
		--extra-allowed-impure-host-deps | --extra-allowed-uris | --extra-allowed-users | \
		--extra-experimental-features | --extra-extra-platforms | --extra-hashed-mirrors | \
		--extra-ignored-acls | --extra-nix-path | --extra-platforms | \
		--extra-plugin-files | --extra-sandbox-paths | --extra-secret-key-files | \
		--extra-substituters | --extra-system-features | --extra-trusted-public-keys | \
		--extra-trusted-substituters | --extra-trusted-users | --flake-registry | \
		--gc-reserved-space | --hashed-mirrors | --http-connections | \
		--ignored-acls | --log-format |--log-lines | \
		--max-build-log-size | --max-free | --max-jobs | \
		--max-silent-time | --min-free | --min-free-check-interval | \
		--nar-buffer-size | --narinfo-cache-negative-ttl | --narinfo-cache-positive-ttl | \
		--netrc-file | --nix-path | --plugin-files | \
		--post-build-hook | --pre-build-hook | --repeat | \
		--sandbox-build-dir | --sandbox-dev-shm-size | --sandbox-paths | \
		--secret-key-files | --stalled-download-timeout | --store | \
		--substituters | --system | --system-features | \
		--tarball-ttl | --timeout | --trusted-public-keys | \
		--trusted-substituters | --trusted-users | --user-agent-suffix)
			_nixArgs+=("$1"); shift
			_nixArgs+=("$1"); shift
			;;
		# Options taking zero args.
		--help | --offline | --refresh | --version | --debug | \
		--print-build-logs | -L | --quiet | --verbose | -v | \
		--accept-flake-config | --allow-dirty | --allow-import-from-derivation | \
		--allow-new-privileges | --allow-symlinked-store | \
		--allow-unsafe-native-code-during-evaluation | --auto-optimise-store | \
		--builders-use-substitutes | --compress-build-log | \
		--enforce-determinism | --eval-cache | --fallback | --filter-syscalls | \
		--fsync-metadata | --http2 | --ignore-try | --impersonate-linux-26 | \
		--keep-build-log | --keep-derivations | --keep-env-derivations | \
		--keep-failed | --keep-going | --keep-outputs | \
		--no-accept-flake-config | --no-allow-dirty | \
		--no-allow-import-from-derivation | --no-allow-new-privileges | \
		--no-allow-symlinked-store | \
		--no-allow-unsafe-native-code-during-evaluation | \
		--no-auto-optimise-store | --no-builders-use-substitutes | \
		--no-compress-build-log | --no-enforce-determinism | --no-eval-cache | \
		--no-fallback | --no-filter-syscalls | --no-fsync-metadata | \
		--no-http2 | --no-ignore-try | --no-impersonate-linux-26 | \
		--no-keep-build-log | --no-keep-derivations | --no-keep-env-derivations | \
		--no-keep-failed | --no-keep-going | --no-keep-outputs | \
		--no-preallocate-contents | --no-print-missing | --no-pure-eval | \
		--no-require-sigs | --no-restrict-eval | --no-run-diff-hook | \
		--no-sandbox | --no-sandbox-fallback | --no-show-trace | \
		--no-substitute | --no-sync-before-registering | \
		--no-trace-function-calls | --no-trace-verbose | --no-use-case-hack | \
		--no-use-registries | --no-use-sqlite-wal | --no-warn-dirty | \
		--preallocate-contents | --print-missing | --pure-eval | \
		--relaxed-sandbox | --require-sigs | --restrict-eval | --run-diff-hook | \
		--sandbox | --sandbox-fallback | --show-trace | --substitute | \
		--sync-before-registering | --trace-function-calls | --trace-verbose | \
		--use-case-hack | --use-registries | --use-sqlite-wal | --warn-dirty)
			_nixArgs+=("$1"); shift
			;;
		# All else are command args.
		*)
			_cmdArgs+=("$1"); shift
			;;
		esac
	done
}


## Development commands

# flox build
_development_commands+=("build")
_usage["build"]="build package from current project"
function floxBuild() {
	trace "$@"
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
		local attrPath="$(selectAttrPath build)"
		installables+=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" build "${installables[@]}" "${buildArgs[@]}" --impure
}

# flox develop
_development_commands+=("develop")
_usage["develop"]="launch development shell for current project"
function floxDevelop() {
	trace "$@"
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a developArgs=()
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
		--command|-c|--redirect|--arg|--argstr|--override-flake|--override-input)
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--keep|-k|--phase|--profile|--unset|-u|--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			developArgs+=("$1"); shift
			developArgs+=("$1"); shift
			;;
		# Options taking zero args.
		-*)
			developArgs+=("$1"); shift
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
		local attrPath="$(selectAttrPath develop)"
		installables+=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" develop "${installables[@]}" "${developArgs[@]}" --impure
}

# flox init
_development_commands+=("init")
_usage["init"]="initialize flox expressions for current project"
function floxInit() {
	trace "$@"

	# Select template.
	local choice=$($_nix eval --no-write-lock-file --raw --apply '
	  x: with builtins; concatStringsSep "\n" (
		attrValues (mapAttrs (k: v: k + ": " + v.description) (removeAttrs x ["_init"]))
	  )
	' "flox#templates" | $_gum filter | $_cut -d: -f1)
	[ -n "$choice" ] || exit 1

	# Identify pname.
	local origin=$($_git remote get-url origin)
	local bn=${origin//*\//}
	local pname=$($_gum input --value "${bn//.git/}" --prompt "Enter package name: ")
	[ -n "$pname" ] || exit 1

	# Extract flox _init template if it hasn't already.
	[ -f flox.nix ] || {
		# Start by extracting "_init" template to floxify project.
		$invoke_nix flake init --template "flox#templates._init" "$@"
	}

	# Extract requested template.
	$invoke_nix flake init --template "flox#templates.$choice" "$@"
	if [ -f pkgs/default.nix ]; then
		$invoke_mkdir -p "pkgs/$pname"
		$invoke_git mv pkgs/default.nix "pkgs/$pname/default.nix"
		echo "renamed: pkgs/default.nix -> pkgs/$pname/default.nix" 1>&2
		$invoke_sed -i -e \
			"s/pname = \".*\";/pname = \"$pname\";/" \
			"pkgs/$pname/default.nix"
	fi
}

# flox publish
_development_commands+=("publish")
_usage["publish"]="build and publish project to flox channel"
_usage_options["publish"]="[ --publish-to <gitURL> ] \\
                 [ --copy-to <nixURI> ] [ --copy-from <nixURI> ] \\
                 [ --render-path <dir> ] [ --key-file <file> ]"
function floxPublish() {
	trace "$@"
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	# Publish takes the same args as build, plus a few more.
	# Split out the publish args from the build args.
	local -a buildArgs=()
	local -a installables
	local attrPath
	local flakeRef
	local publishTo
	local copyTo
	local copyFrom
	local renderPath="catalog"
	local tmpdir=$(mktemp -d)
	local gitClone # separate from tmpdir out of abundance of caution
	local keyFile
	while test $# -gt 0; do
		case "$1" in
		--publish-to | -p) # takes one arg
			shift
			publishTo="$1"; shift
			;;
		--copy-to) # takes one arg
			shift
			copyTo="$1"; shift
			;;
		--copy-from) # takes one arg
			shift
			copyFrom="$1"; shift
			;;
		--render-path | -r) # takes one arg
			shift
			renderPath="$1"; shift
			;;
		--key-file | -k) # takes one arg
			shift
			keyFile="$1"; shift
			;;
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
		attrPath="$(selectAttrPath publish)"
		installables+=(".#$attrPath")
		flakeRef="."
	else
		# otherwise extract {attrPath,flakeRef} from first installable.
		attrPath=${installables[0]//*#/}
		flakeRef=${installables[0]//#*/}
	fi

	# If the user has provided the fully-qualified attrPath then remove
	# the "packages.$NIX_CONFIG_system." part as we'll add it back for
	# those places below where we need it.
	attrPath="${attrPath//packages.$NIX_CONFIG_system./}"

	# The --copy-to argument specifies the binary cache to which to
	# upload the package, but we also publish the URL that people use
	# to download the package in the catalog metadata. By default
	# this will be the same URL, but can be overridden with --copy-from.
	if [ -n "$copyTo" ]; then
		if [ -z "$copyFrom" ]; then
			copyFrom="$copyTo"
		fi
	fi

	# Start by making sure we can clone the thing we want to publish to.
	if [ -z "$publishTo" ]; then
		local origin=$($_git remote get-url origin)
		local dn=$($_dirname "$origin")
		publishTo=$($_gum input --value $dn/floxpkgs --prompt "Enter publish URL (enter '.' to publish to current directory): ")
	fi
	if [ "$publishTo" = "-" ]; then
		gitClone="-"
	elif [ "$publishTo" = "." ]; then
		gitClone="."
	else
		gitClone=$tmpdir
		ensureGHRepoExists "$publishTo" public "https://github.com/flox/floxpkgs-template.git"
		warn "Cloning $publishTo ..."
		$invoke_gh repo clone "$publishTo" "$gitClone"
	fi

	# Then build installables.
	warn "Building $attrPath ..."
	local outpaths=$(floxBuild --no-link --print-out-paths "${installables[@]}" "${buildArgs[@]}")

	# TODO Make content addressable (remove "false" below).
	local ca_out
	if false ca_out=$($invoke_nix store make-content-addressed $outpaths --json | $_jq '.rewrites[]'); then
		# Replace package outpaths with CA versions.
		warn "Replacing with content-addressable package: $ca_out"
		outpaths=$ca_out
	fi

	# Sign the package outpaths (optional). Sign by default?
	if [ -z "$keyFile" -a -f "$FLOX_CONFIG_HOME/secret-key" ]; then
		keyFile="$FLOX_CONFIG_HOME/secret-key"
	fi
	if [ -n "$keyFile" ]; then
		if [ -f "$keyFile" ]; then
			$invoke_nix store sign --key-file "$keyFile" $outpaths
		else
			error "could not read $keyFile: $!"
		fi
	fi

	### Next section cribbed from: github:flox/catalog-ingest#analyze

	# Gather local package outpath metadata.
	local metadata=$($invoke_nix flake metadata "$flakeRef" --json)

	# Gather remote package outpath metadata ... why?
	# XXX need to clean up $publishTo to be a nix-friendly URL .. punt for now
	local remoteMetadata=$metadata # $($invoke_nix flake metadata $publishTo --json)

	# Analyze package.
	# TODO: bundle lib/analysis.nix with flox CLI to avoid dependency on remote flake
	local analyzer="github:flox/catalog-ingest"
	# Nix eval command is noisy so filter out the expected output.
	local tmpstderr=$(mktemp)
	evalAndBuild=$($invoke_nix eval --json --override-input target "$flakeRef" \
		"$analyzer#analysis.eval.packages.$NIX_CONFIG_system.$attrPath" 2>$tmpstderr) || {
		$_grep --no-filename -v \
		  -e "^evaluating 'catalog\." \
		  -e "not writing modified lock file of flake" \
		  -e " Added input " \
		  -e " follows " \
		  -e "\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)" \
		  $tmpstderr 1>&2 || true
		$_rm -f $tmpstderr
		error "eval of $analyzer#analysis.eval.packages.$NIX_CONFIG_system.$attrPath failed - see above" < /dev/null
	}
	$_rm -f $tmpstderr

	# XXX TODO: refactor next section
	sourceInfo=$(echo "$metadata" | $_jq '{locked:.locked, original:.original}')
	remoteInfo=$(echo "$remoteMetadata" | $_jq '{remote:.original}')

	# Copy to binary cache (optional).
	if [ -n "$copyTo" ]; then
		local builtfilter="flake:flox#builtfilter"
		$invoke_nix copy --to $copyTo $outpaths
		# Enhance eval data with remote binary substituter.
		evalAndBuild=$(echo "$evalAndBuild" | \
			$invoke_nix run "$builtfilter" -- --substituter $copyFrom)
	fi

	# shellcheck disable=SC2086 # since jq variables don't need to be quoted
	evalAndBuildAndSource=$($_jq -n \
		--argjson evalAndBuild "$evalAndBuild" \
		--argjson sourceInfo "$sourceInfo" \
		--argjson remoteInfo "$remoteInfo" \
		--arg stability "$FLOX_STABILITY" '
		$evalAndBuild * {
			"source": ($sourceInfo*$remoteInfo),
			"eval": {
				"stability": $stability
			}
		}
	')

	### Next section cribbed from: github:flox/catalog-ingest#publish
	warn "publishing render to $renderPath ..."

	elementPath=$($_jq -n \
		--argjson evalAndBuildAndSource "$evalAndBuildAndSource" \
		--arg rootPath "$gitClone/$renderPath" '
		{
			"analysis": ($evalAndBuildAndSource),
			"attrPath": (
				"\($rootPath)/" + (
					$evalAndBuildAndSource.eval |
					[.system, .stability, .namespace, .version] |
					flatten |
					join("/")
				) + ".json"
			)
		}
	')
	echo "$elementPath"

	if [ "$publishTo" != "-" ]; then
		local epAttrPath=$($_jq -r .attrPath <<< "$elementPath")
		$_mkdir -p $($_dirname "$epAttrPath")
		echo "$elementPath" | $_jq -r '.analysis' > "$( echo "$elementPath" | $_jq -r '.attrPath' )"
		warn "flox publish completed"
		$_git -C "$gitClone" add $renderPath
	fi

	if [ "$publishTo" != "." -a "$publishTo" != "-" ]; then
		$_git -C "$gitClone" commit -m "$USER published ${installables[@]}"
		$_git -C "$gitClone" push
	fi

	# Hate rm -rf, but safer to delete tmpdir than risk deleting wrong git clone.
	$_rm -rf "$tmpdir"
}

# flox run
_development_commands+=("run")
_usage["run"]="run app from current project"
function floxRun() {
	trace "$@"
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a runArgs=()
	local -a installables=()
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
		# Options taking zero args.
		-*)
			runArgs+=("$1"); shift
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
		local attrPath="$(selectAttrPath run)"
		installables+=(".#$attrPath")
	elif [ ${#installables[@]} -gt 1 ]; then
		usage | error "more than one package argument provided"
	fi

	$invoke_nix "${_nixArgs[@]}" run "${installables[0]}" "${runArgs[@]}" --impure
}

# flox shell
_development_commands+=("shell")
_usage["shell"]="launch build shell for current project"
function floxShell() {
	trace "$@"
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"

	local -a shellArgs=()
	local -a installables=()
	while test $# -gt 0; do
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-run option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are `nix run` args.

		# Options taking two args.
		--command|-c|--arg|--argstr|--override-flake|--override-input)
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--keep|-k|--unset|-u|--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			shellArgs+=("$1"); shift
			shellArgs+=("$1"); shift
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
		local attrPath="$(selectAttrPath shell)"
		installables+=(".#$attrPath")
	elif [ ${#installables[@]} -gt 1 ]; then
		usage | error "more than one package argument provided"
	fi

	$invoke_nix "${_nixArgs[@]}" shell "${installables[@]}" "${shellArgs[@]}" --impure
}

## Environment commands

_environment_commands+=("cat")
_usage["cat"]="display declarative environment manifest"

_environment_commands+=("destroy")
_usage["destroy"]="remove all data pertaining to an environment"

#_environment_commands+=("diff-closures")
#_usage["diff-closures"]="show the closure difference between each version of an environment"

_environment_commands+=("edit")
_usage["edit"]="edit declarative environment manifest"

_environment_commands+=("generations")
_usage["generations"]="list environment generations with contents"

_environment_commands+=("history")
_usage["history"]="show all versions of an environment"

_environment_commands+=("install")
_usage["install"]="install a package into an environment"

_environment_commands+=("list")
_usage["list"]="list installed packages"
_usage_options["list"]="[--out-path]"

_environment_commands+=("pull")
_usage["pull"]="pull environment metadata from remote registry"
_usage_options["pull"]="[--force]"

_environment_commands+=("push")
_usage["push"]="send environment metadata to remote registry"
_usage_options["push"]="[--force]"

_environment_commands+=("rollback")
_usage["rollback"]="roll back to the previous generation of an environment"

_environment_commands+=("(rm|remove)")
_usage["(rm|remove)"]="remove packages from an environment"

_environment_commands+=("switch-generation")
_usage["switch-generation"]="switch to a specific generation of an environment"

#_environment_commands+=("sync")
#_usage["sync"]="synchronize environment metadata and links"

_environment_commands+=("upgrade")
_usage["upgrade"]="upgrade packages using their most recent flake"

_environment_commands+=("wipe-history")
_usage["wipe-history"]="delete non-current versions of an environment"

# vim:ts=4:noet:syntax=bash