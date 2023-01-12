zshrc=${FLOX_ORIG_ZDOTDIR:-$HOME}/.zshrc

# This is the only file in which we need to perform flox actions so
# take this opportunity to restore the user's original $ZDOTDIR if
# defined, otherwise remove it from the environment.
if [ -n "$FLOX_ORIG_ZDOTDIR" ]
then
	export ZDOTDIR=$FLOX_ORIG_ZDOTDIR
	unset FLOX_ORIG_ZDOTDIR
else
	unset ZDOTDIR
fi

# Do all of the usual initializations.
if [ -f ${zshrc} ]
then
    source ${zshrc}
fi

# Bring in the set of default environment variables.
source @@PREFIX@@/etc/flox.profile

for dir in ${(s.:.)FLOX_XDG_DATA_DIRS_PREPEND-}; do
    if [ -d "$dir/zsh/site-functions" ]; then
      fpath=("$dir/zsh/site-functions" $fpath)
    fi
    if [ -d "$dir/zsh/vendor-completions" ]; then
      fpath=("$dir/zsh/vendor-completions" $fpath)
    fi
done

autoload -U compinit
compinit

# Tweak the (already customized) prompt: add a flox indicator.
if [ -z "$FLOX_PROMPT_DISABLE" ]; then
    _floxPrompt1="%F{${FLOX_PROMPT_COLOR_1}}flox"
    _floxPrompt2="%F{$FLOX_PROMPT_COLOR_2}[$FLOX_PROMPT_ENVIRONMENTS]"
    _flox="%B${FLOX_PROMPT-$_floxPrompt1} ${_floxPrompt2}%f%b "
fi

if [ -n "$_flox" -a -n "$PS1" ]
then
    case "$PS1" in
        # If the prompt contains an embedded newline,
        # then insert the flox indicator immediately after
        # the (first) newline.
        *\\n*)      PS1="${PS1/\\n/\\n$_flox}";;
        *\\012*)    PS1="${PS1/\\012/\\012$_flox}";;

        # Otherwise, prepend the flox indicator.
        *)          PS1="$_flox$PS1";;
    esac

    # TODO: figure out zsh way of setting window and icon title.
fi

unset _flox _floxPrompt1 _floxPrompt2
