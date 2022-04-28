zshenv=${FLOX_ORIG_ZDOTDIR:-$HOME}/.zshenv
if [ -f ${zshenv} ]
then
    ZDOTDIR=${FLOX_ORIG_ZDOTDIR} FLOX_ORIG_ZDOTDIR= source ${zshenv}
fi
