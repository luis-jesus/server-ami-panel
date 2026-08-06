#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"
# shellcheck source=lib/system.sh
source "$SCRIPT_DIR/lib/system.sh"
# shellcheck source=lib/software.sh
source "$SCRIPT_DIR/lib/software.sh"
# shellcheck source=lib/services.sh
source "$SCRIPT_DIR/lib/services.sh"
# shellcheck source=lib/security.sh
source "$SCRIPT_DIR/lib/security.sh"
# shellcheck source=lib/containers.sh
source "$SCRIPT_DIR/lib/containers.sh"
# shellcheck source=lib/user_configs.sh
source "$SCRIPT_DIR/lib/user_configs.sh"
# shellcheck source=lib/gaming.sh
source "$SCRIPT_DIR/lib/gaming.sh"

RUN_TS=$(date -u +"%Y%m%dT%H%M%SZ")
HOSTNAME_SAFE=$(hostname 2>/dev/null || uname -n)
HOSTNAME_SAFE=${HOSTNAME_SAFE//[^A-Za-z0-9._-]/_}
OUTPUT_ROOT="$ROOT_DIR/output"
QUICK_MODE=0

parse_args() {
    while (($# > 0)); do
        case $1 in
            -o|--output-root)
                if (($# < 2)); then
                    printf 'missing value for %s\n' "$1" >&2
                    return 1
                fi
                OUTPUT_ROOT=$2
                shift 2
                ;;
            --quick)
                QUICK_MODE=1
                shift
                ;;
            -h|--help)
                cat <<'EOF'
Usage: bash scripts/collect_inventory.sh [options]

Options:
  -o, --output-root DIR  Override the base output directory.
      --quick            Skip the configuration archive to speed up collection.
  -h, --help             Show this help message.
EOF
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

SNAPSHOT_DIR="$OUTPUT_ROOT/${HOSTNAME_SAFE}_${RUN_TS}"
TEXT_DIR="$SNAPSHOT_DIR/text"
CONFIG_DIR="$SNAPSHOT_DIR/configs"
WARNINGS_FILE="$SNAPSHOT_DIR/warnings.log"
MANIFEST_FILE="$SNAPSHOT_DIR/manifest.txt"

mkdir -p "$TEXT_DIR" "$CONFIG_DIR"
: > "$WARNINGS_FILE"

warn() {
    printf '%s\n' "$*" | tee -a "$WARNINGS_FILE" >&2
}

append_manifest() {
    printf '%s=%s\n' "$1" "$2" >> "$MANIFEST_FILE"
}

run_collector() {
    local name=$1
    shift

    if "$@"; then
        append_manifest "collector_${name}" "ok"
    else
        append_manifest "collector_${name}" "failed"
        warn "collector_failed=$name"
    fi
}

main() {
    local os_id="unknown"
    local os_like="unknown"
    local os_name="unknown"
    local distro_family="unknown"
    local pkg_backend="unknown"
    local init_system="unknown"
    local firewall_backend="none"
    local container_backends="none"

    detect_os_release os_id os_like os_name
    distro_family=$(infer_distro_family "$os_id" "$os_like")
    pkg_backend=$(detect_package_backend)
    init_system=$(detect_init_system)
    firewall_backend=$(detect_firewall_backend)
    container_backends=$(detect_container_backends)

    append_manifest "timestamp_utc" "$RUN_TS"
    append_manifest "snapshot_dir" "$SNAPSHOT_DIR"
    append_manifest "hostname" "$HOSTNAME_SAFE"
    append_manifest "user" "${SUDO_USER:-${USER:-unknown}}"
    append_manifest "effective_uid" "$(id -u)"
    append_manifest "quick_mode" "$QUICK_MODE"
    append_manifest "os_id" "$os_id"
    append_manifest "os_like" "$os_like"
    append_manifest "os_name" "$os_name"
    append_manifest "distro_family" "$distro_family"
    append_manifest "package_backend" "$pkg_backend"
    append_manifest "init_system" "$init_system"
    append_manifest "firewall_backend" "$firewall_backend"
    append_manifest "container_backends" "$container_backends"

    run_collector "compatibility" collect_compatibility_inventory "$TEXT_DIR/compatibility.txt"
    run_collector "system" collect_system_inventory "$TEXT_DIR/system.txt"
    run_collector "software" collect_software_inventory "$TEXT_DIR/software.txt" "$pkg_backend"
    run_collector "services" collect_services_inventory "$TEXT_DIR/services.txt" "$init_system"
    run_collector "security" collect_security_inventory "$TEXT_DIR/security.txt" "$firewall_backend"
    run_collector "containers" collect_containers_inventory "$TEXT_DIR/containers.txt" "$container_backends"
    run_collector "gaming" collect_gaming_inventory "$TEXT_DIR/gaming.txt"

    if ((QUICK_MODE == 0)); then
        run_collector "user_configs" collect_user_configs "$TEXT_DIR/user-configs.txt" "$CONFIG_DIR/configs.tar.gz"
    else
        append_manifest "collector_user_configs" "skipped_quick_mode"
    fi

    printf 'snapshot_dir=%s\n' "$SNAPSHOT_DIR"
}

main "$@"