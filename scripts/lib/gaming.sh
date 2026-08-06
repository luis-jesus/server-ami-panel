#!/usr/bin/env bash

collect_gaming_inventory() {
    local output_file=$1
    local target_home

    target_home=$(resolve_target_home)

    {
        write_tool_version "$output_file" steam
        write_tool_version "$output_file" lutris
        write_tool_version "$output_file" heroic
        write_tool_version "$output_file" wine
        write_tool_version "$output_file" mangohud

        if command_exists glxinfo; then
            write_command_output "opengl-summary" glxinfo -B
        fi

        if command_exists vulkaninfo; then
            write_shell_output "vulkan-summary" 'vulkaninfo --summary 2>/dev/null || vulkaninfo 2>/dev/null'
        fi

        if command_exists nvidia-smi; then
            write_command_output "nvidia-gpus" nvidia-smi -L
        fi

        write_shell_output "gpu-modules" 'lsmod | grep -E "nvidia|amdgpu|radeon|nouveau|i915" || true'

        if command_exists pactl; then
            write_command_output "pulseaudio-info" pactl info
        fi

        if command_exists wpctl; then
            write_command_output "wireplumber-status" wpctl status
        fi

        if command_exists aplay; then
            write_command_output "alsa-playback-devices" aplay -l
        fi

        printf '## gaming-config-paths\n'
        [[ -d "$target_home/.local/share/Steam" ]] && printf '%s\n' "$target_home/.local/share/Steam"
        [[ -d "$target_home/.steam" ]] && printf '%s\n' "$target_home/.steam"
        [[ -d "$target_home/.config/lutris" ]] && printf '%s\n' "$target_home/.config/lutris"
        [[ -d "$target_home/.config/heroic" ]] && printf '%s\n' "$target_home/.config/heroic"
        [[ -d "$target_home/.config/MangoHud" ]] && printf '%s\n' "$target_home/.config/MangoHud"
        printf '\n'
    } > "$output_file"
}