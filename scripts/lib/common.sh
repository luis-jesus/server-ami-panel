#!/usr/bin/env bash

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

write_command_output() {
    local title=$1
    shift
    local tmp_file
    local status=0

    tmp_file=$(mktemp)
    printf '## %s\n' "$title"
    if "$@" >"$tmp_file" 2>&1; then
        cat "$tmp_file"
    else
        status=$?
        if [[ -s "$tmp_file" ]]; then
            cat "$tmp_file"
        else
            printf 'unavailable\n'
        fi
        printf '\nexit_code=%s\n' "$status"
    fi
    printf '\n'
    rm -f "$tmp_file"
}

write_shell_output() {
    local title=$1
    shift
    write_command_output "$title" sh -c "$*"
}

resolve_target_user() {
    printf '%s\n' "${SUDO_USER:-${USER:-unknown}}"
}

resolve_target_home() {
    local target_user
    target_user=$(resolve_target_user)

    if command_exists getent; then
        getent passwd "$target_user" | awk -F: 'NR == 1 { print $6 }'
        return 0
    fi

    printf '%s\n' "$HOME"
}

append_existing_path() {
    local list_file=$1
    local path=$2

    if [[ -e "$path" ]]; then
        printf '%s\n' "$path" >> "$list_file"
    fi
}

write_tool_version() {
    local output_file=$1
    local tool=$2
    local label=${3:-$tool}

    if command_exists "$tool"; then
        write_shell_output "$label-version" "$tool --version | head -n 1"
    fi >> "$output_file"
}