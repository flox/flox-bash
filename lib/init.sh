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
				$_cat "$f" | $_dasel -p toml $i | while read _cline
				do
					local _xline=$(echo "$_cline" | $_tr -d ' \t')
					local _i=${i/-/_}
					echo FLOX_CONF_"$_i"_"$_xline"
				done
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
export USER=$($_id -un)
export HOME=$($_getent passwd ${USER} | $_cut -d: -f6)

# Define and create flox metadata cache, data, and profiles directories.
export FLOX_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/flox"
export FLOX_PROFILEMETA="$FLOX_CACHE_HOME/profilemeta"
export FLOX_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/flox"
export FLOX_PROFILES="$FLOX_DATA_HOME/profiles"
export FLOX_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/flox"
$_mkdir -p "$FLOX_CACHE_HOME" "$FLOX_PROFILEMETA" "$FLOX_DATA_HOME" "$FLOX_PROFILES" "$FLOX_CONFIG_HOME"

# Prepend FLOX_DATA_HOME to XDG_DATA_DIRS. XXX Why? Probably delete ...
# XXX export XDG_DATA_DIRS="$FLOX_DATA_HOME"${XDG_DATA_DIRS:+':'}${XDG_DATA_DIRS}

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
if $_cmp --quiet $tmpNixConf $nixConf; then
	$_rm $tmpNixConf
else
	echo "Updating $nixConf" 1>&2
	$_mv -f $tmpNixConf $nixConf
fi
export NIX_REMOTE=daemon
export NIX_USER_CONF_FILES="$nixConf"
export NIX_SSL_CERT_FILE="@@SSL_CERT_FILE@@"

# Load nix configuration (must happen after setting NIX_USER_CONF_FILES)
eval $(nix_show_config)

# Load configuration from [potentially multiple] flox.toml config file(s).
eval $(read_flox_conf npfs floxpkgs)

# Bootstrap user-specific configuration.
. $_lib/bootstrap.sh

# Populate user-specific flake registry.
# FIXME: support multiple flakes.
tmpFloxFlakeRegistry=$($_mktemp --tmpdir=$FLOX_CONFIG_HOME)
$_jq . > $tmpFloxFlakeRegistry <<EOF
{
  "flakes": [{$(flakeURLToRegistryJSON $defaultFlake)}],
  "version": 2
}
EOF
if $_cmp --quiet $tmpFloxFlakeRegistry $floxFlakeRegistry; then
	$_rm $tmpFloxFlakeRegistry
else
	echo "Updating $floxFlakeRegistry" 1>&2
	$_mv -f $tmpFloxFlakeRegistry $floxFlakeRegistry
fi

# String to be prepended to flox flake uri.
floxpkgsUri="flake:floxpkgs"

# String to be prepended to flake attrPath (before channel).
catalogAttrPathPrefix="legacyPackages.$NIX_CONFIG_system.catalog"

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
