_smia_profile_names() {
    smia profiles list --names 2>/dev/null || true
}

_smia_complete() {
    local cur command candidates
    cur="${COMP_WORDS[COMP_CWORD]}"
    command="${COMP_WORDS[1]:-}"
    COMPREPLY=()

    if ((COMP_CWORD == 1)); then
        candidates="help list $(smia list --names 2>/dev/null || true)"
        mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$cur")
        return 0
    fi

    case "$command" in
        help)
            if ((COMP_CWORD == 2)); then
                candidates="$(smia list --names 2>/dev/null || true)"
                mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$cur")
            fi
            ;;
        install)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W \
                    "mango-desktop mango-gaming niri-desktop niri-gaming hyprland-desktop hyprland-gaming" \
                    -- "$cur")
            else
                mapfile -t COMPREPLY < <(compgen -W "--astral" -- "$cur")
            fi
            ;;
        list)
            mapfile -t COMPREPLY < <(compgen -W "--names --verbose" -- "$cur")
            ;;
        profiles)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W "list current select switch" -- "$cur")
            elif [[ "${COMP_WORDS[2]:-}" == switch && $COMP_CWORD -eq 3 ]]; then
                candidates="$(_smia_profile_names)"
                mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$cur")
            elif [[ "${COMP_WORDS[2]:-}" == list ]]; then
                mapfile -t COMPREPLY < <(compgen -W "--names" -- "$cur")
            fi
            ;;
        session)
            mapfile -t COMPREPLY < <(compgen -W "--apply-theme --reapply-theme --help" -- "$cur")
            ;;
        system-model)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W "path plan apply --help" -- "$cur")
            fi
            ;;
        update)
            mapfile -t COMPREPLY < <(compgen -W "--help" -- "$cur")
            ;;
        status)
            mapfile -t COMPREPLY < <(compgen -W "--help" -- "$cur")
            ;;
        idle|dnd)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W "status toggle --help" -- "$cur")
            fi
            ;;
        record)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W "toggle start stop status --help" -- "$cur")
            elif ((COMP_CWORD == 3)); then
                mapfile -t COMPREPLY < <(compgen -W "screen region" -- "$cur")
            fi
            ;;
        night-light)
            if ((COMP_CWORD == 2)); then
                mapfile -t COMPREPLY < <(compgen -W "start stop toggle status --help" -- "$cur")
            fi
            ;;
    esac
}

complete -F _smia_complete smia
