# Do all of the usual initializations.
if [ -f ~/.bashrc ]
then
    source ~/.bashrc
fi

# Tweak the (already customized) prompt: add a flox indicator.
_flox=${FLOXRUN_PROMPT-"[flox] "}

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

    # Older versions of bash don't support the "@P" operator
    # so attempt the eval first before proceeding for real.
    if eval ': "${_flox@P}"' 2> /dev/null
    then
        # Remove all color and escape sequences from $_flox
        # before adding to window titles and icon names.
        _flox=$(echo "${_flox@P}" | ansifilter)

        # Prepend the flox indicator to window titles and icon names.
        PS1="${PS1//\\e]0;/\\e]0;$_flox}"
        PS1="${PS1//\\e]1;/\\e]1;$_flox}"
        PS1="${PS1//\\e]2;/\\e]2;$_flox}"

        PS1="${PS1//\\033]0;/\\033]0;$_flox}"
        PS1="${PS1//\\033]1;/\\033]1;$_flox}"
        PS1="${PS1//\\033]2;/\\033]2;$_flox}"
    fi
fi

unset _flox
