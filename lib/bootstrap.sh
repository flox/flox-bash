# Boolean to track whether this is the initial bootstrap.
declare -i _initial_bootstrap=0

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
		info "It appears you have not set up your local git user configuration."
		if boolPrompt "Would you like to set that up now?" "yes"; then
			[ $_found_name -eq 1 ] || \
				gitConfigSet "user.name" "Full name: " \
					"$($_getent passwd $USER | $_cut -d: -f5)"
			[ $_found_email -eq 1 ] || \
				gitConfigSet "user.email" "Email address: " \
					"${USER}@domain.name"
			info ""
			info "Great! Here are your new git config user settings:"
			$_git config --get-regexp 'user\..*' 1>&2
			info ""
			info "You can change them at any time with the following:"
		else
			info "OK, you can suppress further warnings by setting these explicitly:"
		fi
		$_cat <<EOF 1>&2

    git config --global [user.name](http://user.name/) "Your Name"
    git config --global user.email [you@example.com](mailto:you@example.com)

EOF
	fi
}

# Bootstrap the personal metadata to track the user's default github
# baseURL, organization, username, "base" flake, etc.
# This is an MVP stream-of-consciousness thing at the moment; can
# definitely be improved upon.
function bootstrap() {
	[ -f $floxUserMeta ] || _initial_bootstrap=1
	registry $floxUserMeta 1 get floxClientUUID 2>&1 >/dev/null || \
		registry $floxUserMeta 1 set floxClientUUID $($_uuid)
	floxClientUUID=$(registry $floxUserMeta 1 get floxClientUUID)
	if [ -t 1 ]; then
		# Interactive mode
		gitBaseURL=$(registry $floxUserMeta 1 get gitBaseURL) || {
			gitBaseURL="$FLOX_CONF_floxpkgs_gitBaseURL"
			registry $floxUserMeta 1 set gitBaseURL "$gitBaseURL"
		}
		organization=$(registry $floxUserMeta 1 get organization) || {
			organization="$FLOX_CONF_floxpkgs_organization"
			registry $floxUserMeta 1 set organization "$organization"
		}
		_previous=$(registry $floxUserMeta 1 get defaultFlake || true)
		if [ -n "$_previous" ]; then
			defaultFlake="$_previous"
		else
			defaultFlake=$(gitBaseURLToFlakeURL ${gitBaseURL} ${organization}/floxpkgs master)
		fi
		if [ $getPromptSetConfirm -gt 0 ]; then
			defaultFlake=$(registry $floxUserMeta 1 getPromptSet \
				"Default floxpkgs repository: " "$defaultFlake" defaultFlake)
		else
			registry $floxUserMeta 1 set defaultFlake "$defaultFlake"
		fi
		if [ "$_previous" != "$defaultFlake" ]; then
			validateFlakeURL $defaultFlake || {
				registry $floxUserMeta 1 delete defaultFlake
				error "could not verify defaultFlake URL: \"$defaultFlake\"" < /dev/null
			}
		fi
		defaultSubstituter=$(registry $floxUserMeta 1 get defaultSubstituter) || {
		  defaultSubstituter="$FLOX_CONF_floxpkgs_defaultSubstituter"
		  registry $floxUserMeta 1 set defaultSubstituter "$defaultSubstituter"
		}

if false; then # XXX
		# Set the user's local git config user.{name,email} attributes.
		[ $_initial_bootstrap -eq 0 ] || checkGitConfig
fi # XXX

		# Collect the user's express consent to submit telemetry data.
		floxMetricsConsent=$(registry $floxUserMeta 1 get floxMetricsConsent) || {
			info ""
			info "flox collects basic usage metrics in order to improve the user experience,"
			info "including a record of the subcommand invoked along with a unique token."
			info "It does not collect any personal information."
			info ""
			if boolPrompt "Do you consent to the collection of basic usage metrics?" "yes"; then
				registry $floxUserMeta 1 setNumber floxMetricsConsent 1
				info ""
				info "Thank you for helping to improving flox!"
				info ""
			else
				registry $floxUserMeta 1 setNumber floxMetricsConsent 0
				info ""
				info "Understood. If you change your mind you can change your election"
				info "at any time with the following command: flox config --reset"
				info ""
			fi
			floxMetricsConsent=$(registry $floxUserMeta 1 get floxMetricsConsent)
		}

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
		defaultSubstituter=$(registry $floxUserMeta 1 get defaultSubstituter || \
			echo "$FLOX_CONF_floxpkgs_defaultSubstituter")
		floxMetricsConsent=$(registry $floxUserMeta 1 get floxMetricsConsent) || \
			floxMetricsConsent=0

	fi
}

bootstrap

# vim:ts=4:noet:syntax=bash
