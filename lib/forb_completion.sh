#!/bin/bash

_forb_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="-h --help --json --html -l --list -e --edit \
          -P --preset -np --no-preset -gp --get-presets -cp --create-preset \
          -lp --list-presets -op --open-presets -rp --remove-preset -oh --open-html -ol --open-logs \
          -b --blacklist -v --verbose -f -p --full-path -a --all --no-auto \
          -s --source -mlx -lm -t --time --version -up --update --remove --log"

    case "$prev" in
        -f)
            COMPREPLY=( $(compgen -f -- "${cur}") )
            return 0
            ;;
    esac
    if [[ ${cur} == -* ]] ; then
        COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
        return 0
    fi
    COMPREPLY=( $(compgen -f -- "${cur}") )
}
complete -F _forb_completions forb
