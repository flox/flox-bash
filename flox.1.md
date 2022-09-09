% FLOX(1) flox User Manuals

# NAME

flox - command-line interface (CLI)

# SYNOPSIS

flox [ `<options>` ] command [ `<command options>` ] [ `<args>` ] ...

# DESCRIPTION

flox is a platform for developing, building, and using packages created with Nix.
It can be used alone to simplify the process of working with Nix,
within a team for the sharing of development environments,
and in enterprises as system development lifecycle (SDLC) framework.

The `flox` CLI is used:

1. To manage and use collections of packages,
   environment variables and services
   known as flox *runtime environments*,
   which can be used in a variety of contexts
   on any Linux distribution, in or out of a container.
1. To launch flox *development environments*
   as maintained using a `flox.toml` file
   stored within a project directory.
1. As a wrapper for Nix functionality
   which drives the process of building packages with flox.

<!--
See *floxtutorial(7)* to get started.
More in-depth information is available by way of the [flox User's Manual](https://alpha.floxsdlc.com/docs/).
-->

# OPTIONS

## General options

-v, \--verbose
:   Verbose mode. Invoke multiple times for increasing detail.

-d, \--debug
:   Debug mode. Invoke multiple times for increasing detail.

-V, \--version
:   Print `flox` version.

\--prefix
:   Print `flox` installation prefix / Nix store path.
    (Flox internal use only.)

## Environment options

The following option is supported by all runtime environment subcommands:

-e `<name>`, \--environment `<name>`
:   Selects **flox environment** to be modified or used. If not provided then
    `flox` will fall back to using the `default` environment.

# SUBCOMMANDS

Flox commands are grouped into categories pertaining to
runtime environments, developer environments, and administration.

## Packages

**search** `<name>` [ --refresh ]
:   Search for available packages matching name.
    The list of available packages is updated hourly, but if required
    you can invoke with `--refresh` to update the list before searching.

## Runtime environments

**install** `<package>` [ `<package>` ... ]
:   Install package(s) to environment.
    See *PACKAGE ARGUMENTS* below for a description of flox package arguments.

**upgrade** `<package>` [ `<package>` ... ]
:   Upgrade package(s) in environment.
    See *PACKAGE ARGUMENTS* below for a description of flox package arguments.

**remove** `<package>` [ `<package>` ... ]
:   Remove package(s) from environment.
    See *PACKAGE ARGUMENTS* below for a description of flox package arguments.

**cat**
:   Display declarative environment manifest.

**edit**
:   Edit declarative environment manifest. Has the effect of creating the
    environment if it does not exist.

**environments**
:   List all environments.

**generations**
:   List generations of selected environment.

**list** [ `<generation>` ]
:   List contents of selected environment. Provide optional generation
    argument to list the contents of a specific generation.

**history** [ \--oneline ]
:   List history of selected environment. With `--oneline` arg, display concise
    format including only the subject line for history log entries.

**activate**
:   The "activate" subcommand adds environment `bin` directories to your
    `$PATH` environment variable and can be invoked from an interactive
    terminal to launch a sub-shell, non-interactively to produce
    a series of commands to be sourced by your current `$SHELL`,
    or with a command and arguments to be invoked directly.

    Examples:

    - activate "default" flox environment only within the current shell
    (add to the relevant "rc" file, e.g. `~/.bashrc` or `~/.zprofile`)
    ```
    . <(flox activate)
    ```

    - activate "foo" and "default" flox environments in a new subshell
    ```
    flox activate -p foo
    ```

    - invoke command using "foo" and "default" flox environments
    ```
    flox activate -p foo -- cmd --cmdflag cmdflagarg cmdarg
    ```

**push** / **pull** [ \--force ]
:   (`git`) Push or pull metadata to the environment's `floxmeta` repository.
    With this mechanism environments can be pushed and pulled between machines
    and within teams just as you would any project managed with `git`.

    With the `--force` argument flox will forceably overwrite either the
    upstream or local copy of the environment based on having invoked
    `push` or `pull`, respectively.

**destroy** [ \--origin ]
:   Remove all local data pertaining to an environment.
    Does *not* remove “upstream” environment data by default.

    Invoke with the `--origin` flag to delete environment data
    both upstream and downstream.

## Development

**develop**
:   Launch subshell configured for development environment using the
    `flox.toml` or Nix expression file as found in the current directory.

**publish** [ (-f|-s|-a|-r) ]
:   The `flox publish` command will perform a build, copy to cache substituter,
    and render of flox catalog data to the local repository for future use by
    flox. Command flags `-f` resolves to the flake url, multiple `-s` arguments
    may be submitted for substituters, `-a` denotes the attribute path, and `-r`
    specifies the directory to write the render to.

    - invoking command example
    ```
    flox publish -f github:flox/floxpkgs \
    -a x86_64-linux.stable.curl \
    -s https://flox-store-public.s3.us-east-1.amazonaws.com?trusted=1 \
    -r ./render
    ```

## Administration

**config** [ (--list|-l) ]
:   Configure and/or display user-specific parameters.

**git** `<git-subcommand>` [ `<args>` ]
:   Direct access to git command invoked in the `floxmeta` repository clone.
    Accepts the `(-e|--environment)` flag for repository selection.
    For expert use only.

**gh** `<gh-subcommand>` [ `<args>` ]
:   Direct access to gh command. For expert use only.

# PACKAGE ARGUMENTS

Flox package arguments are specified as a tuple of
stability, channel, name, and version in the format:
`<stability>`.`<channel>`.`<name>`@`<version>`

The version field is optional, defaulting to the latest version if not specified.

The stability field is also optional, defaulting to "stable" if not specified.

The channel field is also optional, defaulting to "nixpkgs" if not specified,
_but only if using the "stable" stability_. If using anything other than the
default "stable" stability, the channel *must* be specified.

For example, each of the following will install the latest hello version 2.12 from
the stable channel:
```
flox install stable.nixpkgs.hello@2.12
flox install stable.nixpkgs.hello
flox install nixpkgs.hello@2.12
flox install nixpkgs.hello
flox install hello@2.12
flox install hello
```

... and each of the following will install the older hello version 2.10
from the stable channel:
```
flox install stable.nixpkgs.hello@2.10
flox install nixpkgs.hello@2.10
flox install hello@2.10
```

... but only the following will install the older hello version 2.10 from the unstable channel:
```
flox install unstable.nixpkgs.hello@2.10
```

# ENVIRONMENT VARIABLES

`$FLOX_HOME`
:   Location for runtime flox environments as included in `PATH` environment variable.
    Defaults to `$XDG_DATA_HOME/flox/environments` or `$HOME/.local/share/flox/environments`
    if `$XDG_DATA_HOME` is not defined.

`$FLOX_PROMPT`
:   The **FLOX_PROMPT** variable defaults to `[flox] ` and can be used to specify
    an alternate flox indicator string (including fancy colors, if desired), or set
    to the empty string to opt out of prompt customization for interactive shells.

    For example, include the following in your `.bashrc` and/or `.zshprofile` file
    (or equivalent) to display the flox indicator in bright blue:

    - **bash**: `export FLOX_PROMPT="\[\033[1;34m\]flox\[\033[0m\] "`
    - **zsh**: `export FLOX_PROMPT='%B%F{blue}flox%f%b '`

`$FLOX_VERBOSE`
:   Setting **FLOX_VERBOSE=1** is the same as invoking `flox` with the `--verbose`
    argument except that it can be convenient to set this in the environment for
    the purposes of development.

`$FLOX_DEBUG`
:   Setting **FLOX_DEBUG=1** is the same as invoking `flox` with the `--debug`
    argument except that it activates debugging prior to the start of argument
    parsing and that it can be convenient to set this in the environment for
    the purposes of development.

`$EDITOR`, `$VISUAL`
:   Override the default editor used for editing environment manifests and commit messages.

<!--
# EXAMPLES

# SEE ALSO

`flox-framework`(7)

`flox-tutorial`(7)
-->
