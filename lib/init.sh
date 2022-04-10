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
		for i in "$@"
			do
				# Use `cat` to open files because it produces a clear and concise
				# message when file is not found or not readable. By comparison
				# the equivalent dasel output is to report "unknown parser".
				$_cat "$f" | $_dasel -p toml $i | while read _cline
				do
					local _xline=$(echo "$_cline" | tr -d ' \t')
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
			local _xline=$(echo "${_cline[@]}" | tr -d ' \t')
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

# Set base configuration before invoking nix.
export NIX_USER_CONF_FILES=$_etc/nix.conf

# Load nix configuration
eval $(nix_show_config)

# Load configuration from [potentially multiple] flox.toml config file(s).
eval $(read_flox_conf npfs floxpkgs)

# String to be prepended to flox flake uri.
floxFlakePrefix="@@FLOX_FLAKE_PREFIX@@"

# String to be prepended to flake attrPath (before stability).
floxFlakeAttrPathPrefix="legacyPackages.$NIX_CONFIG_system."

# NIX honors ${USER} over the euid, so make them match.
export USER=$($_id -un)
export HOME=$($_getent passwd ${USER} | $_cut -d: -f6)

# FLOX_USER can be completely different, e.g. the GitHub user,
# or can be the same as the UNIX $USER. Only flox knows!
export FLOX_USER=$USER # XXX FIXME $(flox whoami)

# Define and create flox metadata cache, data, and profiles directories.
export FLOX_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/flox"
export FLOX_METADATA="${FLOX_METADATA:-$FLOX_CACHE_HOME/profiles}"
export FLOX_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/flox"
export FLOX_PROFILES="${FLOX_PROFILES:-$FLOX_DATA_HOME/profiles}"
mkdir -p "$FLOX_CACHE_HOME" "$FLOX_METADATA" "$FLOX_DATA_HOME" "$FLOX_PROFILES"

# Prepend FLOX_DATA_HOME to XDG_DATA_DIRS. XXX Why? Probably delete ...
# XXX export XDG_DATA_DIRS="$FLOX_DATA_HOME"${XDG_DATA_DIRS:+':'}${XDG_DATA_DIRS}

# Home of the user-specific registry.json.
# XXX May need further consideration for Enterprise.
registry="$FLOX_CACHE_HOME/registry.json"

# Leave it to Bob to figure out that Nix 2.3 has the bug that it invokes
# `tar` without the `-f` flag and will therefore honor the `TAPE` variable
# over STDIN (to reproduce, try running `TAPE=none flox shell`).
# XXX Still needed??? Probably delete ...
if [ -n "$TAPE" ]; then
	unset TAPE
fi

# vim:ts=4:noet:
