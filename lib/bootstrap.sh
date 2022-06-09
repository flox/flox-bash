if [ -t 1 ]; then

	# Bootstrap the personal metadata to track the user's default github
	# baseURL, organization, username, "base" flake, etc.
	# This is an MVP stream-of-consciousness thing at the moment; can
	# definitely be improved upon.

	[ -f $floxUserMeta ] || $_cat <<EOF 1>&2

I see you are new to flox! We just need to ask a few questions
to get you started ...

EOF

	registry $floxUserMeta 1 get gitBaseURL > /dev/null || $_cat <<EOF 1>&2
Flox works by storing metadata using git. Let's start by
identifying your primary git server and username.

EOF

	# Guess gitBaseURL from configuration defaults.
	gitBaseURL=$(registry $floxUserMeta 1 getPromptSet \
		"base git URL (including auth and trailing delimiter): " \
		"$FLOX_CONF_floxpkgs_gitBaseURL" gitBaseURL)

	# Guess git username from UNIX username (likely to be incorrect).
	username=$(registry $floxUserMeta 1 getPromptSet \
		"git username: " "$USER" username)
	export FLOX_USER="$username"

	# Guess organization from configuration defaults.
	registry $floxUserMeta 1 get organization > /dev/null || $_cat <<EOF 1>&2

The packages available for installation with Flox are determined
by a single "base" repository from which additional package sets
can be included. By convention this repository is always called
"floxpkgs" as found either in your personal organization or in
the primary organization for your company.

If you are only looking to install public domain software or
otherwise unsure then start by using the one provided by the
"flox" organization - you can always change it later with the
\`flox defaults\` command.

EOF
	organization=$(registry $floxUserMeta 1 getPromptSet \
		"primary git organization: " \
		"$FLOX_CONF_floxpkgs_organization" organization)

	# Convention: Flox Nix expression repository for organization
	# always called "floxpkgs".
	registry $floxUserMeta 1 get defaultFlake > /dev/null || \
		registry $floxUserMeta 1 set defaultFlake "${gitBaseURL}${organization}/floxpkgs?=master"
	defaultFlake=$(registry $floxUserMeta 1 get defaultFlake)

else

	gitBaseURL=$(registry $floxUserMeta 1 get gitBaseURL || echo "$FLOX_CONF_floxpkgs_gitBaseURL")
	username=$(registry $floxUserMeta 1 get username || echo "$USER")
	export FLOX_USER="$username"
	organization=$(registry $floxUserMeta 1 get organization || echo "$FLOX_CONF_floxpkgs_organization")
	defaultFlake=$(registry $floxUserMeta 1 get defaultFlake || echo "${gitBaseURL}${organization}/floxpkgs?=master")

fi

# vim:ts=4:noet:syntax=bash
