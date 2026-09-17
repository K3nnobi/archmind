#!/usr/bin/env zsh

typeset -g ARCHMIND_PYTHON_PROJECT="${ARCHMIND_PYTHON_PROJECT:-$PWD}"

python_service_binary() {
    emulate -L zsh

    if command -v python >/dev/null 2>&1; then
        command -v python
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        return 1
    fi
}

python_service_version() {
    emulate -L zsh

    local binary=""

    binary="$(python_service_binary)" || {
        print -r -- "Not installed"
        return 1
    }

    "$binary" --version 2>&1
}

python_service_pip() {
    emulate -L zsh

    local binary=""

    binary="$(python_service_binary)" || return 1

    if "$binary" -m pip --version >/dev/null 2>&1; then
        "$binary" -m pip --version 2>/dev/null
        return 0
    fi

    print -r -- "Unavailable"
    return 1
}

python_service_active_venv() {
    emulate -L zsh

    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        print -r -- "$VIRTUAL_ENV"
        return 0
    fi

    print -r -- "None"
    return 1
}

python_service_project() {
    emulate -L zsh

    local project="${ARCHMIND_PYTHON_PROJECT:-$PWD}"

    if [[ -d "$project" ]]; then
        print -r -- "${project:A}"
    else
        print -r -- "${PWD:A}"
    fi
}

python_collect_information() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PYTHON_INFORMATION_LINES

    local binary="Not found"
    local version="Not installed"
    local pip_info="Unavailable"
    local active_venv="None"
    local project=""
    local site_packages="Unavailable"

    project="$(python_service_project)"

    if binary="$(python_service_binary 2>/dev/null)"; then
        version="$(python_service_version)"
        pip_info="$(python_service_pip)" || true
        active_venv="$(python_service_active_venv)" || true

        site_packages="$(
            "$binary" - <<'PY' 2>/dev/null
import site

paths = site.getsitepackages()
print(paths[0] if paths else "Unavailable")
PY
        )"

        [[ -n "$site_packages" ]] || site_packages="Unavailable"
    fi

    PYTHON_INFORMATION_LINES=(
        "Executable .......... ${binary}"
        "Version .............. ${version}"
        "Pip ................. ${pip_info}"
        "Active environment ...... ${active_venv}"
        "Project ............. ${project}"
        "Site-packages ....... ${site_packages}"
    )
}

python_collect_environments() {
    emulate -L zsh
    setopt localoptions typesetsilent nullglob

    typeset -ga PYTHON_ENVIRONMENT_LINES

    local project=""
    local environment=""
    local count=0
    local -a candidates

    project="$(python_service_project)"

    candidates=(
        "$project"/.venv(N/)
        "$project"/venv(N/)
        "$project"/env(N/)
        "$HOME"/.virtualenvs/*(N/)
    )

    PYTHON_ENVIRONMENT_LINES=(
        "Searched project:"
        "$project"
        ""
        "Environments found:"
    )

    for environment in "${candidates[@]}"; do
        [[ -x "$environment/bin/python" ]] || continue

        PYTHON_ENVIRONMENT_LINES+=(
            ""
            "${environment}"
            "  Python: $("$environment/bin/python" --version 2>&1)"
        )

        (( count++ ))
        (( count >= 10 )) && break
    done

    if (( count == 0 )); then
        PYTHON_ENVIRONMENT_LINES+=(
            ""
            "No virtual environments were found."
        )
    fi
}

python_collect_packages() {
    emulate -L zsh
    setopt localoptions typesetsilent

    typeset -ga PYTHON_PACKAGE_LINES

    local binary=""
    local output=""

    binary="$(python_service_binary)" || {
        PYTHON_PACKAGE_LINES=("Python is not installed.")
        return 1
    }

    output="$(
        "$binary" -m pip list \
            --format=columns \
            2>/dev/null |
            head -n 22
    )"

    if [[ -z "$output" ]]; then
        PYTHON_PACKAGE_LINES=(
            "Pip is not available in this environment."
            ""
            "On Arch Linux, avoid global pip installations."
            "Use pacman, pipx or a virtual environment."
        )
        return 1
    fi

    PYTHON_PACKAGE_LINES=(
        "Packages in the current Python environment:"
        ""
        "$output"
        ""
        "List limited to the first entries."
    )
}

python_create_venv() {
    emulate -L zsh
    setopt localoptions typesetsilent

    local binary=""
    local project=""
    local environment=""

    binary="$(python_service_binary)" || {
        print -u2 -- "Python is not installed."
        return 1
    }

    project="$(python_service_project)"
    environment="$project/.venv"

    if [[ -e "$environment" ]]; then
        print -u2 -- "The path already exists:"
        print -u2 -- "$environment"
        return 1
    fi

    print -r -- "Project: $project"
    print -r -- "Environment: $environment"
    print
    print -r -- "Creating virtual environment..."

    "$binary" -m venv "$environment" || return 1

    print
    print -r -- "Virtual environment created successfully."
    print -r -- "To activate:"
    print -r -- "source \"$environment/bin/activate\""
}

python_show_activation_command() {
    emulate -L zsh

    local project=""
    local environment=""

    project="$(python_service_project)"

    if [[ -d "$project/.venv" ]]; then
        environment="$project/.venv"
    elif [[ -d "$project/venv" ]]; then
        environment="$project/venv"
    else
        print -r -- "No .venv or venv environment was found."
        return 1
    fi

    print -r -- "Run this command:"
    print
    print -r -- "source \"$environment/bin/activate\""
}
