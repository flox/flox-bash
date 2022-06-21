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
		"$(gitBaseURLToFlakeURL ${gitBaseURL})${organization}/floxpkgs?ref=master" \
		defaultFlake)

else

	gitBaseURL=$(registry $floxUserMeta 1 get gitBaseURL || echo "$FLOX_CONF_floxpkgs_gitBaseURL")
	username=$(registry $floxUserMeta 1 get username || echo "$USER")
	export FLOX_USER="$username"
	organization=$(registry $floxUserMeta 1 get organization || echo "$FLOX_CONF_floxpkgs_organization")
	defaultFlake=$(registry $floxUserMeta 1 get defaultFlake || echo "$(gitBaseURLToFlakeURL ${gitBaseURL})${organization}/floxpkgs?ref=master")

fi

# vim:ts=4:noet:syntax=bash
