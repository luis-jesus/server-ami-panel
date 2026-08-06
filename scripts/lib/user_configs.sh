#!/usr/bin/env bash

collect_user_configs() {
    local summary_file=$1
    local archive_file=$2
    local list_file
    local target_home
    local tar_stderr_file
    local tar_status=0

    list_file="${archive_file%.tar.gz}.list"
    tar_stderr_file="${archive_file%.tar.gz}.stderr.log"
    target_home=$(resolve_target_home)
    : > "$list_file"

    append_existing_path "$list_file" /etc
    append_existing_path "$list_file" /usr/local/etc
    append_existing_path "$list_file" /var/spool/cron
    append_existing_path "$list_file" "$target_home/.bashrc"
    append_existing_path "$list_file" "$target_home/.bash_profile"
    append_existing_path "$list_file" "$target_home/.profile"
    append_existing_path "$list_file" "$target_home/.zshrc"
    append_existing_path "$list_file" "$target_home/.gitconfig"
    append_existing_path "$list_file" "$target_home/.ssh"
    append_existing_path "$list_file" "$target_home/.gnupg"
    append_existing_path "$list_file" "$target_home/.local/share/applications"
    append_existing_path "$list_file" "$target_home/.local/share/Steam/config"
    append_existing_path "$list_file" "$target_home/.steam/steam/config"
    append_existing_path "$list_file" "$target_home/.config/systemd/user"
    append_existing_path "$list_file" "$target_home/.config/Code/User"
    append_existing_path "$list_file" "$target_home/.config/wireshark"
    append_existing_path "$list_file" "$target_home/.config/terminator"
    append_existing_path "$list_file" "$target_home/.config/libvirt"
    append_existing_path "$list_file" "$target_home/.config/VirtualBox"
    append_existing_path "$list_file" "$target_home/.config/lutris"
    append_existing_path "$list_file" "$target_home/.config/heroic"
    append_existing_path "$list_file" "$target_home/.config/MangoHud"
    append_existing_path "$list_file" "$target_home/.config/pulse"
    append_existing_path "$list_file" "$target_home/.config/gtk-3.0"
    append_existing_path "$list_file" "$target_home/.config/gtk-4.0"
    append_existing_path "$list_file" "$target_home/.config/nvim"
    append_existing_path "$list_file" "$target_home/.config/htop"
    append_existing_path "$list_file" "$target_home/.config/neofetch"
    append_existing_path "$list_file" "$target_home/.config/alacritty"
    append_existing_path "$list_file" "$target_home/.config/kitty"
    append_existing_path "$list_file" "$target_home/.config/fish"
    append_existing_path "$list_file" "$target_home/.docker/config.json"
    append_existing_path "$list_file" "$target_home/.docker/daemon.json"
    append_existing_path "$list_file" "$target_home/.kube"

    {
        printf 'target_user=%s\n' "$(resolve_target_user)"
        printf 'target_home=%s\n' "$target_home"
        printf 'archive_file=%s\n\n' "$archive_file"
        printf 'included_paths:\n'
        cat "$list_file"
        printf '\n'
    } > "$summary_file"

    if [[ ! -s "$list_file" ]]; then
        printf 'no_paths_selected\n' >> "$summary_file"
        return 0
    fi

    tar -czf "$archive_file" \
        --ignore-failed-read \
        --warning=no-file-changed \
        --exclude='/etc/shadow' \
        --exclude='/etc/shadow-' \
        --exclude='/etc/gshadow' \
        --exclude='/etc/gshadow-' \
        --exclude='/etc/ssh/ssh_host_*' \
        --exclude='/etc/NetworkManager/system-connections/*' \
        --exclude='/etc/libvirt/secrets/*' \
        --exclude='*/cache/*' \
        --exclude='*/Cache/*' \
        --exclude='*/Code/Cache/*' \
        --exclude='*/Code/CachedData/*' \
        --exclude='*/Code/Service Worker/CacheStorage/*' \
        --exclude='*/.cache/*' \
        --exclude='*/logs/*' \
        --exclude='*.sock' \
        -T "$list_file" \
        2> "$tar_stderr_file" || tar_status=$?

    {
        printf 'archive_status=%s\n' "$tar_status"
        printf 'archive_stderr=%s\n' "$tar_stderr_file"
    } >> "$summary_file"

    if [[ $tar_status -ne 0 && ! -s "$archive_file" ]]; then
        return "$tar_status"
    fi

    return 0
}