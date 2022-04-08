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
# vim:ts=4:noet:
