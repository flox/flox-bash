% FLOX(1) Flox User Manuals
% Michael Brantley, Tom Bereknyei
% March 8, 2022

# NAME

flox - Flox command-line interface (CLI)

# SYNOPSIS

flox [*options*] command [*command options*] [*args*]...

# DESCRIPTION

Flox is a platform for developing, building, and using packages created with Nix.
It can be used alone to simplify the process of working with Nix,
within a team for the sharing of development environments,
and in enterprises as system development lifecycle (SDLC) framework.

The `flox` CLI is used:

1. To manage collections of packages, environment variables and services
   known as *Flox profiles*,
   which can be used in a variety of contexts
   on any Linux distribution, in or out of a container.
2. As a wrapper for providing the Nix functionality
   which drives the process of building packages with Flox.

See *floxtutorial(7)* to get started.
More in-depth information is available by way of the [Flox User's Manual](https://floxdev.com/docs).

# OPTIONS

## General options

-V, \--version
:   Print `flox` version.

-v, \--verbose
:   Verbose mode. Invoke multiple times for increasing verbosity.

-d, \--debug
:   Debug mode. Invoke multiple times for increasing detail.

## Profile selection options

The following options are applicable to `flox` commands affecting profiles:

-f *file*, \--profile-file=*file*
:   Specifies the path to the **flox profile** configuration file to be used.

-p *name*, \--profile-name=*name*
:   Syntactic sugar for specifying **flox profile** configuration file paths
    maintained in the user's `$FLOX_HOME` directory.
    Defaults to `$XDG_DATA_HOME/flox/profiles` or `$HOME/.local/share/flox/profiles`
    if `$XDG_DATA_HOME` is not defined.

If neither of the above options are provided
`flox` looks for a `flox.toml` file in the current directory,
and if not found will fall back to `$FLOX_HOME/default.toml`.

# FLOX COMMANDS

Flox commands are grouped into categories pertaining
to developer environments, profile management, and administration.

## Profile management

**install**
:   Install package(s) to profile.

**upgrade**
:   Upgrade package(s in profile.

## Development

**activate**
:   The "activate" subcommand adds profile paths to your `$PATH`
    environment variable and either can be invoked from an interactive
    terminal to launch a sub-shell or non-interactively to produce
    a series of commands that can be sourced by your current `$SHELL`.

    To use flox most effectively we recommend adding the following
    to the relevant "rc" file (e.g. `~/.bashrc` or `~/.zprofile`):
    ```
    source <(flox activate)
    ```

**develop**
:   Launch subshell configured for development environment,
    sourcing the following configuration files in this order:

    - project committed ./flox.toml
    - personal rc file: ~/.flox.toml
    - project-specific uncommited ./flox.toml.personal

    The result will be a "flattened" view whereby the configuration
    directives in each file supersedes the previous.

**register**
:   Activate profile.

## Administration

**foo**
:   Do foo.

**bar**
:   Do bar.

# ENVIRONMENT VARIABLES

`$FLOX_PROMPT`
:   The **FLOX_PROMPT** variable defaults to `[flox] ` and can be used to specify
    an alternate flox indicator string (including fancy colors, if desired), or set
    to the empty string to opt out of prompt customization for interactive shells.

    For example, include the following in your `.bashrc` and/or `.zshprofile` file
    (or equivalent) to display the flox indicator in bright blue:

    - **bash**: `export FLOX_PROMPT="\[\033[1;34m\]flox\[\033[0m\] "`
    - **zsh**: `export FLOX_PROMPT='%B%F{blue}flox%f%b '`

`$XDG_CACHE_HOME`
:   asdlkfj

`$FLOX_HOME`
:   asdlkfj

# EXAMPLES

# SEE ALSO

`flox-framework`(7)

`flox-tutorial`(7)
