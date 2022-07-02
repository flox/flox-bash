# Boolean to track whether this is the initial bootstrap.
declare -i _initial_bootstrap=0
[ -f $floxUserMeta ] || _initial_bootstrap=1

declare -i _greeted=0
function initialGreeting {
	trace "$@"
	[ $_initial_bootstrap -eq 1 ] || return 0
	[ $_greeted -eq 0 ] || return 0
	$_cat <<EOF 1>&2

I see you are new to flox! We just need to set up a few things
to get you started ...

EOF
	_greeted=1
}

function checkGitConfig {
	trace "$@"
	# Check to see if they have valid git config for user.{name,email}.
	declare -i _found_name=0
	declare -i _found_email=0
	eval $(
		$_git config --name-only --get-regexp 'user\..*' | while read i; do
			if [ "$i" = "user.name" ]; then
				echo _found_name=1
			elif [ "$i" = "user.email" ]; then
				echo _found_email=1
			fi
		done
	)
	if [ $_found_name -eq 0 -o $_found_email -eq 0 ]; then
		initialGreeting
		warn "It appears you have not set up your local git user configuration."
		if boolPrompt "Would you like to set that up now?" "yes"; then
			[ $_found_name -eq 1 ] || \
				gitConfigSet "user.name" "Full name: " \
					"$($_getent passwd $USER | $_cut -d: -f5)"
			[ $_found_email -eq 1 ] || \
				gitConfigSet "user.email" "Email address: " \
					"${USER}@domain.name"
			warn ""
			warn "Great! Here are your new git config user settings:"
			$_git config --get-regexp 'user\..*' 1>&2
			warn ""
			warn "You can change them at any time with the following:"
		else
			warn "OK, you can suppress further warnings by setting these explicitly:"
		fi
		$_cat <<EOF 1>&2

    git config --global [user.name](http://user.name/) "Your Name"
    git config --global user.email [you@example.com](mailto:you@example.com)

EOF
	fi
}

#
# bootstrap main()
#
if [ -t 1 ]; then

	# Bootstrap the personal metadata to track the user's default github
	# baseURL, organization, username, "base" flake, etc.
	# This is an MVP stream-of-consciousness thing at the moment; can
	# definitely be improved upon.

	gitBaseURL=$(registry $floxUserMeta 1 get gitBaseURL) || {
		gitBaseURL="$FLOX_CONF_floxpkgs_gitBaseURL"
		registry $floxUserMeta 1 set gitBaseURL "$gitBaseURL"
	}
	organization=$(registry $floxUserMeta 1 get organization) || {
		organization="$FLOX_CONF_floxpkgs_organization"
		registry $floxUserMeta 1 set organization "$organization"
	}
	defaultFlake=$(registry $floxUserMeta 1 get defaultFlake) || {
		defaultFlake=$(gitBaseURLToFlakeURL ${gitBaseURL} ${organization}/floxpkgs master)
		validateFlakeURL $defaultFlake || \
			error "could not verify defaultFlake URL: \"$defaultFlake\"" < /dev/null
		registry $floxUserMeta 1 set defaultFlake "$defaultFlake"
	}

if false; then # XXX
	# Set the user's local git config user.{name,email} attributes.
	[ $_initial_bootstrap -eq 0 ] || checkGitConfig
fi # XXX

else

	#
	# Non-interactive mode. Use all defaults if not found in registry.
	#
	gitBaseURL=$(registry $floxUserMeta 1 get gitBaseURL || \
		echo "$FLOX_CONF_floxpkgs_gitBaseURL")
	organization=$(registry $floxUserMeta 1 get organization || \
		echo "$FLOX_CONF_floxpkgs_organization")
	defaultFlake=$(registry $floxUserMeta 1 get defaultFlake || \
		gitBaseURLToFlakeURL ${gitBaseURL} ${organization}/floxpkgs master)

fi

# vim:ts=4:noet:syntax=bash
