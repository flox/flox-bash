## Development commands

# flox init
_development_commands+=("init")
_usage["init"]="initialize flox expressions for current project"
function floxInit() {
	trace "$@"
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
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" build --impure "${buildArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY
}

# flox develop
_development_commands+=("develop")
_usage["develop"]="launch development shell for current project"
function floxDevelop() {
	trace "$@"
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
		local attrPath="$(selectAttrPath develop)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" develop --impure "${developArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# flox publish
_development_commands+=("publish")
_usage["publish"]="build and publish project to flox channel"
_usage_options["publish"]="[--publish-to <gitURL>] [--upstream-url <gitURL>] \\
                 [--copy-to <nixURI>] [--copy-from <nixURI>] \\
                 [--render-path <dir>] [--key-file <file>]"
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
	local upstreamUrl
	local renderPath="catalog"
	local tmpdir=$(mkTempDir)
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
		--upstream-url)
			shift
			upstreamUrl="$1"; shift
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

	# The --upstream-url argument specifies the upstream url of the flake.
	# By default this is the origin of the repo being published.
	if [ -z "$upstreamUrl" ]; then
		# TODO: improve user visibility, validate url with proper error
		# messages
		local origin=$($_git remote get-url origin)

		# put this after querying the url from the user?
		local nixGitRef=
		case "$origin" in
			git@* )
				nixGitRef="git+ssh://${origin/[:]//}"
				;;
			ssh://* | http://* | https://* )
				nixGitRef="git+$origin"
				;;
			*)
				nixGitRef="$origin"
				;;
		esac

		upstreamUrl=$($_gum input --value "$nixGitRef" --prompt "Enter upstream URL for source backed builds: (enter '.' to effectively disable source builds on remote machines): ")
	fi

	# Start by making sure we can clone the thing we want to publish to.
	if [ -z "$publishTo" ]; then
		local origin=$($_git remote get-url origin)
		local dn=$($_dirname "$origin")
		publishTo=$($_gum input --value $dn/floxpkgs --prompt "Enter publish URL (enter '.' to publish to current directory): ")
	fi
	if [ "$publishTo" = "-" ]; then
		gitClone="-"
	elif [ -d "$publishTo" ]; then
		gitClone="$publishTo"
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

	# Fail if local repo dirty
	if ! gitRevisionLocal="$($_jq -n -r -e --argjson md "$metadata" '$md.revision')"; then
		error "The flake '$flakeRef' is dirty or not a git repository" < /dev/null
	fi


	# Gather remote package outpath metadata ... why?
	# XXX need to clean up $publishTo to be a nix-friendly URL .. punt for now
	local remoteMetadata
	if ! remoteMetadata=$($invoke_nix flake metadata "$upstreamUrl?rev=$gitRevisionLocal" --json); then
		error "The local commit '$gitRevisionLocal'  was not found in upstream repository '$upstreamUrl'" < /dev/null
	fi

	# Analyze package.
	# TODO: bundle lib/analysis.nix with flox CLI to avoid dependency on remote flake
	local analyzer="github:flox/catalog-ingest"
	# Nix eval command is noisy so filter out the expected output.
	local tmpstderr=$(mkTempFile)
	evalAndBuild=$($invoke_nix eval --json \
		--override-input target "$flakeRef" \
		--override-input target/floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY \
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
		--argjson remoteMetadata "$remoteMetadata" \
		--arg stability "$FLOX_STABILITY" '
		$evalAndBuild * {
			"element": {"url": "\($remoteMetadata.resolvedUrl)"},
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

	if [ "$publishTo" != "-" ]; then
		local epAttrPath=$($_jq -r .attrPath <<< "$elementPath")
		$_mkdir -p $($_dirname "$epAttrPath")
		echo "$elementPath" | $_jq -r '.analysis' > "$( echo "$elementPath" | $_jq -r '.attrPath' )"
		warn "flox publish completed"
		$_git -C "$gitClone" add $renderPath
	else
		$_jq -n -r --argjson ep "$elementPath" '$ep.analysis'
	fi

	if [ ! -d "$publishTo" -a "$publishTo" != "-" ]; then
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
		local attrPath="$(selectAttrPath run)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" run --impure "${runArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# flox shell
_development_commands+=("shell")
_usage["shell"]="run a shell in which the current project is available"
function floxShell() {
	trace "$@"
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
		local attrPath="$(selectAttrPath shell)"
		installables=(".#$attrPath")
	fi

	$invoke_nix "${_nixArgs[@]}" shell --impure "${shellArgs[@]}" "${installables[@]}" --override-input floxpkgs/nixpkgs/nixpkgs flake:nixpkgs-$FLOX_STABILITY "${remainingArgs[@]}"
}

# vim:ts=4:noet:syntax=bash
