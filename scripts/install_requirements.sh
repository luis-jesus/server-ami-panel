#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

AUTO_YES=0
PRINT_ONLY=0

print_usage() {
    cat <<'EOF'
Usage: bash scripts/install_requirements.sh [options]

Install the base system dependencies required to run ServerAM1.

Options:
  -y, --yes      Use non-interactive confirmation flags where supported.
      --print    Print the detected install command without executing it.
  -h, --help     Show this help message.

Notes:
  - This script installs system packages, not Python packages from requirements.txt.
    - The project itself does not require third-party Python libraries.
    - The installer uses a managed virtual environment and needs venv support.
  - Supported package backends: dpkg/apt, zypper, rpm with dnf or yum,
    pacman, apk and xbps.
EOF
}

parse_args() {
    while (($# > 0)); do
        case $1 in
            -y|--yes)
                AUTO_YES=1
                shift
                ;;
            --print)
                PRINT_ONLY=1
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                printf 'unknown option: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done
}

parse_args "$@"

append_auto_yes() {
    local flag=$1
    if ((AUTO_YES == 1)); then
        INSTALL_COMMAND+=("$flag")
    fi
}

build_install_command() {
    local pkg_backend=$1

    case $pkg_backend in
        dpkg)
            if ! command_exists apt-get; then
                printf 'apt-get is required for the dpkg backend\n' >&2
                return 1
            fi
            INSTALL_COMMAND=(apt-get install)
            append_auto_yes "-y"
            INSTALL_COMMAND+=(python3 python3-pip python3-venv)
            ;;
        zypper)
            INSTALL_COMMAND=(zypper install)
            append_auto_yes "-y"
            INSTALL_COMMAND+=(python3 python3-pip)
            ;;
        rpm)
            if command_exists dnf; then
                INSTALL_COMMAND=(dnf install)
                append_auto_yes "-y"
                INSTALL_COMMAND+=(python3 python3-pip)
            elif command_exists yum; then
                INSTALL_COMMAND=(yum install)
                append_auto_yes "-y"
                INSTALL_COMMAND+=(python3 python3-pip)
            else
                printf 'rpm backend detected but neither dnf nor yum is available\n' >&2
                return 1
            fi
            ;;
        pacman)
            INSTALL_COMMAND=(pacman -S)
            append_auto_yes "--noconfirm"
            INSTALL_COMMAND+=(python python-pip)
            ;;
        apk)
            INSTALL_COMMAND=(apk add)
            INSTALL_COMMAND+=(python3 py3-pip)
            ;;
        xbps)
            INSTALL_COMMAND=(xbps-install)
            append_auto_yes "-y"
            INSTALL_COMMAND+=(python3 python3-pip)
            ;;
        *)
            printf 'unsupported or unknown package backend: %s\n' "$pkg_backend" >&2
            printf 'install python3 and pip manually for your distribution\n' >&2
            return 1
            ;;
    esac
}

main() {
    local pkg_backend="unknown"
    local prefix=()

    pkg_backend=$(detect_package_backend)
    build_install_command "$pkg_backend"

    if ((EUID != 0)); then
        if command_exists sudo; then
            prefix=(sudo)
        else
            printf 'run this script as root or install sudo first\n' >&2
            return 1
        fi
    fi

    if ((PRINT_ONLY == 1)); then
        printf 'detected_package_backend=%s\n' "$pkg_backend"
        printf 'install_command=%s\n' "${prefix[*]} ${INSTALL_COMMAND[*]}"
        return 0
    fi

    printf 'detected_package_backend=%s\n' "$pkg_backend"
    printf 'running_install_command=%s\n' "${prefix[*]} ${INSTALL_COMMAND[*]}"
    "${prefix[@]}" "${INSTALL_COMMAND[@]}"
}

main "$@"