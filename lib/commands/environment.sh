## Environment commands

_environment_commands+=("list")
_usage["list"]="list installed packages"
_usage_options["list"]="[--out-path] [--json]"
function floxList() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local environmentStartGen=$(environmentGen "$environment")
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"
	local -a invocation=("$@")

	local -a listArgs=()
	local -i displayOutPath=0
	local -i displayJSON=0
	while test $# -gt 0; do
		# 'flox list' args.
		case "$1" in
		--out-path) # takes zero args
			displayOutPath=1
			shift
			;;
		--json) # takes zero args
			displayJSON=1
			shift
			;;
		# Any other options are unrecognised.
		-*)
			usage | error "unknown option '$1'"
			;;
		# Assume all other options are installables.
		*)
			listArgs+=("$1"); shift
			;;
		esac
	done

	if [ $displayOutPath -gt 0 -a $displayJSON -gt 0 ]; then
		usage | error "only one of '--out-path' and '--json' options may be provided"
	fi

	if [ ${#listArgs[@]} -gt 0 ]; then
		# First argument to list can be generation number.
		if [[ ${listArgs[0]} =~ ^[0-9]*$ ]]; then
			if [ -e "$environment-${listArgs[0]}-link" ]; then
				environmentStartGen=${listArgs[0]}
				listArgs=(${listArgs[@]:1}) # aka shift
				environment="$environment-$environmentStartGen-link"
			fi
		fi
	fi
	if [ ${#listArgs[@]} -gt 0 ]; then
		usage | error "extra arguments provided '${listargs[*]}'"
	fi

	_environmentPath="$FLOX_ENVIRONMENTS/$environmentOwner/$environmentName"
	_environmentAlias="$environmentOwner/$environmentName"
	if [ -e "$_environmentPath" ]; then
		if [ "$($_realpath $_environmentPath)" = "$($_realpath $FLOX_ENVIRONMENTS/local/$environmentName)" ]; then
			_environmentAlias="$environmentName"
		fi
	fi

	if [ $verbose -eq 1 ]; then
		# Increase verbosity when invoking list command.
		let ++verbose
	fi

	# Before going any further, make sure environment actually exists.
	[ -d $environment ] || \
		error "environment $_environmentAlias does not exist" < /dev/null
	[ -f $environment/manifest.json ] || \
		error "environment manifest not found - run 'flox destroy -e $_environmentAlias' to clean up" </dev/null

	if [ $displayJSON -gt 0 ]; then
		manifest $environment/manifest.json listEnvironment --json | $_jq -r \
			--arg a "$_environmentAlias" \
			--arg s "$NIX_CONFIG_system" \
			--arg p "$FLOX_ENVIRONMENTS/$environmentOwner/$environmentName" \
			--arg c "$environmentStartGen" \
			'{"alias":$a,"system":$s,"path":$p,"currentGeneration":$c} * .'
	else
		$_cat <<EOF
$environmentOwner/$environmentName
    Alias     $_environmentAlias
    System    $NIX_CONFIG_system
    Path      $FLOX_ENVIRONMENTS/$environmentOwner/$environmentName
    Curr Gen  $environmentStartGen

Packages
EOF
		if [ $displayOutPath -gt 0 ]; then
			manifest $environment/manifest.json listEnvironment --out-path | $_sed 's/^/    /'
		else
			manifest $environment/manifest.json listEnvironment | $_sed 's/^/    /'
		fi
	fi
}

_environment_commands+=("install")
_usage["install"]="install a package into an environment"
function floxInstall() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local environment="$1"; shift
	local system="$1"; shift
	parseNixArgs "$@" && set -- "${_cmdArgs[@]}"
	local -a invocation=("$@")

	local -a installArgs=()
	local -a installables=()
	while test $# -gt 0; do
		# 'flox install' args.
		case "$1" in
		-A | --attr) # takes one arg
			# legacy nix-build option; convert to flakeref
			shift
			installables+=(".#$1"); shift
			;;

		# All remaining options are 'nix profile install' args.

		# Options taking two args.
		--arg|--argstr|--override-flake|--override-input)
			installArgs+=("$1"); shift
			installArgs+=("$1"); shift
			installArgs+=("$1"); shift
			;;
		# Options taking one arg.
		--priority|--eval-store|--include|-I|--inputs-from|--update-input|--expr|--file|-f)
			installArgs+=("$1"); shift
			installArgs+=("$1"); shift
			;;
		# Options taking zero args.
		--debugger|--impure|--commit-lock-file|--no-registries|--no-update-lock-file|--no-write-lock-file|--recreate-lock-file|--derivation)
			installArgs+=("$1"); shift
			;;
		# Any other options are unrecognised.
		-*)
			usage | error "unknown option '$1'"
			;;
		# Assume all other options are installables.
		*)
			installables+=("$1"); shift
			;;
		esac
	done

	local args="$@"

	# Create shared clone for importing new generation.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 1

	# Glean current and next generations from clone.
	local currentGen=$($_readlink $workDir/current || :)
	local nextGen=$($_readlink $workDir/next)

	# Step through installables deriving floxpkg equivalents.
	local -a pkgArgs=()
	for pkg in ${installables[@]}; do
		pkgArgs+=($(floxpkgArg "$pkg"))
	done
	# Step through installables deriving versioned floxpkg flakerefs.
	# A versioned flakeref is one that ends with "@1.2.3".
	local -a versionedPkgArgs=()
	for versionedPkg in ${installables[@]}; do
		versionedPkgArgs+=($(versionedFloxpkgArg "$versionedPkg"))
	done
	# Infer floxpkg name(s) from floxpkgs flakerefs.
	local -a pkgNames=()
	for pkgArg in ${pkgArgs[@]}; do
		case "$pkgArg" in
		flake:*)
			# Look up floxpkg name from flox flake prefix.
			pkgNames+=($(manifest $environment/manifest.json flakerefToFloxpkg "$pkgArg")) ||
				error "failed to look up floxpkg reference for flake \"$pkgArg\"" </dev/null
			;;
		*)
			pkgNames+=("$pkgArg")
			;;
		esac
	done

	local -i currentGenVersion
	if [ -z "$currentGen" ]; then
		# if we're creating a new environment, make it version 2
		currentGenVersion=2
	elif ! currentGenVersion=$(registry $workDir/metadata.json 1 get generations "$currentGen" version); then
		currentGenVersion=1
	fi

	case $currentGenVersion in
	1)
		# Now we want to construct the manifest.json entries for incorporating
		# the new installables into our environments, and the easiest way to
		# do that is to just install them to an ephemeral profile.
		local profileWorkDir=$(mkTempDir)
		if ! $invoke_nix profile install --profile "$profileWorkDir/x" --impure "${pkgArgs[@]}"; then
			# If that failed then repeat the build of each pkgArg individually
			# to report which one(s) failed.
			local -a failedPkgArgs=()
			local _stderr=$(mkTempFile)
			for pkgArg in ${pkgArgs[@]}; do
				if ! $invoke_nix build --no-link --impure "$pkgArg" >$_stderr 2>&1; then
					failedPkgArgs+=("$pkgArg")
					local pkgName
					case "$pkgArg" in
					flake:*\#)
						pkgName=($(manifest $environment/manifest.json flakerefToFloxpkg "$pkgArg"))
						;;
					*)
						pkgName="$pkgArg"
						;;
					esac
					if $_grep -q -e "error: path '/nix/store/.\+' does not exist and cannot be created" "$_stderr"; then
						warn "failed to find a binary download for '$pkgName'"
						warn "try building from source by installing as '$pkgName.fromSource':\n"
						warn "\t\$ flox install $pkgName.fromSource\n"
						warn "failed to find a binary download for '$pkgName'" < /dev/null
					else
						$_cat $_stderr 1>&2
					fi
				fi
			done
			$_rm -f $_stderr
			error "failed to install packages: ${failedPkgArgs[@]}" < /dev/null
		fi

		# Construct and render the new manifest.json in the metadata workDir.
		if [ -n "$currentGen" ]; then
			$_cat \
				$profileWorkDir/x/manifest.json \
				$workDir/$currentGen/manifest.json \
				| $_jq -s -f $_lib/merge-manifests.jq \
				> $workDir/$nextGen/manifest.json
		else
			# Expand the compact JSON rendered by default.
			$_jq . $profileWorkDir/x/manifest.json > $workDir/$nextGen/manifest.json
		fi
		$_git -C $workDir add $nextGen/manifest.json

		# Take this opportunity to compare the current and next generations before building.
		local envPackage
		if $_cmp --quiet $workDir/$currentGen/manifest.json $workDir/$nextGen/manifest.json; then
			envPackage=$($_jq -r '.generations[.currentGen].path' $workDir/metadata.json)
		else
			# Invoke 'nix profile build' to turn the manifest into a package.
			# Derive the environment package from the newly-rendered link.
			envPackage=$($invoke_nix profile build $workDir/$nextGen/manifest.json)
		fi

		# Generate declarative manifest.
		# First add the top half with packages section removed.
		if [ -n "$currentGen" ]; then
			# Include everything up to the snipline.
			$_awk "{if (/$snipline/) {exit} else {print}}" "$workDir/$currentGen/manifest.toml" > $workDir/$nextGen/manifest.toml
		else
			# Bootstrap with prototype manifest.
			$_cat > $workDir/$nextGen/manifest.toml <<EOF
$protoManifestToml
EOF
		fi
		# Append empty line if it doesn't already end with one.
		$_tail -1 $workDir/$nextGen/manifest.toml | $_grep --quiet '^$' || ( echo >> $workDir/$nextGen/manifest.toml )
		# Then append the updated packages list derived from manifest.json.
		echo "# $snipline" >> $workDir/$nextGen/manifest.toml
		manifest "$workDir/$nextGen/manifest.json" listEnvironmentTOML >> $workDir/$nextGen/manifest.toml
		$_git -C $workDir add $nextGen/manifest.toml
		;;
	2)
		# Construct and render the new manifest.json in the metadata workDir.
		if [ -n "$currentGen" ]; then
			# -T so we don't copy the parent directory
			$_cp -rT $workDir/$currentGen $workDir/$nextGen
		else
			# files in the Nix store are read-only
			$_cp --no-preserve=mode -rT $_lib/templateFloxEnv $workDir/$nextGen
		fi
		# otherwise Nix build won't be able to find any of the files
		$_git -C $workDir add $nextGen

		# Modify the declarative environment to add the new installables.
		for versionedPkgArg in ${versionedPkgArgs[@]}; do
			# That's it; invoke the editor to add the package.
			nixEditor $environment $workDir/$nextGen/pkgs/default/flox.nix install "$versionedPkgArg"
		done
		$_git -C $workDir add $nextGen/pkgs/default/flox.nix

		local envPackage
		if ! envPackage=$($invoke_nix build --impure --no-link --print-out-paths "$workDir/$nextGen#floxEnvs.$system.default"); then
			error "failed to install packages: ${pkgArgs[@]}" < /dev/null
		fi

		$_jq . --sort-keys $envPackage/catalog.json > $workDir/$nextGen/pkgs/default/catalog.json
		$_jq . --sort-keys $envPackage/manifest.json > $workDir/$nextGen/manifest.json
		$_git -C $workDir add $nextGen/pkgs/default/catalog.json
		$_git -C $workDir add $nextGen/manifest.json
		;;
	*)
		error "unknown version: $currentGenVersion" < /dev/null
		;;
	esac

	# That went well. Go ahead and commit the transaction.
	commitTransaction $environment $workDir $envPackage \
		"$USER installed ${pkgNames[*]}" \
		$currentGenVersion \
		"$me install ${invocation[*]}"
}

_environment_commands+=("(rm|remove)")
_usage["(rm|remove)"]="remove packages from an environment"
_usage_options["remove"]="[--force]"
function floxRemove() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local -a invocation=("$@")

	local -a removeArgs=()
	local -i force=0
	while test $# -gt 0; do
		# 'flox remove` args.
		case "$1" in
		-f | --force) # takes zero args
			force=1
			shift
			;;
		# Any other options are unrecognised.
		-*)
			usage | error "unknown option '$1'"
			;;
		# Assume all other options are packages to be removed.
		*)
			removeArgs+=("$1"); shift
			;;
		esac
	done

	local args="$@"

	# Create shared clone for modifying environment.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 0

	# Glean current and next generations from clone.
	local currentGen=$($_readlink $workDir/current || :)
	local nextGen=$($_readlink $workDir/next)

	# Create an ephemeral copy of the current generation to delete from.
	local profileWorkDir=$(mkTempDir)
	local envPackage=$($_jq -r '.generations[.currentGen].path' $workDir/metadata.json)
	$_ln -s $envPackage $profileWorkDir/x-$currentGen-link
	$_ln -s x-$currentGen-link $profileWorkDir/x

	local -i currentGenVersion
	if ! currentGenVersion=$(registry $workDir/metadata.json 1 get generations "$currentGen" version); then
		currentGenVersion=1
	fi

	# The remove and upgrade commands operate on flake references and
	# require the package to be present in the manifest. Take this
	# opportunity to look up the flake reference from the manifest
	# and then remove or upgrade them by position only.
	local -a pkgArgs=()
	local -a pkgPositionArgs=()
	for pkg in ${removeArgs[@]}; do
		pkgArg=$(floxpkgArg "$pkg")
		pkgArgs+=("$pkgArg")
		position=
		if [[ "$pkgArg" == *#* ]]; then
			position=$(manifest $profileWorkDir/x/manifest.json flakerefToPosition "$pkgArg") ||
				error "package \"$pkg\" not found in environment $environment" </dev/null
		elif [[ "$pkgArg" =~ ^[0-9]+$ ]]; then
			position="$pkgArg"
		else
			position=$(manifest $profileWorkDir/x/manifest.json storepathToPosition "$pkgArg") ||
				error "package \"$pkg\" not found in environment $environment" </dev/null
		fi
		pkgPositionArgs+=($position)
	done
	# Look up floxpkg name(s) from position.
	local -a pkgNames=()
	for position in ${pkgPositionArgs[@]}; do
		pkgNames+=($(manifest $profileWorkDir/x/manifest.json positionToFloxpkg "$position")) ||
			error "failed to look up package name for position \"$position\" in environment $environment" </dev/null
	done

	case $currentGenVersion in
	1)
		# Render a new environment with 'nix profile remove'.
		$invoke_nix profile remove --profile $profileWorkDir/x "${pkgPositionArgs[@]}"
		envPackage=$($_realpath $profileWorkDir/x/.)

		# That went well, update metadata accordingly.
		# Expand the compact JSON rendered by default.
		$_jq . $profileWorkDir/x/manifest.json > $workDir/$nextGen/manifest.json
		$_git -C $workDir add $nextGen/manifest.json

		# Generate declarative manifest.
		# First add the top half with packages section removed.
		if [ -n "$currentGen" ]; then
			# Include everything up to the snipline.
			$_awk "{if (/$snipline/) {exit} else {print}}" "$workDir/$currentGen/manifest.toml" > $workDir/$nextGen/manifest.toml
		else
			# Bootstrap with prototype manifest.
			$_cat > $workDir/$nextGen/manifest.toml <<EOF
$protoManifestToml
EOF
		fi
		# Append empty line if it doesn't already end with one.
		$_tail -1 $workDir/$nextGen/manifest.toml | $_grep --quiet '^$' || ( echo >> $workDir/$nextGen/manifest.toml )
		# Then append the updated packages list derived from manifest.json.
		echo "# $snipline" >> $workDir/$nextGen/manifest.toml
		manifest "$workDir/$nextGen/manifest.json" listEnvironmentTOML >> $workDir/$nextGen/manifest.toml
		$_git -C $workDir add $nextGen/manifest.toml
		;;
	2)
		# Create an ephemeral copy of the current generation to delete from.
		# -T so we don't copy the parent directory
		$_cp -rT $workDir/$currentGen $workDir/$nextGen
		# otherwise Nix build won't be able to find any of the files
		$_git -C $workDir add $nextGen

		# Step through floxtuples removing packages.
		for pkgName in ${pkgNames[@]}; do
			# That's it; invoke the editor to remove the package.
			nixEditor $environment $workDir/$nextGen/pkgs/default/flox.nix delete "$pkgName"
		done
		$_git -C $workDir add $nextGen/pkgs/default/flox.nix

		local envPackage
		if ! envPackage=$($invoke_nix build --impure --no-link --print-out-paths "$workDir/$nextGen#floxEnvs.$system.default"); then
			error "failed to remove ${pkgNames[@]}" </dev/null
		fi

		$_jq . --sort-keys $envPackage/catalog.json > $workDir/$nextGen/pkgs/default/catalog.json
		$_jq . --sort-keys $envPackage/manifest.json > $workDir/$nextGen/manifest.json
		$_git -C $workDir add $nextGen/pkgs/default/catalog.json
		$_git -C $workDir add $nextGen/manifest.json
		;;
	*)
		error "unknown version: $currentGenVersion" </dev/null
		;;
	esac

	# That went well. Go ahead and commit the transaction.
	commitTransaction $environment $workDir $envPackage \
		"$USER removed ${pkgNames[*]}" \
		$currentGenVersion \
		"$me remove ${invocation[*]}"
}

_environment_commands+=("upgrade")
_usage["upgrade"]="upgrade packages using their most recent flake"
_usage_options["upgrade"]="[--force]"
function floxUpgrade() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local environment="$1"; shift
	local system="$1"; shift
	local -a invocation=("$@")

	local -a upgradeArgs=()
	local -i force=0
	while test $# -gt 0; do
		# 'flox upgrade` args.
		case "$1" in
		-f | --force) # takes zero args
			force=1
			shift
			;;
		# Any other options are unrecognised.
		-*)
			usage | error "unknown option '$1'"
			;;
		# Assume all other options are packages to be upgraded.
		*)
			upgradeArgs+=("$1"); shift
			;;
		esac
	done

	local args="$@"

	# Create shared clone for modifying environment.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 0

	# Glean current and next generations from clone.
	local currentGen=$($_readlink $workDir/current)
	local nextGen=$($_readlink $workDir/next)

	# Create an ephemeral copy of the current generation to upgrade.
	local profileWorkDir=$(mkTempDir)
	local envPackage=$($_jq -r '.generations[.currentGen].path' $workDir/metadata.json)
	$_ln -s $envPackage $profileWorkDir/x-$currentGen-link
	$_ln -s x-$currentGen-link $profileWorkDir/x

	# The remove and upgrade commands operate on flake references and
	# require the package to be present in the manifest. Take this
	# opportunity to look up the flake reference from the manifest
	# and then remove or upgrade them by position only.
	local -a pkgArgs=()
	for pkg in ${upgradeArgs[@]}; do
		pkgArg=$(floxpkgArg "$pkg")
		position=
		if [[ "$pkgArg" == *#* ]]; then
			position=$(manifest $profileWorkDir/x/manifest.json flakerefToPosition "$pkgArg") ||
				error "package \"$pkg\" not found in environment $environment" </dev/null
		elif [[ "$pkgArg" =~ ^[0-9]+$ ]]; then
			position="$pkgArg"
		else
			position=$(manifest $profileWorkDir/x/manifest.json storepathToPosition "$pkgArg") ||
				error "package \"$pkg\" not found in environment $environment" </dev/null
		fi
		pkgArgs+=($position)
	done
	# Look up floxpkg name(s) from position.
	local -a pkgNames=()
	for position in ${pkgArgs[@]}; do
		pkgNames+=($(manifest $profileWorkDir/x/manifest.json positionToFloxpkg "$position")) ||
			error "failed to look up package name for position \"$position\" in environment $environment" </dev/null
	done
	# Look up catalog deletion paths from position.
	local -a pkgCatalogPaths=()
	for position in ${pkgArgs[@]}; do
		pkgCatalogPaths+=($(manifest $profileWorkDir/x/manifest.json positionToCatalogPath "$position")) ||
			error "failed to look up package catalog path for position \"$position\" in environment $environment" </dev/null
	done

	local -i currentGenVersion
	if ! currentGenVersion=$(registry $workDir/metadata.json 1 get generations "$currentGen" version); then
		currentGenVersion=1
	fi
	case $currentGenVersion in
	1)

		# Render a new environment with 'nix profile upgrade'.
		if [ ${#pkgArgs[@]} -gt 0 ]; then
			$invoke_nix profile upgrade --impure --profile $profileWorkDir/x "${pkgArgs[@]}"
		else
			$invoke_nix profile upgrade --impure --profile $profileWorkDir/x '.*'
		fi
		envPackage=$($_realpath $profileWorkDir/x/.)

		# That went well, update metadata accordingly.
		# Expand the compact JSON rendered by default.
		$_jq . $profileWorkDir/x/manifest.json > $workDir/$nextGen/manifest.json
		$_git -C $workDir add $nextGen/manifest.json

		# Generate declarative manifest.
		# First add the top half with packages section removed.
		if [ -n "$currentGen" ]; then
			# Include everything up to the snipline.
			$_awk "{if (/$snipline/) {exit} else {print}}" "$workDir/$currentGen/manifest.toml" > $workDir/$nextGen/manifest.toml
		else
			# Bootstrap with prototype manifest.
			$_cat > $workDir/$nextGen/manifest.toml <<EOF
$protoManifestToml
EOF
		fi
		# Append empty line if it doesn't already end with one.
		$_tail -1 $workDir/$nextGen/manifest.toml | $_grep --quiet '^$' || ( echo >> $workDir/$nextGen/manifest.toml )
		# Then append the updated packages list derived from manifest.json.
		echo "# $snipline" >> $workDir/$nextGen/manifest.toml
		manifest "$workDir/$nextGen/manifest.json" listEnvironmentTOML >> $workDir/$nextGen/manifest.toml
		$_git -C $workDir add $nextGen/manifest.toml
		;;
	2)
		# Create an ephemeral copy of the current generation to upgrade.
		# -T so we don't copy the parent directory
		$_cp -rT $workDir/$currentGen $workDir/$nextGen
		# otherwise Nix build won't be able to find any of the files
		$_git -C $workDir add $nextGen

		# To upgrade a package, we remove its entry from the ephemeral
		# catalog.json file. This essentially makes it unlocked, and Nix
		# will resolve that package reference to create a new lock, thus
		# upgrading it in the process.

		if [ ${#upgradeArgs[@]} == 0 ]; then
			# If upgrading all, simply remove all locks.
			rm $workDir/$nextGen/pkgs/default/catalog.json
		else
			# Delete all pkgCatalogPath references from catalog.json.
			local concatPkgCatalogPaths=$(IFS=","; echo "${pkgCatalogPaths[*]}")
			$invoke_jq "del($concatPkgCatalogPaths)" \
				$workDir/$currentGen/pkgs/default/catalog.json \
				> $workDir/$nextGen/pkgs/default/catalog.json
		fi

		local envPackage
		if ! envPackage=$($invoke_nix build --impure --no-link --print-out-paths "$workDir/$nextGen#floxEnvs.$system.default"); then
			# TODO: be more specific?
			error "failed to upgrade packages" < /dev/null
		fi

		$_jq . --sort-keys $envPackage/catalog.json > $workDir/$nextGen/pkgs/default/catalog.json
		$_jq . --sort-keys $envPackage/manifest.json > $workDir/$nextGen/manifest.json
		$_git -C $workDir add $nextGen/pkgs/default/catalog.json
		$_git -C $workDir add $nextGen/manifest.json
		;;
	*)
		error "unknown version: $currentGenVersion" </dev/null
		;;
	esac

	# That went well. Go ahead and commit the transaction.
	commitTransaction $environment $workDir $envPackage \
		"$USER upgraded ${pkgNames[*]}" \
		$currentGenVersion \
		"$me upgrade ${invocation[*]}"
}

_environment_commands+=("edit")
_usage["edit"]="edit declarative environment manifest"
function floxEdit() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local environment="$1"; shift
	local system="$1"; shift
	local -a invocation=("$@")

	# Create shared clone for importing new generation.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 1

	# Glean current and next generations from clone.
	local currentGen=$($_readlink $workDir/current || :)
	local nextGen=$($_readlink $workDir/next)

	local -i currentGenVersion
	if [ -z "$currentGen" ]; then
		# if we're creating a new environment, make it version 2
		currentGenVersion=2
	elif ! currentGenVersion=$(registry $workDir/metadata.json 1 get generations "$currentGen" version); then
		currentGenVersion=1
	fi
	case $currentGenVersion in
	1)
		# Copy manifest.toml from currentGen, or create prototype.
		if [ -n "$currentGen" ]; then
			$_cp $workDir/$currentGen/manifest.toml $workDir/$nextGen/manifest.toml
		else
			$_cat > $workDir/$nextGen/manifest.toml <<EOF
$protoManifestToml

EOF
			# XXX temporary: if 0.0.6 format manifest.json exists then append current package manifest.
			if [ -f "$workDir/manifest.json" ]; then
				manifest $workDir/manifest.json listEnvironmentTOML >> $workDir/$nextGen/manifest.toml
			fi # /XXX
		fi

		# Edit nextGen manifest.toml file.
		while true; do
			$editorCommand $workDir/$nextGen/manifest.toml

			# Verify valid TOML syntax
			[ -s $workDir/$nextGen/manifest.toml ] || (
				$_rm -f $workDir/$nextGen/manifest.toml
				error "editor returned empty manifest .. aborting" < /dev/null
			)
			if validateTOML $workDir/$nextGen/manifest.toml; then
				: confirmed valid TOML
				break
			else
				if [ -t 1 ]; then
					if boolPrompt "Try again?" "yes"; then
						: will try again
					else
						$_rm -f $workDir/$nextGen/manifest.toml
						error "editor returned invalid TOML .. aborting" < /dev/null
					fi
				else
					error "editor returned invalid TOML .. aborting" < /dev/null
				fi
			fi
		done

		# Check that something changed with the edit.
		if [ -n "$currentGen" ] && \
			$_cmp --quiet "$workDir/$currentGen/manifest.toml" "$workDir/$nextGen/manifest.toml"; then
			warn "No environment changes detected .. exiting"
			exit 0
		fi
		$_git -C $workDir add $nextGen/manifest.toml

		# Now render the environment package from the manifest.toml. This pulls
		# from the latest catalog by design and will upgrade everything.
		local envPackage=$(renderManifestTOML $workDir/$nextGen/manifest.toml)
		[ -n "$envPackage" ] || error "failed to render new environment" </dev/null
		;;
	2)
		# Copy manifest.toml from currentGen, or create prototype.
		if [ -n "$currentGen" ]; then
			# -T so we don't copy the parent directory
			$_cp -rT $workDir/$currentGen $workDir/$nextGen
		else
			# files in the Nix store are read-only
			$_cp --no-preserve=mode -rT $_lib/templateFloxEnv $workDir/$nextGen
		fi
		# otherwise Nix build won't be able to find any of the files
		$_git -C $workDir add $nextGen

		# Edit nextGen manifest.toml file.
		while true; do
			$editorCommand $workDir/$nextGen/pkgs/default/flox.nix

			[ -s $workDir/$nextGen/pkgs/default/flox.nix ] || (
				$_rm -rf $workDir/$nextGen
				error "editor returned empty configuration .. aborting" < /dev/null
			)

			# TODO: return early if no changes have been made instead of rebuilding?
			if envPackage=$($invoke_nix build --impure --no-link --print-out-paths "$workDir/$nextGen#floxEnvs.$system.default"); then
				: confirmed valid config
				break
			else
				if [ -t 1 ]; then
					if boolPrompt "Invalid configuration. Try again?" "yes"; then
						: will try again
					else
						$_rm -rf $workDir/$nextGen
						error "editor returned invalid configuration .. aborting" < /dev/null
					fi
				else
					error "editor returned invalid configuration .. aborting" < /dev/null
				fi
			fi
		done
		$_git -C $workDir add $nextGen/pkgs/default/flox.nix
		# copy the potentially updated catalog
		$_jq . --sort-keys $envPackage/catalog.json > $workDir/$nextGen/pkgs/default/catalog.json
		$_git -C $workDir add $workDir/$nextGen/pkgs/default/catalog.json
		;;
	*)
		error "unknown version: $currentGenVersion" </dev/null
		;;
	esac

	# Copy the manifest.json (lock file) from the freshly-rendered
	# package into the floxmeta repo.
	$_jq . --sort-keys $envPackage/manifest.json > $workDir/$nextGen/manifest.json
	$_git -C $workDir add $nextGen/manifest.json

	# That went well. Go ahead and commit the transaction.
	commitTransaction $environment $workDir $envPackage \
		"$USER edited declarative profile (generation $nextGen)" \
		$currentGenVersion \
		"$me edit ${invocation[*]}"
}

_environment_commands+=("import")
_usage["import"]="import declarative environment manifest as new generation"
function floxImport() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local environment="$1"; shift
	local system="$1"; shift
	local -a invocation=("$@")

	# Create shared clone for importing new generation.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 1

	# Glean next generation from clone.
	local nextGen=$($_readlink $workDir/next)

	# New tarball coming in on STDIN. Extract to tmpDir.
	local tmpDir=$(mkTempDir)
	$_tar -C $tmpDir -xf - || \
		usage | error "tar extraction failed - try using same flox version for import and export"

	# Inspect extracted data.
	[ -f $tmpDir/metadata.json ] || \
		usage | error "metadata.json not found - was tar created with flox export?"
	local currentGen=$(registry $tmpDir/metadata.json 1 get currentGen) || \
		usage | error "metadata.json does not contain currentGen"

	# Move latest generation from extracted data and insert as nextGen.
	$invoke_rmdir $workDir/$nextGen
	$invoke_mv $tmpDir/$currentGen $workDir/$nextGen
	$invoke_git -C $workDir add $nextGen

	# Detect version and act accordingly.
	local -i currentGenVersion
	if ! currentGenVersion=$(registry $tmpDir/metadata.json 1 get generations "$currentGen" version); then
		currentGenVersion=1
	fi

	local envPackage
	case $currentGenVersion in
	1)
		# Now render the environment package from the manifest.toml. This pulls
		# from the latest catalog by design and will upgrade everything.
		envPackage=$(renderManifestTOML $workDir/$nextGen/manifest.toml)
		[ -n "$envPackage" ] || error "failed to render new environment" </dev/null
		;;
	2)
		envPackage=$($invoke_nix build --impure --no-link --print-out-paths "$workDir/$nextGen#floxEnvs.$system.default")
		;;
	*)
		error "unknown version: $currentGenVersion" </dev/null
		;;
	esac

	# Copy the manifest.json (lock file) from the freshly-rendered
	# package into the floxmeta repo.
	$_cp $envPackage/manifest.json $workDir/$nextGen/manifest.json
	$_git -C $workDir add $nextGen/manifest.json

	# That went well. Go ahead and commit the transaction.
	commitTransaction $environment $workDir $envPackage \
		"$USER imported generation $nextGen" \
		$currentGenVersion \
		"$me import ${invocation[*]}"
}

_environment_commands+=("export")
_usage["export"]="export declarative environment manifest of current generation"
function floxExport() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local envName="$(basename $environment)"
	# This is the easy one; just export all the generations. It's up to the
	# import function to weed out and renumber the current generation.
	metaGit $environment $system archive --format=tar "$system.$envName"
}

_environment_commands+=("history")
_usage["history"]="show all versions of an environment"
_usage_options["history"]="[--oneline] [--json]"
function floxHistory() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"

	# Default to verbose log format (like git).
	logFormat="format:%cd %C(cyan)%B%Creset"

	# Step through args looking for (--oneline).
	local -i displayJSON=0
	while test $# -gt 0; do
		case "$1" in
		--oneline)
			# If --oneline then just include log subjects.
			logFormat="format:%cd %C(cyan)%s%Creset"
			shift
			;;
		--json) # takes zero args
			displayJSON=1
			logFormat='format:{"time":%ct, "msg":"%s"}'
			shift
			;;
		-*)
			usage | error "unknown option '$1'"
			;;
		*)
			usage | error "extra argument '$arg'"
			;;
		esac
	done
	if [ $displayJSON -gt 0 ]; then
		$invoke_git -C $environmentMetaDir log $branch --pretty="$logFormat" | $_jq -s .
	else
		$invoke_git -C $environmentMetaDir log $branch --pretty="$logFormat"
	fi
}

_environment_commands+=("generations")
_usage["generations"]="list environment generations with contents"
function floxGenerations() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift

	# Infer existence of generations from the registry (i.e. the database),
	# rather than the symlinks on disk so that we can have a history of all
	# generations long after they've been deleted for the purposes of GC.
	tmpfile=$(mkTempFile)
	metaGitShow $environment $system metadata.json > $tmpfile
	registry $tmpfile 1 listGenerations
}

_environment_commands+=("rollback")
_usage["rollback"]="roll back to the previous generation of an environment"
function floxRollback() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local environment="$1"; shift
	local system="$1"; shift
	local subcommand="$1"; shift
	local -a invocation=("$@")

	# Create shared clone for importing new generation.
	local workDir=$(mkTempDir)
	beginTransaction "$environment" "$system" "$workDir" 0

	# Glean current and next generations from clone.
	local currentGen=$($_readlink $workDir/current)

	# Look for target generation from command arguments.
	local -i targetGeneration=0
	for index in "${!invocation[@]}"; do
		case "${invocation[$index]}" in
		--to) targetGeneration="${invocation[$(($index + 1))]}"; break;;
		   *) ;;
		esac
	done

	# If not found in args then set target generation to previous.
	[ $targetGeneration -gt 0 ] || targetGeneration=$(( $currentGen - 1 ))

	# Quick sanity check.
	[ $targetGeneration -gt 0 ] || error "invalid generation '$targetGeneration'" < /dev/null

	# Bow out quickly if attempting to activate same environment.
	[ "$targetGeneration" != "$currentGen" ] || {
		warn "start and target generations are the same"
		exit 0
	}

	# Look up target generation in metadata, verify generation exists.
	$invoke_jq -e --arg gen $targetGeneration '.generations | has($gen)' $workDir/metadata.json >/dev/null || \
		error "could not find environment data for generation '$targetGeneration'" < /dev/null

	# Set the target generation in metadata.json by changing the "next" symlink
	# in the workDir. A bit hacky but a workaround to the limitations of bash.
	$_rm -f $workDir/next
	ln -s $targetGeneration $workDir/next

	# ... and commit.
	commitTransaction $environment $workDir UNUSED \
		"$USER switched to generation $targetGeneration" \
		1 \
		"$me $subcommand ${invocation[*]}"
}

_environment_commands+=("switch-generation")
_usage["switch-generation"]="switch to a specific generation of an environment"

_environment_commands+=("wipe-history")
_usage["wipe-history"]="delete non-current versions of an environment"

_environment_commands+=("destroy")
_usage["destroy"]="remove all data pertaining to an environment"
_usage_options["destroy"]="[--force] [--origin]"
function floxDestroy() {
	trace "$@"
	local environment="$1"; shift
	local system="$1"; shift
	local environmentDir=$($_dirname $environment)
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"
	local originArg=
	local -i force=0
	for i in "$@"; do
		if [ "$i" = "--origin" ]; then
			originArg="--origin"
		elif [[ "$i" = "-f" || "$i" = "--force" ]]; then
			force=1
		else
			usage | error "unknown argument: '$i'"
		fi
	done

	# Accumulate warning lines as we go.
	local -a warnings=("WARNING: you are about to delete the following:")

	# Look for symlinks to delete.
	local -a links=()
	for i in $environmentDir/$environmentName{,-*-link}; do
		if [ -L "$i" ]; then
			links+=("$i")
			warnings+=(" - $i")
		fi
	done

	# Look for directories to delete.
	local -a directories=()
	for i in $environmentDir/$environmentName; do
		if [ ! -L "$i" -a -d "$i" ]; then
			directories+=("$i")
			warnings+=(" - $i")
		fi
	done

	# Look for a local branch.
	local localBranch=
	if $invoke_git -C "$environmentMetaDir" show-ref --quiet refs/heads/"$branch" >/dev/null; then
		localBranch="$branch"
		warnings+=(" - the $branch branch in $environmentMetaDir")
	fi

	# Look for an origin branch.
	local origin=
	if $invoke_git -C "$environmentMetaDir" show-ref --quiet refs/remotes/origin/"$branch" >/dev/null; then
		local -i deleteOrigin=0
		if [ -n "$originArg" ]; then
			deleteOrigin=1
		else
			if [ -t 1 ] && $invoke_gum confirm --default="false" "delete '$branch' on origin as well?"; then
				deleteOrigin=1
				warn "hint: invoke with '--origin' flag to avoid this prompt in future"
			fi
		fi
		if [ $deleteOrigin -gt 0 ]; then
			# XXX: BUG no idea why, but this is reporting origin twice
			#      when first creating the repository; hack with sort.
			origin=$(getSetOrigin "$environment" "$system" | $_sort -u)
			warnings+=(" - the $branch branch in $origin")
		fi
	fi

	# If no warnings (other than the header warning) then nothing to destroy.
	if [ ${#warnings[@]} -le 1 ]; then
		warn "Nothing to delete for the '$environmentName' environment"
		return 0
	fi

	# Issue all the warnings and prompt for confirmation
	for i in "${warnings[@]}"; do
		warn "$i"
	done
	if [ $force -gt 0 ] || boolPrompt "Are you sure?" "no"; then
		# Start by changing to the (default) floxmain branch to ensure
		# we're not attempting to delete the current branch.
		if [ -n "$localBranch" ]; then
			if $invoke_git -C "$environmentMetaDir" checkout --quiet "$defaultBranch" 2>/dev/null; then
				# Ensure following commands always succeed so that subsequent
				# invocations can reach the --origin remote removal below.
				$invoke_git -C "$environmentMetaDir" branch -D "$branch" || true
			fi
		fi
		if [ -n "$origin" ]; then
			$invoke_git -C "$environmentMetaDir" branch -rd origin/"$branch" || true
			githubHelperGit -C "$environmentMetaDir" push origin --delete "$branch" || true
		fi
		$invoke_rm --verbose -f ${links[@]}
		if [ ${#directories[@]} -gt 0 ]; then
			$invoke_rmdir --verbose ${directories[@]}
		fi
	else
		warn "aborted"
		exit 1
	fi
}

_environment_commands+=("push")
_usage["push"]="send environment metadata to remote registry"
_usage_options["push"]="[--force]"

_environment_commands+=("pull")
_usage["pull"]="pull environment metadata from remote registry"
_usage_options["pull"]="[--force]"

#
# floxPushPull("(push|pull)",$environment,$system)
#
# This function creates an ephemeral clone for reconciling commits before
# pushing the result to either of the local (origin) or remote (upstream)
# repositories.
#
function floxPushPull() {
	trace "$@"
	betaRefreshNixCache # XXX: remove with open beta
	local action="$1"; shift
	local environment="$1"; shift
	local system="$1"; shift
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	local branch="${system}.${environmentName}"
	local forceArg=
	for i in "$@"; do
		if [ "$i" = "--force" ]; then
			forceArg="--force"
		else
			usage | error "unknown argument: '$i'"
		fi
	done

	[ $action = "push" -o $action = "pull" ] ||
		error "pushpullMetadata(): first arg must be (push|pull)" < /dev/null

	# First verify that the clone has an origin defined.
	# XXX: BUG no idea why, but this is reporting origin twice
	#      when first creating the repository; hack with sort.
	local origin=$(getSetOrigin "$environment" "$system" | $_sort -u)

	# Perform a fetch to get remote data into sync.
	githubHelperGit -C "$environmentMetaDir" fetch origin

	# Create an ephemeral clone with which to perform the synchronization.
	local tmpDir=$(mkTempDir)
	$invoke_git clone --quiet --shared "$environmentMetaDir" $tmpDir

	# Add the upstream remote to the ephemeral clone.
	$invoke_git -C $tmpDir remote add upstream $origin
	githubHelperGit -C $tmpDir fetch --quiet --all

	# Check out the relevant branch. Can be complicated in the event
	# that this is the first pull of a brand-new branch.
	if $invoke_git -C "$tmpDir" show-ref --quiet refs/heads/"$branch"; then
		$invoke_git -C "$tmpDir" checkout "$branch"
	elif $invoke_git -C "$tmpDir" show-ref --quiet refs/remotes/origin/"$branch"; then
		$invoke_git -C "$tmpDir" checkout --quiet --track origin/"$branch"
	elif $invoke_git -C "$tmpDir" show-ref --quiet refs/remotes/upstream/"$branch"; then
		$invoke_git -C "$tmpDir" checkout --quiet --track upstream/"$branch"
	else
		$invoke_git -C "$tmpDir" checkout --orphan "$branch"
		$invoke_git -C "$tmpDir" ls-files | $_xargs --no-run-if-empty $_git -C "$tmpDir" rm --quiet -f
		# A commit is needed in order to make the branch visible.
		$invoke_git -C "$tmpDir" commit --quiet --allow-empty \
			-m "$USER created profile"
		$invoke_git -C "$tmpDir" push --quiet --set-upstream origin "$branch"
	fi

	# Then push or pull.
	if [ "$action" = "push" ]; then
		githubHelperGit -C $tmpDir push $forceArg upstream origin/"$branch":refs/heads/"$branch" ||
			error "repeat command with '--force' to overwrite" < /dev/null
		# Push succeeded, ensure that $environmentMetaDir has remote ref for this branch.
		githubHelperGit -C "$environmentMetaDir" fetch --quiet origin
	elif [ "$action" = "pull" ]; then
		# Slightly different here; we first attempt to rebase and do
		# a hard reset if invoked with --force.
		if $invoke_git -C "$tmpDir" show-ref --quiet refs/remotes/upstream/"$branch"; then
			if [ -z "$forceArg" ]; then
				$invoke_git -C $tmpDir rebase --quiet upstream/"$branch" ||
					error "repeat command with '--force' to overwrite" < /dev/null
			else
				$invoke_git -C $tmpDir reset --quiet --hard upstream/"$branch"
			fi
			# Set receive.denyCurrentBranch=updateInstead before pushing
			# to update both the bare repository and the checked out branch.
			$invoke_git -C "$environmentMetaDir" config receive.denyCurrentBranch updateInstead
			$invoke_git -C $tmpDir push $forceArg origin
			syncEnvironment "$environment" "$system"
		else
			error "branch '$branch' does not exist on $origin upstream" < /dev/null
		fi
	fi
}

_environment_commands+=("git")
_usage["git"]="access to the git CLI for floxmeta repository"
function floxGit() {
	trace "$@"
	local environment="$1"; shift
	local -a invocation=("$@")
	local environmentDir=$($_dirname $environment)
	local environmentName=$($_basename $environment)
	local environmentOwner=$($_basename $($_dirname $environment))
	local environmentMetaDir="$FLOX_META/$environmentOwner"
	githubHelperGit -C $environmentMetaDir ${args[@]}
}

# vim:ts=4:noet:syntax=bash
