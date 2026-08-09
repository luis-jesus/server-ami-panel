#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/inventory-tests.XXXXXX")
FAILED=0
TEST_COUNT=0

cleanup() {
    rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

# shellcheck source=../scripts/lib/common.sh
source "$ROOT_DIR/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/detect.sh
source "$ROOT_DIR/scripts/lib/detect.sh"

pass() {
    printf 'PASS %s\n' "$1"
}

fail() {
    printf 'FAIL %s\n' "$1" >&2
    FAILED=1
}

assert_eq() {
    local expected=$1
    local actual=$2
    local message=$3

    if [[ "$expected" == "$actual" ]]; then
        pass "$message"
    else
        fail "$message: expected [$expected] got [$actual]"
    fi
}

assert_file_exists() {
    local path=$1
    local message=$2

    if [[ -f "$path" ]]; then
        pass "$message"
    else
        fail "$message: missing file $path"
    fi
}

assert_dir_exists() {
    local path=$1
    local message=$2

    if [[ -d "$path" ]]; then
        pass "$message"
    else
        fail "$message: missing directory $path"
    fi
}

assert_file_contains() {
    local path=$1
    local pattern=$2
    local message=$3

    if grep -Eq "$pattern" "$path"; then
        pass "$message"
    else
        fail "$message: pattern [$pattern] not found in $path"
    fi
}

assert_path_missing() {
    local path=$1
    local message=$2

    if [[ ! -e "$path" ]]; then
        pass "$message"
    else
        fail "$message: path still exists $path"
    fi
}

assert_valid_json() {
    local path=$1
    local message=$2

    if command_exists python3; then
        if python3 -m json.tool "$path" >/dev/null 2>&1; then
            pass "$message"
        else
            fail "$message: invalid json in $path"
        fi
    else
        pass "$message (skipped: python3 unavailable)"
    fi
}

run_test() {
    local name=$1
    shift

    TEST_COUNT=$((TEST_COUNT + 1))
    printf 'TEST %s\n' "$name"
    "$@"
}

test_shell_syntax() {
    local scripts=("$ROOT_DIR/install.sh")

    while IFS= read -r script_path; do
        scripts+=("$script_path")
    done < <(find "$ROOT_DIR/scripts" -type f -name '*.sh' | sort)

    if ((${#scripts[@]} == 0)); then
        fail "shell syntax: no scripts found"
        return 0
    fi

    if bash -n "${scripts[@]}"; then
        pass "shell syntax"
    else
        fail "shell syntax"
    fi
}

test_infer_distro_family() {
    assert_eq "debian" "$(infer_distro_family ubuntu debian)" "infer distro family debian"
    assert_eq "suse" "$(infer_distro_family opensuse suse)" "infer distro family suse"
    assert_eq "void" "$(infer_distro_family void unknown)" "infer distro family void"
}

test_detect_package_backend_prefers_zypper() {
    local actual

    actual=$( (
        command_exists() {
            case $1 in
                zypper|rpm) return 0 ;;
                *) return 1 ;;
            esac
        }
        detect_package_backend
    ) )

    assert_eq "zypper" "$actual" "package backend prefers zypper"
}

test_detect_firewall_backend_prefers_managed_firewall() {
    local ufw_actual
    local firewalld_actual

    ufw_actual=$( (
        command_exists() {
            case $1 in
                ufw|nft|iptables) return 0 ;;
                *) return 1 ;;
            esac
        }
        detect_firewall_backend
    ) )

    firewalld_actual=$( (
        command_exists() {
            case $1 in
                firewall-cmd|nft) return 0 ;;
                *) return 1 ;;
            esac
        }
        detect_firewall_backend
    ) )

    assert_eq "ufw" "$ufw_actual" "firewall backend prefers ufw"
    assert_eq "firewalld" "$firewalld_actual" "firewall backend prefers firewalld"
}

test_detect_container_backends() {
    local actual

    actual=$( (
        command_exists() {
            case $1 in
                docker|virsh|podman) return 0 ;;
                *) return 1 ;;
            esac
        }
        detect_container_backends
    ) )

    assert_eq "docker,podman,libvirt" "$actual" "container backend detection"
}

test_quick_inventory_smoke() {
    local output_root="$TMP_ROOT/output"
    local command_output
    local snapshot_dir

    command_output=$(bash "$ROOT_DIR/scripts/collect_inventory.sh" --quick --output-root "$output_root")
    snapshot_dir=$(printf '%s\n' "$command_output" | awk -F= '/^snapshot_dir=/{print $2}')

    if [[ -z "$snapshot_dir" ]]; then
        fail "quick inventory smoke: snapshot_dir not reported"
        return 0
    fi

    assert_dir_exists "$snapshot_dir" "quick inventory creates snapshot directory"
    assert_file_exists "$snapshot_dir/manifest.txt" "quick inventory creates manifest"
    assert_file_exists "$snapshot_dir/text/compatibility.txt" "quick inventory creates compatibility report"
    assert_file_exists "$snapshot_dir/text/system.txt" "quick inventory creates system report"
    assert_file_exists "$snapshot_dir/text/software.txt" "quick inventory creates software report"
    assert_file_contains "$snapshot_dir/manifest.txt" '^quick_mode=1$' "quick inventory manifest marks quick mode"
    assert_file_contains "$snapshot_dir/manifest.txt" '^collector_user_configs=skipped_quick_mode$' "quick inventory skips config archive"
}

test_update_packages_help() {
    local help_output

    help_output=$(bash "$ROOT_DIR/scripts/update_packages.sh" --help)

    if printf '%s\n' "$help_output" | grep -Eq '^Usage: bash scripts/update_packages.sh'; then
        pass "update packages help"
    else
        fail "update packages help"
    fi
}

test_install_requirements_help() {
    local help_output

    help_output=$(bash "$ROOT_DIR/scripts/install_requirements.sh" --help)

    if printf '%s\n' "$help_output" | grep -Eq '^Usage: bash scripts/install_requirements.sh'; then
        pass "install requirements help"
    else
        fail "install requirements help"
    fi
}

test_install_requirements_print() {
    local command_output

    command_output=$(bash "$ROOT_DIR/scripts/install_requirements.sh" --print)

    if printf '%s\n' "$command_output" | grep -Eq '^detected_package_backend='; then
        pass "install requirements detects package backend"
    else
        fail "install requirements detects package backend"
    fi

    if printf '%s\n' "$command_output" | grep -Eq '^install_command='; then
        pass "install requirements prints install command"
    else
        fail "install requirements prints install command"
    fi

    if [[ $(detect_package_backend) == 'dpkg' ]]; then
        if printf '%s\n' "$command_output" | grep -Eq 'python3-venv'; then
            pass "install requirements includes python3-venv for dpkg"
        else
            fail "install requirements includes python3-venv for dpkg"
        fi
    fi
}

test_installer_help() {
    local help_output

    help_output=$(bash "$ROOT_DIR/install.sh" --help)

    if printf '%s\n' "$help_output" | grep -Eq '^Usage: bash install.sh'; then
        pass "installer help"
    else
        fail "installer help"
    fi
}

test_installer_menu_render() {
    local home_root="$TMP_ROOT/installer-menu-home"
    local menu_file="$TMP_ROOT/installer-menu.txt"
    local color_file="$TMP_ROOT/installer-menu-color.txt"

    mkdir -p "$home_root"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" print-menu > "$menu_file"

    assert_file_contains "$menu_file" 'Services Monitor AMI' "installer menu shows title"
    assert_file_contains "$menu_file" 'install = instala la aplicacion y prepara el entorno' "installer menu shows install option prefix"
    assert_file_contains "$menu_file" 'virtual\(install\)' "installer menu shows install option suffix"
    assert_file_contains "$menu_file" 'log = muestra el historial del instalador\(log\)' "installer menu shows log option"
    assert_file_contains "$menu_file" 'exit = sale del instalador\(exit\)' "installer menu shows exit option"
    assert_file_contains "$menu_file" 'Escribe un comando \[install, log, exit\]:' "installer menu shows command prompt"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=always \
    bash "$ROOT_DIR/install.sh" print-menu > "$color_file"

    assert_file_contains "$color_file" $'\033\[32m' "installer menu title uses green ANSI"
    assert_file_contains "$color_file" $'\033\[31m' "installer menu separators use red ANSI"
    assert_file_contains "$color_file" $'\033\[34m' "installer menu options use blue ANSI"
}

test_installer_metadata_round_trip() {
    local home_root="$TMP_ROOT/installer metadata home"
    local metadata_file="$home_root/.local/share/serveram1/install.env"
    local metadata_output="$TMP_ROOT/installer-metadata-output.txt"
    local metadata_errors="$TMP_ROOT/installer-metadata-errors.txt"
    local legacy_errors="$TMP_ROOT/installer-legacy-errors.txt"

    mkdir -p "$(dirname -- "$metadata_file")"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    bash -c '
        source "$1"
        installer_init "$2"
        installer_write_metadata
        unset ROOT_DIR
        installer_load_metadata
        printf "%s\n" "$ROOT_DIR"
    ' _ "$ROOT_DIR/scripts/lib/installer.sh" "$ROOT_DIR" > "$metadata_output" 2> "$metadata_errors"

    assert_eq "$ROOT_DIR" "$(cat -- "$metadata_output")" "installer metadata preserves paths with spaces"
    if [[ ! -s "$metadata_errors" ]]; then
        pass "installer metadata reload has no shell errors"
    else
        fail "installer metadata reload emitted shell errors"
    fi

    printf 'INSTALLATION_REGISTERED=1\nROOT_DIR=%s\n' "$ROOT_DIR" > "$metadata_file"
    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" print-menu >/dev/null 2> "$legacy_errors"

    if [[ ! -s "$legacy_errors" ]]; then
        pass "installer hides errors from legacy metadata"
    else
        fail "installer emitted errors from legacy metadata"
    fi
}

test_installer_install_cycle() {
    local home_root="$TMP_ROOT/installer-cycle-home"
    local install_output="$TMP_ROOT/installer-install.txt"
    local menu_file="$TMP_ROOT/installer-installed-menu.txt"
    local log_file="$TMP_ROOT/installer-log.txt"

    mkdir -p "$home_root"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" install > "$install_output"

    assert_dir_exists "$home_root/.local/share/serveram1/venv" "installer creates venv"
    assert_file_exists "$home_root/.local/share/applications/services-monitor-ami.desktop" "installer creates app desktop entry"
    assert_file_exists "$home_root/.local/share/applications/services-monitor-ami-installer.desktop" "installer creates installer desktop entry"
    assert_file_exists "$home_root/.local/bin/services-monitor-ami" "installer creates app shim"
    assert_file_exists "$home_root/.local/bin/services-monitor-ami-installer" "installer creates installer shim"
    assert_file_exists "$home_root/.local/share/serveram1/install.env" "installer writes metadata"
    assert_file_contains "$home_root/.local/bin/services-monitor-ami" '^exec bash ' "installer app shim invokes bash"
    assert_file_contains "$home_root/.local/bin/services-monitor-ami-installer" '^exec bash ' "installer installer shim invokes bash"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" print-menu > "$menu_file"

    assert_file_contains "$menu_file" 'reinstall = reinstala la aplicacion y regenera el' "installer installed menu shows reinstall prefix"
    assert_file_contains "$menu_file" 'entorno\(reinstall\)' "installer installed menu shows reinstall suffix"
    assert_file_contains "$menu_file" 'update = actualiza la instalacion desde el' "installer installed menu shows update prefix"
    assert_file_contains "$menu_file" 'repositorio\(update\)' "installer installed menu shows update suffix"
    assert_file_contains "$menu_file" 'uninstall = desinstala la aplicacion\(uninstall\)' "installer installed menu shows uninstall"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" log > "$log_file"

    assert_file_contains "$log_file" 'instalacion completada' "installer log records completion"

    HOME="$home_root" \
    XDG_DATA_HOME="$home_root/.local/share" \
    XDG_STATE_HOME="$home_root/.local/state" \
    XDG_CONFIG_HOME="$home_root/.config" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$ROOT_DIR/install.sh" uninstall >/dev/null

    assert_path_missing "$home_root/.local/share/serveram1/install.env" "installer removes metadata on uninstall"
    assert_path_missing "$home_root/.local/share/serveram1/venv" "installer removes venv on uninstall"
}

test_installer_e2e_temp_clone() {
    if bash "$ROOT_DIR/tests/e2e_installer.sh"; then
        pass "installer e2e temp clone"
    else
        fail "installer e2e temp clone"
    fi
}

test_panel_help() {
    local help_output

    help_output=$(bash "$ROOT_DIR/scripts/run_panel.sh" --help)

    if printf '%s\n' "$help_output" | grep -Eq 'Execution and monitoring panel for ServerAM1'; then
        pass "panel help"
    else
        fail "panel help"
    fi
}

test_panel_python_syntax() {
    if command_exists python3; then
        if python3 -m py_compile "$ROOT_DIR/panel/server.py"; then
            pass "panel python syntax"
        else
            fail "panel python syntax"
        fi
    else
        fail "panel python syntax: python3 unavailable"
    fi
}

test_panel_services_payload() {
    local payload_file="$TMP_ROOT/panel-services.json"

    if ! command_exists python3; then
        fail "panel services payload: python3 unavailable"
        return 0
    fi

    if python3 - <<'PY' > "$payload_file"
import json
from panel.server import collect_services_status

print(json.dumps(collect_services_status()))
PY
    then
        pass "panel services payload generation"
    else
        fail "panel services payload generation"
        return 0
    fi

    assert_valid_json "$payload_file" "panel services payload valid json"
    assert_file_contains "$payload_file" '"primary_ip"' "panel services payload includes primary ip"
    assert_file_contains "$payload_file" '"id": "ssh"' "panel services payload includes ssh"
    assert_file_contains "$payload_file" '"docker_socket"' "panel services payload includes docker socket capability"
    assert_file_contains "$payload_file" '"docker_cli"' "panel services payload includes docker cli capability"
    assert_file_contains "$payload_file" '"panel_user"' "panel services payload includes docker socket access metadata"
    assert_file_contains "$payload_file" '"id": "firewall"' "panel services payload includes firewall"
    assert_file_contains "$payload_file" '"listening_ports"' "panel services payload includes listening ports"
}

test_panel_service_logs() {
    local payload_file="$TMP_ROOT/panel-service-logs.json"

    if ! command_exists python3; then
        fail "panel service logs: python3 unavailable"
        return 0
    fi

    if python3 - <<'PY' > "$payload_file"
import json
from panel.server import collect_service_logs

print(json.dumps(collect_service_logs("ssh")))
PY
    then
        pass "panel service logs generation"
    else
        fail "panel service logs generation"
        return 0
    fi

    assert_valid_json "$payload_file" "panel service logs valid json"
    assert_file_contains "$payload_file" '"service_id": "ssh"' "panel service logs includes ssh id"
    assert_file_contains "$payload_file" '"status":' "panel service logs includes status"
}

test_update_packages_check_smoke() {
    local output_root="$TMP_ROOT/package-updates"
    local command_output
    local report_dir

    command_output=$(bash "$ROOT_DIR/scripts/update_packages.sh" --check --no-refresh --output-root "$output_root")
    report_dir=$(printf '%s\n' "$command_output" | awk -F= '/^report_dir=/{print $2}')

    if [[ -z "$report_dir" ]]; then
        fail "update packages smoke: report_dir not reported"
        return 0
    fi

    assert_dir_exists "$report_dir" "update packages creates report directory"
    assert_file_exists "$report_dir/manifest.txt" "update packages creates manifest"
    assert_file_exists "$report_dir/plan.txt" "update packages creates plan report"
    assert_file_exists "$report_dir/security.txt" "update packages creates security report"
    assert_file_exists "$report_dir/source-trust.txt" "update packages creates source trust report"
    assert_file_exists "$report_dir/report.json" "update packages creates json report"
    assert_file_exists "$report_dir/packages-before.tsv" "update packages creates package snapshot"
    assert_file_exists "$report_dir/summary.txt" "update packages creates summary"
    assert_file_contains "$report_dir/manifest.txt" '^mode=check$' "update packages manifest marks check mode"
    assert_file_contains "$report_dir/manifest.txt" '^refresh_status=disabled$' "update packages honors no-refresh"
    assert_file_contains "$report_dir/manifest.txt" '^trust_status=' "update packages records trust status"
    assert_file_contains "$report_dir/manifest.txt" '^trust_allowlist_file=' "update packages records trust allowlist file"
    assert_file_contains "$report_dir/report.json" '"manifest"' "update packages json includes manifest"
    assert_file_contains "$report_dir/report.json" '"trust"' "update packages json includes trust block"
    assert_file_contains "$report_dir/report.json" '"security"' "update packages json includes security block"
    assert_file_contains "$report_dir/report.json" '"detected_sources"' "update packages json includes detected trust sources"
    assert_file_contains "$report_dir/report.json" '"sections"' "update packages json includes parsed report sections"
    assert_valid_json "$report_dir/report.json" "update packages json is valid"
}

main() {
    run_test "shell syntax" test_shell_syntax
    run_test "infer distro family" test_infer_distro_family
    run_test "package backend preference" test_detect_package_backend_prefers_zypper
    run_test "firewall backend preference" test_detect_firewall_backend_prefers_managed_firewall
    run_test "container backend detection" test_detect_container_backends
    run_test "quick inventory smoke" test_quick_inventory_smoke
    run_test "update packages help" test_update_packages_help
    run_test "install requirements help" test_install_requirements_help
    run_test "install requirements print" test_install_requirements_print
    run_test "installer help" test_installer_help
    run_test "installer menu render" test_installer_menu_render
    run_test "installer metadata round trip" test_installer_metadata_round_trip
    run_test "installer install cycle" test_installer_install_cycle
    run_test "installer e2e temp clone" test_installer_e2e_temp_clone
    run_test "panel help" test_panel_help
    run_test "panel python syntax" test_panel_python_syntax
    run_test "panel services payload" test_panel_services_payload
    run_test "panel service logs" test_panel_service_logs
    run_test "update packages smoke" test_update_packages_check_smoke

    printf 'Executed %s tests\n' "$TEST_COUNT"

    if ((FAILED != 0)); then
        exit 1
    fi
}

main "$@"