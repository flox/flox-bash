## Development commands

# Splitting out "flox publish" into its own module because it is
# quite a bit more complex than other commands and deserves to
# be split out into a collection of related functions.

#
# doEducatePublish()
#
# A very important function, gives users an overview of 'flox publish'
# and sets a flag to not present the same information more than once.
declare -i educatePublishCalled=0
function doEducatePublish() {
	educatePublishCalled=1
	[ $educatePublish -eq 0 ] || return 0
	$_cat <<EOF 1>&2

As this seems to be your first time publishing a package here's a
brief overview of the process.

Publishing a package requires the following:

  * the build repository from which to "flox build"
  * a channel repository for storing built package metadata
  * [optional] a binary cache location for storing copies
    of already-built packages
  * [optional] a binary cache location from which to
    download already-built packages for faster installation

Once it has been published to a channel repository, you can
search for and use your package with the following:

  * subscribe to the channel: flox subscribe <channel> <URL>
  * search for a package: flox search -c <channel> <package>
  * install a package: flox install <channel>.<package>

See the flox(1) man page for more information.

EOF
	educatePublish=1
	registry $floxUserMeta 1 setNumber educatePublish 1
}

#
# Create project-specific flox registry file.
# XXX TODO move to development command bootstrap logic?
#
declare gitCloneRegistry
function initProjectRegistry() {
	local gitCloneToplevel="$($_git rev-parse --show-toplevel || :)"
	local floxProjectMetaDir=".flox"
	if [ -n "$gitCloneToplevel" ]; then
		local gitCloneFloxDir="$gitCloneToplevel/$floxProjectMetaDir"
		[ -d $gitCloneFloxDir ] || $invoke_mkdir -p "$gitCloneFloxDir"
		gitCloneRegistry="$gitCloneFloxDir/metadata.json"
		if [ $interactive -eq 1 ]; then
			[ -f $gitCloneRegistry ] || info "creating $gitCloneRegistry"
			if ! $_grep -q "^/$floxProjectMetaDir$" "$gitCloneToplevel/.gitignore" && \
				$invoke_gum confirm "add /$floxProjectMetaDir to toplevel .gitignore file?"; then
				echo "/$floxProjectMetaDir" >> "$gitCloneToplevel/.gitignore"
				$invoke_git -C "$gitCloneToplevel" add .gitignore
				warn "clone modified - please commit and re-invoke"
				exit 1
			fi
		fi
	fi
}

_development_commands+=("publish")
_usage["publish"]="build and publish project to flox channel"
_usage_options["publish"]="[--build-repo <URL>] [--channel-repo <URL>] \\
                 [--upload-to <URL>] [--download-from <URL>] \\
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
	local channelRepository
	local uploadTo
	local downloadFrom
	local buildRepository
	local renderPath="catalog"
	local tmpdir=$(mkTempDir)
	local gitClone # separate from tmpdir out of abundance of caution
	local keyFile
	while test $# -gt 0; do
		case "$1" in
		# Required
		--build-repo | -b | --upstream-url) # XXX TODO: remove mention of upstream
			[ "$1" != "--upstream-url" ] || \
				warn "Warning: '$1' is deprecated - please use '--build-repo' instead"
			shift
			buildRepository="$1"; shift
			;;
		--channel-repo | -c | --publish-to | -p) # XXX TODO: remove mention of publish
			[ "$1" != "--publish-to" -a "$1" != "-p" ] || \
				warn "Warning: '$1' is deprecated - please use '--channel-repo' instead"
			shift
			channelRepository="$1"; shift
			;;
		# Optional
		--upload-to | --copy-to) # takes one arg
			[ "$1" != "--copy-to" ] || \
				warn "Warning: '$1' is deprecated - please use '--upload-to' instead"
			shift
			uploadTo="$1"; shift
			;;
		--download-from | --copy-from) # takes one arg
			[ "$1" != "--copy-from" ] || \
				warn "Warning: '$1' is deprecated - please use '--download-from' instead"
			shift
			downloadFrom="$1"; shift
			;;
		# Expert
		--render-path | -r) # takes one arg
			shift
			renderPath="$1"; shift
			;;
		--key-file | -k) # takes one arg
			shift
			keyFile="$1"; shift
			;;
		# Select installable
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
	elif [ ${#installables[@]} -eq 1 ]; then
		# otherwise extract {attrPath,flakeRef} from provided installable.
		attrPath=${installables[0]//*#/}
		flakeRef=${installables[0]//#*/}
	else
		usage | error "multiple arguments provided to 'flox publish' command"
	fi

	# If the user has provided the fully-qualified attrPath then remove
	# the "packages.$NIX_CONFIG_system." part as we'll add it back for
	# those places below where we need it.
	attrPath="${attrPath//packages.$NIX_CONFIG_system./}"

	# Publishing a package requires answers to the following:
	#
	# 1) the "source" repository from which to "flox build"
	# 2) a "channel" repository for storing built package metadata
	# 3) (optional) a list of "binary cache" URLs for uploading signed
	#    copies of already-built packages
	# 4) (optional) a list of "binary cache" URLs from which to download
	#    already-built packages
	#
	# Walk the user through the process of collecting each of
	# these in turn.

	# Start by figuring out if we're in a git clone, and if so
	# make note of its origin.
	local remote=$($_git rev-parse --abbrev-ref --symbolic-full-name @{u} | $_cut -d / -f 1 || echo "origin")
	local origin=$($_git remote get-url $remote || :)

	# If we are in a git repository then create the project registry.
	[ -z "$origin" ] || initProjectRegistry

	# The --build-repo argument specifies the repository of the flake
	# used to build the package. When invoked from a git clone this
	# defaults to its origin.
	if [ -z "$buildRepository" ]; then
		doEducatePublish
		# Load previous answer (if applicable).
		if ! buildRepository=$(registry "$gitCloneRegistry" 1 get buildRepository); then
			# put this after querying the url from the user?
			case "$origin" in
				git@* )
					buildRepository="git+ssh://${origin/[:]//}"
					;;
				ssh://* | http://* | https://* )
					buildRepository="git+$origin"
					;;
				*)
					buildRepository="$origin"
					;;
			esac
		fi
		while true; do
			buildRepository=$(promptInput \
				"Enter git URL (required)" \
				"build repository:" \
				"$buildRepository")
			if checkGitRepoExists "$buildRepository"; then
				[ -z "$buildRepository" ] || break
			fi
			warn "please enter a valid URL from which to 'flox build' a package"
		done
	fi

	# The --channel-repo argument specifies the repository for storing
	# built package metadata. When invoked from a git clone this defaults
	# to a "floxpkgs" repository in the same organization as its origin.
	if [ -z "$channelRepository" ]; then
		doEducatePublish
		# Load previous answer (if applicable).
		if ! channelRepository=$(registry "$gitCloneRegistry" 1 get channelRepository); then
			case "$origin" in
				*/* )
					channelRepository=$($_dirname "$origin")/floxpkgs
					;;
			esac
		fi
		while true; do
			channelRepository=$(promptInput \
				"Enter git URL (required)" \
				"channel repository:" \
				"$channelRepository")
			if ensureGHRepoExists "$channelRepository" public "https://github.com/flox/floxpkgs-template.git"; then
				[ -z "$channelRepository" ] || break
			fi
			warn "please enter a valid URL with which to 'flox subscribe'"
		done
	fi

	# Prompt for location(s) TO and FROM which we can (optionally) copy the
	# built package store path(s). By default these will refer to the same
	# URL, but can be overridden with --download-from.
	if [ -z "$uploadTo" ]; then
		doEducatePublish
		# Load previous answer (if applicable).
		uploadTo=$(registry "$gitCloneRegistry" 1 get uploadTo || :)
		# XXX TODO: find a way to remember previous binary cache locations
		uploadTo=$(promptInput \
			"Enter binary cache URL (leave blank to skip upload)" \
			"binary cache for upload:" \
			"$uploadTo")
	fi
	if [ -z "$downloadFrom" ]; then
		# Load previous answer (if applicable).
		downloadFrom=$(registry "$gitCloneRegistry" 1 get downloadFrom || :)
		if [ -z "$downloadFrom" ]; then
			# Note - the following line is not a mistake; if $downloadFrom is not
			# defined then we should use $uploadTo as the default suggested value.
			downloadFrom=$uploadTo
		fi
		downloadFrom=$(promptInput \
			"Enter binary cache URL (optional)" \
			"binary cache for download:" \
			"$downloadFrom")
	fi

	# Construct string encapsulating entire command invocation.
	local entirePublishCommand=$(printf \
		"flox publish --build-repo %s --channel-repo %s" \
		"$buildRepository" "$channelRepository")
	[ -z "$uploadTo" ] || entirePublishCommand=$(printf "%s --upload-to %s" "$entirePublishCommand" "$uploadTo")
	[ -z "$downloadFrom" ] || entirePublishCommand=$(printf "%s --download-from %s" "$entirePublishCommand" "$downloadFrom")

	# Only hint and save responses in interactive mode.
	if [ $interactive -eq 1 ]; then
		# Input parsing over, print informational hint in the event that we
		# had to ask any questions.
		if [ $educatePublishCalled -eq 1 ]; then
			warn "HINT: avoid having to answer these questions next time with:"
			echo '{{ Color "'$LIGHTPEACH256'" "'$DARKBLUE256'" "$ '$entirePublishCommand'" }}' | \
				$_gum format -t template 1>&2
		fi

		# Save answers to the project registry so they can serve as
		# defaults for next time.
		if [ -n "$gitCloneRegistry" ]; then
			registry "$gitCloneRegistry" 1 set buildRepository "$buildRepository"
			registry "$gitCloneRegistry" 1 set channelRepository "$channelRepository"
			registry "$gitCloneRegistry" 1 set uploadTo "$uploadTo"
			registry "$gitCloneRegistry" 1 set downloadFrom "$downloadFrom"
		fi
	else
		echo '{{ Color "'$LIGHTPEACH256'" "'$DARKBLUE256'" "'$entirePublishCommand'" }}' | \
			$_gum format -t template 1>&2
	fi

	# Start by making sure we can clone the channel repository to
	# which we want to publish.
	if [ "$channelRepository" = "-" ]; then
		gitClone="-"
	elif [ -d "$channelRepository" ]; then
		gitClone="$channelRepository"
	else
		gitClone=$tmpdir
		warn "Cloning $channelRepository ..."
		$invoke_gh repo clone "$channelRepository" "$gitClone"
	fi

	# Then build installables.
	warn "Building $attrPath ..."
	local outpaths=$(floxBuild "${_nixArgs[@]}" --no-link --print-out-paths "${installables[@]}" "${buildArgs[@]}")

	# TODO Make content addressable (remove "false" below).
	local ca_out
	if false ca_out=$($invoke_nix "${_nixArgs[@]}" store make-content-addressed $outpaths --json | $_jq '.rewrites[]'); then
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
			$invoke_nix "${_nixArgs[@]}" store sign --key-file "$keyFile" $outpaths
		else
			error "could not read $keyFile: $!" < /dev/null
		fi
	fi

	### Next section cribbed from: github:flox/catalog-ingest#analyze

	# Gather local package outpath metadata.
	local metadata=$($invoke_nix "${_nixArgs[@]}" flake metadata "$flakeRef" --json)

	# Fail if local repo dirty
	local gitRevisionLocal
	if ! gitRevisionLocal="$($_jq -n -r -e --argjson md "$metadata" '$md.revision')"; then
		error "'$flakeRef' has uncommitted changes or is not a git repository" < /dev/null
	fi

	# Gather remote package outpath metadata ... why?
	# XXX need to clean up $channelRepository to be a nix-friendly URL .. punt for now
	local remoteMetadata
	if ! remoteMetadata=$($invoke_nix "${_nixArgs[@]}" flake metadata "$buildRepository?rev=$gitRevisionLocal" --json); then
		error "The local commit '$gitRevisionLocal'  was not found in build repository '$buildRepository'" < /dev/null
	fi

	# Analyze package.
	# TODO: bundle lib/analysis.nix with flox CLI to avoid dependency on remote flake
	local analyzer="github:flox/catalog-ingest"
	# Nix eval command is noisy so filter out the expected output.
	local tmpstderr=$(mkTempFile)
	evalAndBuild=$($invoke_nix "${_nixArgs[@]}" eval --json \
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
	if [ -n "$uploadTo" ]; then
		local builtfilter="flake:flox#builtfilter"
		$invoke_nix "${_nixArgs[@]}" copy --to $uploadTo $outpaths
		# Enhance eval data with remote binary substituter.
		evalAndBuild=$(echo "$evalAndBuild" | \
			$invoke_nix "${_nixArgs[@]}" run "$builtfilter" -- --substituter $downloadFrom)
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

	if [ "$channelRepository" != "-" ]; then
		local epAttrPath=$($_jq -r .attrPath <<< "$elementPath")
		$_mkdir -p $($_dirname "$epAttrPath")
		echo "$elementPath" | $_jq -r '.analysis' > "$( echo "$elementPath" | $_jq -r '.attrPath' )"
		warn "flox publish completed"
		$_git -C "$gitClone" add $renderPath
	else
		$_jq -n -r --argjson ep "$elementPath" '$ep.analysis'
	fi

	if [ ! -d "$channelRepository" -a "$channelRepository" != "-" ]; then
		$_git -C "$gitClone" commit -m "$USER published ${installables[@]}"
		$_git -C "$gitClone" push
	fi

	# Hate rm -rf, but safer to delete tmpdir than risk deleting wrong git clone.
	$_rm -rf "$tmpdir"
}
