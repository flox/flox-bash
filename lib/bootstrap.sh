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

function checkGhAuth {
	trace "$@"
	local hostname="$1"; shift
	# Repeat login attempts until we're successfully logged in.
	while ! $_gh auth status -h $hostname >/dev/null 2>&1; do
		initialGreeting
		warn "Invoking 'gh auth login -h $hostname'"
		$_gh auth login -h $hostname
		warn ""
	done
}

function getUsernameFromGhAuth {
	trace "$@"
	local hostname="$1"; shift
	# Get github username from gh data, if known.
	[ -s "$HOME/.config/gh/hosts.yml" ]
	$_dasel -f "$HOME/.config/gh/hosts.yml" "${hostname//./\\.}.user"
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

  # -------------------- >8 --------------------
  # XXX For design partners only: front-run the configuration
  #     process by defining certain fixed defaults.
  if true; then
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

  else
  # -------------------- >8 --------------------

	initialGreeting

	registry $floxUserMeta 1 get gitBaseURL > /dev/null || $_cat <<EOF 1>&2
Flox works by storing metadata using git. Let's start by
identifying your primary github server.

EOF

	# Guess gitBaseURL from configuration defaults.
	gitBaseURL=$(registry $floxUserMeta 1 getPromptSet \
		"base git URL (including auth and trailing delimiter): " \
		"$FLOX_CONF_floxpkgs_gitBaseURL" gitBaseURL)

	# Guess organization from configuration defaults.
	registry $floxUserMeta 1 get organization > /dev/null || $_cat <<EOF 1>&2

The packages available for installation with Flox are determined by
a single "root" floxpkgs repository from which additional floxpkgs
repositories can be included. By convention this repository is called
"floxpkgs" as found either in your personal organization or in the
primary organization for your company.

If none of this is familiar to you, or if you are only looking to install
public domain software then start by accepting the defaults below to use
the one provided by the "flox" organization. You can always change it later
with the \`flox config\` command.

EOF
	organization=$(registry $floxUserMeta 1 getPromptSet \
		"primary git organization: " \
		"$FLOX_CONF_floxpkgs_organization" organization)

	# Convention: flox expression repository called "floxpkgs" by default.
	defaultFlake=$(registry $floxUserMeta 1 getPromptSet \
		"default floxpkgs repository: " \
		"$(gitBaseURLToFlakeURL ${gitBaseURL} ${organization}/floxpkgs master)" \
		defaultFlake)

  fi # Remove when design partner phase is complete. XXX

	# Set the user's local git config user.{name,email} attributes.
	[ $_initial_bootstrap -eq 0 ] || checkGitConfig

	# Final step: derive GitHub username (aka FLOX_USER) from all that we know.
	username=$(registry $floxUserMeta 1 get username) || {
		# Set github username from gh data, if known.
		# Parse urlHostname from gitBaseURL.
		declare urlTransport urlHostname urlUsername
		eval $(parseURL "$gitBaseURL") || \
			error "cannot parse \"$gitBaseURL\""
		checkGhAuth $urlHostname
		if username=$(getUsernameFromGhAuth $urlHostname); then
			registry $floxUserMeta 1 set username "$username"
		else
			$_cat <<EOF 1>&2
Flox works by storing metadata using git. Let's start by
identifying your GitHub username.

EOF
			username=$(registry $floxUserMeta 1 getPromptSet \
				"GitHub username: " "" username)
		fi
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
	# Parse urlHostname from gitBaseURL.
	declare urlTransport urlHostname urlUsername
	eval $(parseURL "$gitBaseURL") || \
		error "cannot parse \"$gitBaseURL\""
	username=$(registry $floxUserMeta 1 get username || \
		getUsernameFromGhAuth $urlHostname || echo "$USER") # No better guess

fi

export FLOX_USER="$username"

# vim:ts=4:noet:syntax=bash
