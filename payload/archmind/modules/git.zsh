# ==========================================
# ArchMind Git Module
# Intelligence meets Linux
# ==========================================

_archmind_git_require_repo() {
    if ! command -v git >/dev/null 2>&1; then
        _archmind_error "Git is not installed."
        return 1
    fi

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        _archmind_error "This directory is not part of a Git repository."
        return 1
    fi
}

archmind_git_status() {
    _archmind_git_require_repo || return 1

    local repo_root
    local branch
    local remote
    local ahead=0
    local behind=0

    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    branch="$(git branch --show-current 2>/dev/null)"
    remote="$(git remote get-url origin 2>/dev/null)"

    echo
    print -P "%F{cyan}%BARCHMIND GIT%b%f"
    print -P "%F{magenta}Repository summary%f"
    echo

    printf "%-14s %s\n" "Repository:" "${repo_root:t}"
    printf "%-14s %s\n" "Directory:" "$repo_root"
    printf "%-14s %s\n" "Branch:" "${branch:-detached HEAD}"
    printf "%-14s %s\n" "Remote:" "${remote:-not configured}"

    if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
        local counts

        counts="$(
            git rev-list \
                --left-right \
                --count \
                HEAD...'@{upstream}' \
                2>/dev/null
        )"

        read -r ahead behind <<< "$counts"

        printf "%-14s %s\n" "Ahead:" "${ahead:-0} commit(s)"
        printf "%-14s %s\n" "Behind:" "${behind:-0} commit(s)"
    else
        printf "%-14s %s\n" "Upstream:" "not configured"
    fi

    echo
    git status --short --branch
    echo
}

archmind_git_log() {
    _archmind_git_require_repo || return 1

    local amount="${1:-15}"

    if [[ ! "$amount" =~ '^[0-9]+$' ]]; then
        _archmind_error "Specify a numeric amount."
        return 1
    fi

    echo
    print -P "%F{cyan}%BGIT HISTORY%b%f"
    echo

    git log \
        --graph \
        --decorate \
        --date=short \
        --pretty=format:'%C(cyan)%h%Creset %C(yellow)%ad%Creset %C(auto)%d%Creset %s %C(magenta)— %an%Creset' \
        -n "$amount"

    echo
    echo
}

archmind_git_branches() {
    _archmind_git_require_repo || return 1

    echo
    print -P "%F{cyan}%BBRANCHES GIT%b%f"
    echo

    git branch \
        --all \
        --verbose \
        --verbose

    echo
}

archmind_git_diff() {
    _archmind_git_require_repo || return 1

    echo
    print -P "%F{cyan}%BUNSTAGED CHANGES%b%f"
    echo

    if git diff --quiet; then
        _archmind_ok "No unstaged changes."
    else
        git diff --stat
        echo
        git diff --color=always | less -R
    fi
}

archmind_git_diff_staged() {
    _archmind_git_require_repo || return 1

    echo
    print -P "%F{cyan}%BSTAGED CHANGES%b%f"
    echo

    if git diff --cached --quiet; then
        _archmind_ok "No staged changes."
    else
        git diff --cached --stat
        echo
        git diff --cached --color=always | less -R
    fi
}

archmind_git_commit() {
    _archmind_git_require_repo || return 1

    if [[ -z "$1" ]]; then
        _archmind_error "Informe a mensagem do commit."
        echo
        echo 'Example:'
        echo '  archmind git commit "Add system module"'
        return 1
    fi

    if git diff --cached --quiet; then
        _archmind_warn "There are no staged files to commit."
        echo
        echo "Use:"
        echo "  git add file"
        echo "ou:"
        echo "  archmind git add"
        return 1
    fi

    local message="$*"

    echo
    print -P "%F{cyan}%BCOMMIT CONFIRMATION%b%f"
    echo
    printf "Message: %s\n" "$message"
    echo

    git diff --cached --stat
    echo

    local confirmation
    read "confirmation?Create this commit? [y/N] "

    case "${confirmation:l}" in
        y|yes)
            git commit -m "$message"
            ;;
        *)
            _archmind_warn "Commit cancelled."
            return 1
            ;;
    esac
}

archmind_git_add() {
    _archmind_git_require_repo || return 1

    echo
    print -P "%F{cyan}%BMODIFIED FILES%b%f"
    echo

    git status --short
    echo

    local confirmation
    read "confirmation?Add all changes? [y/N] "

    case "${confirmation:l}" in
        y|yes)
            git add --all
            _archmind_ok "Changes added to the staging area."
            ;;
        *)
            _archmind_warn "Operation cancelled."
            return 1
            ;;
    esac
}

archmind_git_pull() {
    _archmind_git_require_repo || return 1

    if [[ -n "$(git status --porcelain)" ]]; then
        _archmind_warn "There are uncommitted local changes."
        echo "Commit or stash them before synchronizing."
        return 1
    fi

    local branch
    branch="$(git branch --show-current)"

    if [[ -z "$branch" ]]; then
        _archmind_error "Cannot update in detached HEAD state."
        return 1
    fi

    if ! git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
        _archmind_error "The current branch has no upstream."
        return 1
    fi

    git pull --ff-only
}

archmind_git_push() {
    _archmind_git_require_repo || return 1

    local branch
    branch="$(git branch --show-current)"

    if [[ -z "$branch" ]]; then
        _archmind_error "Cannot push in detached HEAD state."
        return 1
    fi

    if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
        git push
    else
        _archmind_warn "The branch does not have an upstream yet."
        echo

        local confirmation
        read "confirmation?Publish '$branch' to origin? [y/N] "

        case "${confirmation:l}" in
            y|yes)
                git push --set-upstream origin "$branch"
                ;;
            *)
                _archmind_warn "Push cancelled."
                return 1
                ;;
        esac
    fi
}

archmind_git_sync() {
    _archmind_git_require_repo || return 1

    if [[ -n "$(git status --porcelain)" ]]; then
        _archmind_error "There are pending local changes."
        echo "Commit or stash them before synchronizing."
        return 1
    fi

    echo
    print -P "%F{cyan}%BGIT SYNCHRONIZATION%b%f"
    echo

    archmind_git_pull || return 1
    archmind_git_push
}

archmind_git_new_branch() {
    _archmind_git_require_repo || return 1

    local branch_name="$1"

    if [[ -z "$branch_name" ]]; then
        _archmind_error "Informe o nome da nova branch."
        echo
        echo "Example:"
        echo "  archmind git branch feature/menu"
        return 1
    fi

    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        _archmind_error "Branch '$branch_name' already exists."
        return 1
    fi

    git switch -c "$branch_name"
}

archmind_git() {
    local command="${1:-status}"
    shift 2>/dev/null || true

    case "$command" in
        status)
            archmind_git_status
            ;;
        log)
            archmind_git_log "$@"
            ;;
        branches)
            archmind_git_branches
            ;;
        diff)
            archmind_git_diff
            ;;
        staged)
            archmind_git_diff_staged
            ;;
        add)
            archmind_git_add
            ;;
        commit)
            archmind_git_commit "$@"
            ;;
        pull)
            archmind_git_pull
            ;;
        push)
            archmind_git_push
            ;;
        sync)
            archmind_git_sync
            ;;
        branch)
            archmind_git_new_branch "$@"
            ;;
        help|--help|-h)
            echo
            print -P "%F{cyan}ArchMind Git%f"
            echo
            echo "Usage:"
            echo "  archmind git status"
            echo "  archmind git log [quantidade]"
            echo "  archmind git branches"
            echo "  archmind git diff"
            echo "  archmind git staged"
            echo "  archmind git add"
            echo '  archmind git commit "mensagem"'
            echo "  archmind git pull"
            echo "  archmind git push"
            echo "  archmind git sync"
            echo "  archmind git branch nome"
            echo
            ;;
        *)
            _archmind_error "Unknown Git command: $command"
            echo "Use: archmind git help"
            return 1
            ;;
    esac
}

# Direct shortcuts, without replacing important native commands.

gstatus() {
    archmind_git_status
}

glog() {
    archmind_git_log "$@"
}

gbranches() {
    archmind_git_branches
}

gsync() {
    archmind_git_sync
}
