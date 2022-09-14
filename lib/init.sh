# Set prefix (again) to assist with debugging independently of flox.sh.
_prefix="@@PREFIX@@"
_prefix=${_prefix:-.}
_lib=$_prefix/lib
_etc=$_prefix/etc

# Use extended glob functionality throughout.
shopt -s extglob

# Pull in utility functions early.
. $_lib/utils.sh

# Import library functions.
. $_lib/metadata.sh

#
# Parse flox configuration files in TOML format. Order of processing:
#
# 1. package defaults from $PREFIX/etc/flox.toml
# 2. installation defaults from /etc/flox.toml
# 3. user customizations from $HOME/.floxrc
#
# Latter definitions override/redefine the former ones.
#
read_flox_conf()
{
	local _cline
	# Consider other/better TOML parsers. Calling dasel multiple times below
	# because it only accepts one query per invocation.  In benchmarks it claims
	# to be 3x faster than jq so this is better than converting to json in a
	# single invocation and then selecting multiple values using jq.
	for f in "$_prefix/etc/flox.toml" "/etc/flox.toml" "$HOME/.floxrc"
	do
		if [ -f "$f" ]; then
		for i in $@
			do
				# Use `cat` to open files because it produces a clear and concise
				# message when file is not found or not readable. By comparison
				# the equivalent dasel output is to report "unknown parser".
				#
				# Use jq to look for the requested attribute because dasel always
				# returns nonzero when it is not found.
				#
				# Use the `jq` `tojson()` function to escape quotes contained in
				# values.
				$_cat "$f" | \
				$_dasel -p toml -w json | \
				$_jq -r --arg var $i '
					select(has($var)) | .[$var] | to_entries | map(
						"FLOX_CONF_\($var)_\(.key)=\(.value | tojson)"
					) | join("\n")
				'
			done
		fi
	done
}

nix_show_config()
{
	local -a _cline
	$_nix show-config | while read -a _cline
	do
		case "${_cline[0]}" in
		# List below the parameters you want to use within the script.
		system)
			local _xline=$(echo "${_cline[@]}" | $_tr -d ' \t')
			echo NIX_CONFIG_"$_xline"
			;;
		*)
			;;
		esac
	done
}

#
# Global variables
#

# NIX honors ${USER} over the euid, so make them match.
if _real_user=$($_id -un 2>/dev/null); then
	if [ "$_real_user" != "$USER" ]; then
		export USER="$_real_user"
		if _real_home=$($_getent passwd "$USER" 2>/dev/null | $_cut -d: -f6); then
			export HOME="$_real_home"
		else
			warn "cannot identify home directory for user '$USER'"
		fi
	fi
else
	# XXX Corporate LDAP environments rely on finding nss_ldap in
	# XXX ld.so.cache *or* by configuring nscd to perform the LDAP
	# XXX lookups instead. The Nix version of glibc has been modified
	# XXX to disable ld.so.cache, so if nscd isn't configured to do
	# XXX this then ldap access to the passwd map will not work.
	# XXX Bottom line - don't abort if we cannot find a passwd
	# XXX entry for the euid, but do warn because it's very
	# XXX likely to cause problems at some point.
	warn "cannot determine effective uid - continuing as user '$USER'"
fi
if [ -n "$HOME" ]; then
	[ -w "$HOME" ] || \
		error "\$HOME directory '$HOME' not writable ... aborting" < /dev/null
fi
if [ -n "$XDG_CACHE_HOME" ]; then
	[ -w "$XDG_CACHE_HOME" ] || \
		error "\$XDG_CACHE_HOME directory '$XDG_CACHE_HOME' not writable ... aborting" < /dev/null
fi
if [ -n "$XDG_DATA_HOME" ]; then
	[ -w "$XDG_DATA_HOME" ] || \
		error "\$XDG_DATA_HOME directory '$XDG_DATA_HOME' not writable ... aborting" < /dev/null
fi
if [ -n "$XDG_CONFIG_HOME" ]; then
	[ -w "$XDG_CONFIG_HOME" ] || \
		error "\$XDG_CONFIG_HOME directory '$XDG_CONFIG_HOME' not writable ... aborting" < /dev/null
fi
export PWD=$($_pwd)

# Define and create flox metadata cache, data, and profiles directories.
export FLOX_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/flox"
export FLOX_META="$FLOX_CACHE_HOME/profilemeta"
export FLOX_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/flox"
export FLOX_ENVIRONMENTS="$FLOX_DATA_HOME/environments"
export FLOX_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/flox"
$_mkdir -p "$FLOX_CACHE_HOME" "$FLOX_META" "$FLOX_DATA_HOME" "$FLOX_ENVIRONMENTS" "$FLOX_CONFIG_HOME"

# XXX Temporary: following the rename of profile -> environment:
# * rename $FLOX_DATA_HOME/profiles -> $FLOX_DATA_HOME/environments
# * rename $FLOX_CACHE_HOME/profilemeta -> $FLOX_CACHE_HOME/meta
# * leave symbolic links in place redirecting old to new
# Remove after 20221031
if [ -d "$FLOX_DATA_HOME/profiles" ]; then
	if [ ! -L "$FLOX_DATA_HOME/profiles" ]; then
		$_mv "$FLOX_DATA_HOME/profiles" "$FLOX_ENVIRONMENTS"
		$_ln -s environments "$FLOX_DATA_HOME/profiles"
	fi
fi
if [ -d "$FLOX_CACHE_HOME/profilemeta" ]; then
	if [ ! -L "$FLOX_CACHE_HOME/profilemeta" ]; then
		$_mv "$FLOX_CACHE_HOME/profilemeta" "$FLOX_CACHE_HOME/meta"
		$_ln -s meta "$FLOX_CACHE_HOME/profilemeta"
	fi
fi
# XXX

# Prepend FLOX_DATA_HOME to XDG_DATA_DIRS. XXX Why? Probably delete ...
# XXX export XDG_DATA_DIRS="$FLOX_DATA_HOME"${XDG_DATA_DIRS:+':'}${XDG_DATA_DIRS}

# Default profile "owner" directory, i.e. ~/.local/share/flox/environments/local/default/bin
profileOwner="local" # as in "/usr/local"
if [ -L "$FLOX_ENVIRONMENTS/$profileOwner" ]; then
	profileOwner=$(readlink "$FLOX_ENVIRONMENTS/$profileOwner")
fi

# Define place to store user-specific metadata separate
# from profile metadata.
floxUserMeta="$FLOX_CONFIG_HOME/floxUserMeta.json"

# Define location for user-specific flox flake registry.
floxFlakeRegistry="$FLOX_CONFIG_HOME/floxFlakeRegistry.json"

# Manage user-specific nix.conf for use with flox only.
# XXX May need further consideration for Enterprise.
nixConf="$FLOX_CONFIG_HOME/nix.conf"
tmpNixConf=$($_mktemp --tmpdir=$FLOX_CONFIG_HOME)
$_cat > $tmpNixConf <<EOF
# Automatically generated - do not edit.
experimental-features = nix-command flakes
netrc-file = $HOME/.netrc
flake-registry = $floxFlakeRegistry
accept-flake-config = true
warn-dirty = false
EOF

# Ensure file is secure before appending access token(s).
$_chmod 600 $tmpNixConf

# If found, extract and append github token from gh file.
declare -a accessTokens=()
declare -A accessTokensMap # to detect/eliminate duplicates
#XXX this is candidate for removal unless this is still in use
if [ -f "$HOME/.config/gh/hosts.yml" ]; then
	for i in $($_dasel -r yml -w json < "$HOME/.config/gh/hosts.yml" | $_jq -r '(
			to_entries |
			map(select(.value.oauth_token != null)) |
			map("\(.key)=\(.value.oauth_token)") |
			join(" ")
		)'
	); do
		accessTokens+=($i)
		accessTokensMap[$i]=1
	done
fi

if [ -f "$HOME/.config/flox/tokens" ]; then
	if [ "$($_stat -c %a $HOME/.config/flox/tokens)" != "600" ]; then
		warn "fixing mode of $HOME/.config/flox/tokens"
		$_chmod 600 "$HOME/.config/flox/tokens"
	fi
	for i in $($_sed 's/#.*//' "$HOME/.config/flox/tokens"); do
		# XXX add more syntax validation in golang rewrite
		if [ -z "${accessTokensMap[$i]}" ]; then
			accessTokens+=($i)
			accessTokensMap[$i]=1
		fi
	done
fi

# Add static "floxbeta" developer token for closed beta. (expires 10/31/22)
# XXX Remove after closed beta.
betaToken="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"
# XXX a temporary fix for pre-alpha demonstration to force access to
# semi-private repositories.
echo "access-tokens = github.com=${betaToken}" >> $tmpNixConf

if $_cmp --quiet $tmpNixConf $nixConf; then
	$_rm $tmpNixConf
else
	warn "Updating $nixConf"
	$_mv -f $tmpNixConf $nixConf
fi
export NIX_REMOTE=${NIX_REMOTE:-daemon}
export NIX_USER_CONF_FILES="$nixConf"
export SSL_CERT_FILE="${SSL_CERT_FILE:-@@NIXPKGS_CACERT_BUNDLE_CRT@@}"
export NIX_SSL_CERT_FILE="${NIX_SSL_CERT_FILE:-$SSL_CERT_FILE}"

# Similarly configure git config by way of $GIT_CONFIG_SYSTEM. Note that
# we do it by way of this env variable because Nix doesn't provide a
# passthru mechanism for passing options to git invocations. (?)
gitConfig="$FLOX_CONFIG_HOME/gitconfig"

tmpGitConfig=$($_mktemp --tmpdir=$FLOX_CONFIG_HOME)
$_chmod 600 $tmpGitConfig
$_cat > $tmpGitConfig <<EOF
# Automatically generated - do not edit.

# For access to the closed beta.
[url "https://floxbeta:$betaToken@github.com/flox/capacitor"]
	insteadOf = "https://github.com/flox/capacitor"
	insteadOf = "ssh://git@github.com/flox/capacitor"
	insteadOf = "git@github.com:flox/capacitor"

[url "https://floxbeta:$betaToken@github.com/flox/nixpkgs-flox"]
	insteadOf = "https://github.com/flox/nixpkgs-flox"
	insteadOf = "ssh://git@github.com/flox/nixpkgs-flox"
	insteadOf = "git@github.com:flox/nixpkgs-flox"

[url "https://floxbeta:$betaToken@github.com/flox/nixpkgs-catalog"]
	insteadOf = "https://github.com/flox/nixpkgs-catalog"
	insteadOf = "ssh://git@github.com/flox/nixpkgs-catalog"
	insteadOf = "git@github.com:flox/nixpkgs-catalog"

[url "https://floxbeta:$betaToken@github.com/flox/catalog-ingest"]
	insteadOf = "https://github.com/flox/catalog-ingest"
	insteadOf = "ssh://git@github.com/flox/catalog-ingest"
	insteadOf = "git@github.com:flox/catalog-ingest"

[url "https://floxbeta:$betaToken@github.com/flox/flox-extras"]
	insteadOf = "https://github.com/flox/flox-extras"
	insteadOf = "ssh://git@github.com/flox/flox-extras"
	insteadOf = "git@github.com:flox/flox-extras"

# N.B. not dropping the trailing slash here because that
# would rewrite other flox/flox* repositories.
[url "https://floxbeta:$betaToken@github.com/flox/flox/"]
	insteadOf = "https://github.com/flox/flox/"
	insteadOf = "ssh://git@github.com/flox/flox/"
	insteadOf = "git@github.com:flox/flox/"

# Do not rewrite flox/floxpkgs-internal
[url "ssh://git@github.com/flox/floxpkgs-internal"]
	insteadOf = "ssh://git@github.com/flox/floxpkgs-internal"
[url "git@github.com:flox/floxpkgs-internal"]
	insteadOf = "git@github.com:flox/floxpkgs-internal"

# Do rewrite flox/floxpkgs
[url "https://github.com/flox/floxpkgs"]
	insteadOf = "ssh://git@github.com/flox/floxpkgs"
	insteadOf = "git@github.com:flox/floxpkgs"

EOF
# XXX Remove after closed beta.

# Honor existing GIT_CONFIG_SYSTEM variable and/or default /etc/gitconfig.
if [ -n "$GIT_CONFIG_SYSTEM" ]; then
	if [ -n "$FLOX_ORIGINAL_GIT_CONFIG_SYSTEM" ]; then
		# Reset GIT_CONFIG_SYSTEM to reflect the original value
		# observed before starting flox subshell (see below).
		GIT_CONFIG_SYSTEM="$FLOX_ORIGINAL_GIT_CONFIG_SYSTEM"
	fi
else
	if [ -e "/etc/gitconfig" ]; then
		GIT_CONFIG_SYSTEM="/etc/gitconfig"
	fi
fi

# If system gitconfig exists then include it, but check first to make sure
# user hasn't requested that we include our own gitconfig file(!).
if [ -e "$GIT_CONFIG_SYSTEM" -a "$GIT_CONFIG_SYSTEM" != "$gitConfig" ]; then
	# Save first/original observed variable to disambiguate our use
	# of GIT_CONFIG_SYSTEM in subshells.
	export FLOX_ORIGINAL_GIT_CONFIG_SYSTEM="$GIT_CONFIG_SYSTEM"
	$_cat >> $tmpGitConfig <<EOF
[include]
	path = $GIT_CONFIG_SYSTEM

EOF
fi

# Compare generated gitconfig to cached version.
if $_cmp --quiet $tmpGitConfig $gitConfig; then
	$_rm $tmpGitConfig
else
	warn "Updating $gitConfig"
	$_mv -f $tmpGitConfig $gitConfig
fi

# Override system gitconfig.
export GIT_CONFIG_SYSTEM="$gitConfig"

# Load nix configuration (must happen after setting NIX_USER_CONF_FILES)
eval $(nix_show_config)

# Load configuration from [potentially multiple] flox.toml config file(s).
eval $(read_flox_conf npfs floxpkgs)

# Bootstrap user-specific configuration.
. $_lib/bootstrap.sh

# Populate user-specific flake registry.
# FIXME: support multiple flakes.
# Note: avoids problems to let nix create the temporary file.
tmpFloxFlakeRegistry=$($_mktemp --dry-run --tmpdir=$FLOX_CONFIG_HOME)
minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry floxpkgs $defaultFlake
minverbosity=2 $invoke_nix registry add --registry $tmpFloxFlakeRegistry nixpkgs github:flox/nixpkgs/${FLOX_STABILITY:-stable}
if $_cmp --quiet $tmpFloxFlakeRegistry $floxFlakeRegistry; then
	$_rm $tmpFloxFlakeRegistry
else
	$_mv -f $tmpFloxFlakeRegistry $floxFlakeRegistry
fi

# String to be prepended to flox flake uri.
floxpkgsUri="flake:floxpkgs"

# String to be prepended to flake attrPath (before channel).
catalogSearchAttrPathPrefix="catalog.$NIX_CONFIG_system"
catalogEvalAttrPathPrefix="evalCatalog.$NIX_CONFIG_system"

# Leave it to Bob to figure out that Nix 2.3 has the bug that it invokes
# `tar` without the `-f` flag and will therefore honor the `TAPE` variable
# over STDIN (to reproduce, try running `TAPE=none flox shell`).
# XXX Still needed??? Probably delete ...
if [ -n "$TAPE" ]; then
	unset TAPE
fi

# Timestamp
now=$($_date +%s)

# vim:ts=4:noet:syntax=bash
