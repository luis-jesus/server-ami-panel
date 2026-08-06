#!/usr/bin/env bash

collect_package_inventory() {
    local package_backend=$1

    case $package_backend in
        dpkg)
            write_command_output "packages-dpkg" dpkg-query -W -f='${binary:Package}\t${Version}\n'
            ;;
        rpm)
            write_command_output "packages-rpm" rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n'
            ;;
        pacman)
            write_command_output "packages-pacman" pacman -Q
            ;;
        zypper)
            write_command_output "packages-zypper" zypper search --installed-only --details
            ;;
        apk)
            write_command_output "packages-apk" apk info -vv
            ;;
        xbps)
            write_command_output "packages-xbps" xbps-query -l
            ;;
        portage)
            write_command_output "packages-portage" qlist -Iv
            ;;
        nix)
            write_shell_output "packages-nix" 'nix-store --query --requisites /run/current-system || nix profile list'
            ;;
        *)
            printf '## packages\nbackend-unavailable\n\n'
            ;;
    esac
}

collect_optional_manager_inventory() {
    if command_exists snap; then
        write_command_output "packages-snap" snap list
    fi

    if command_exists flatpak; then
        write_command_output "packages-flatpak" flatpak list
    fi

    if command_exists python3; then
        write_shell_output "packages-pip-python3" 'python3 -m pip list --format=freeze'
    elif command_exists pip3; then
        write_command_output "packages-pip3" pip3 list --format=freeze
    elif command_exists pip; then
        write_command_output "packages-pip" pip list --format=freeze
    fi

    if command_exists pipx; then
        write_command_output "packages-pipx" pipx list
    fi

    if command_exists npm; then
        write_shell_output "packages-npm-global" 'npm -g ls --depth=0 2>&1 || true'
    fi

    if command_exists cargo; then
        write_command_output "packages-cargo" cargo install --list
    fi

    if command_exists gem; then
        write_command_output "packages-gem" gem list
    fi

    if command_exists go; then
        write_command_output "go-environment" go env
    fi
}

collect_runtime_versions() {
    local output_file=$1
    local -a tools=(bash git gcc clang make cmake python3 python pip3 pip node npm java javac rustc cargo go ruby gem php perl docker podman kubectl helm terraform ansible nmap wireshark tshark sqlmap msfconsole)
    local tool

    for tool in "${tools[@]}"; do
        write_tool_version "$output_file" "$tool"
    done
}

collect_software_inventory() {
    local output_file=$1
    local package_backend=$2

    {
        printf 'package_backend=%s\n\n' "$package_backend"
        collect_package_inventory "$package_backend"
        collect_optional_manager_inventory
    } > "$output_file"

    collect_runtime_versions "$output_file"
}