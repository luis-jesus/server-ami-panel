#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
E2E_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/serveram1-e2e.XXXXXX")

cleanup() {
    rm -rf "$E2E_ROOT"
}

trap cleanup EXIT

ORIGIN_REPO="$E2E_ROOT/origin.git"
SEED_REPO="$E2E_ROOT/seed"
WORKTREE="$E2E_ROOT/worktree"
PUBLISHER="$E2E_ROOT/publisher"
USER_HOME="$E2E_ROOT/home"
INSTALL_LOG_CAPTURE="$E2E_ROOT/install.log.txt"
EXIT_CAPTURE="$E2E_ROOT/exit.log.txt"
MENU_CAPTURE="$E2E_ROOT/menu.log.txt"
UPDATE_LOG_CAPTURE="$E2E_ROOT/update.log.txt"
INSTALLER_LOG_CAPTURE="$E2E_ROOT/installer.log.txt"

XDG_DATA_HOME="$USER_HOME/.local/share"
XDG_STATE_HOME="$USER_HOME/.local/state"
XDG_CONFIG_HOME="$USER_HOME/.config"

fail() {
    printf 'E2E FAIL %s\n' "$1" >&2
    exit 1
}

assert_file_contains() {
    local path=$1
    local pattern=$2
    local message=$3

    if grep -Eq "$pattern" "$path"; then
        printf 'E2E PASS %s\n' "$message"
    else
        fail "$message: pattern [$pattern] not found in $path"
    fi
}

assert_exists() {
    local path=$1
    local message=$2

    if [[ -e "$path" ]]; then
        printf 'E2E PASS %s\n' "$message"
    else
        fail "$message: missing $path"
    fi
}

assert_missing() {
    local path=$1
    local message=$2

    if [[ ! -e "$path" ]]; then
        printf 'E2E PASS %s\n' "$message"
    else
        fail "$message: path still exists $path"
    fi
}

run_installer() {
    HOME="$USER_HOME" \
    XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$WORKTREE/install.sh" "$@"
}

printf 'E2E INFO preparando repositorio temporal\n'
mkdir -p "$SEED_REPO"
tar \
    --exclude='.git' \
    --exclude='output' \
    --exclude='update-reports' \
    --exclude='tests/tmp' \
    -C "$ROOT_DIR" -cf - . | tar -C "$SEED_REPO" -xf - || fail 'copy workspace into seed repo'
git -C "$SEED_REPO" init >/dev/null 2>&1 || fail 'init seed repo'
git -C "$SEED_REPO" config user.name 'ServerAM1 E2E'
git -C "$SEED_REPO" config user.email 'serveram1-e2e@example.com'
git -C "$SEED_REPO" add . >/dev/null 2>&1 || fail 'stage seed repo'
git -C "$SEED_REPO" commit -m 'Seed repository snapshot' >/dev/null 2>&1 || fail 'commit seed repo'
git clone --bare "$SEED_REPO" "$ORIGIN_REPO" >/dev/null 2>&1 || fail 'clone bare seed repo'
git clone "$ORIGIN_REPO" "$WORKTREE" >/dev/null 2>&1 || fail 'clone worktree'
git clone "$ORIGIN_REPO" "$PUBLISHER" >/dev/null 2>&1 || fail 'clone publisher'
mkdir -p "$USER_HOME"

printf 'E2E INFO verificando menu inicial\n'
run_installer print-menu > "$MENU_CAPTURE"
assert_file_contains "$MENU_CAPTURE" 'install = instala la aplicacion y prepara el entorno' 'initial menu shows install prefix'
assert_file_contains "$MENU_CAPTURE" 'virtual\(install\)' 'initial menu shows install suffix'
assert_file_contains "$MENU_CAPTURE" 'log = muestra el historial del instalador\(log\)' 'initial menu shows log'
assert_file_contains "$MENU_CAPTURE" 'exit = sale del instalador\(exit\)' 'initial menu shows exit'

printf 'E2E INFO instalando aplicacion\n'
run_installer install > "$INSTALL_LOG_CAPTURE"
assert_file_contains "$INSTALL_LOG_CAPTURE" 'Instalacion completada\.' 'installer completes install'
assert_exists "$XDG_DATA_HOME/serveram1/venv" 'installer created venv'
assert_exists "$XDG_DATA_HOME/applications/services-monitor-ami.desktop" 'installer created app desktop entry'
assert_exists "$USER_HOME/.local/bin/services-monitor-ami" 'installer created app shim'

printf 'E2E INFO verificando menu posterior a instalacion\n'
run_installer print-menu > "$MENU_CAPTURE"
assert_file_contains "$MENU_CAPTURE" 'reinstall = reinstala la aplicacion y regenera el' 'installed menu shows reinstall prefix'
assert_file_contains "$MENU_CAPTURE" 'entorno\(reinstall\)' 'installed menu shows reinstall suffix'
assert_file_contains "$MENU_CAPTURE" 'update = actualiza la instalacion desde el' 'installed menu shows update prefix'
assert_file_contains "$MENU_CAPTURE" 'repositorio\(update\)' 'installed menu shows update suffix'
assert_file_contains "$MENU_CAPTURE" 'uninstall = desinstala la aplicacion\(uninstall\)' 'installed menu shows uninstall'

printf 'E2E INFO publicando cambio remoto para update\n'
git -C "$PUBLISHER" config user.name 'ServerAM1 E2E'
git -C "$PUBLISHER" config user.email 'serveram1-e2e@example.com'
printf '\nE2E update marker\n' >> "$PUBLISHER/README.md"
git -C "$PUBLISHER" add README.md
git -C "$PUBLISHER" commit -m 'E2E update marker' >/dev/null 2>&1 || fail 'commit update marker'
git -C "$PUBLISHER" push origin HEAD >/dev/null 2>&1 || fail 'push update marker'

printf 'E2E INFO ejecutando update\n'
run_installer update > "$UPDATE_LOG_CAPTURE"
assert_file_contains "$UPDATE_LOG_CAPTURE" 'Actualizacion completada\.' 'installer completes update'
assert_file_contains "$WORKTREE/README.md" 'E2E update marker' 'update pulled new commit'

printf 'E2E INFO revisando logs\n'
run_installer log > "$INSTALLER_LOG_CAPTURE"
assert_file_contains "$INSTALLER_LOG_CAPTURE" 'instalacion completada' 'installer log contains install entry'
assert_file_contains "$INSTALLER_LOG_CAPTURE" 'actualizacion completada' 'installer log contains update entry'

printf 'E2E INFO probando salida del instalador\n'
printf 'exit\n' | HOME="$USER_HOME" \
    XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    SERVERAM1_INSTALLER_COLOR_MODE=never \
    bash "$WORKTREE/install.sh" > "$EXIT_CAPTURE"
assert_file_contains "$EXIT_CAPTURE" 'Escribe un comando \[reinstall, update, uninstall, log, exit\]:' 'menu loop accepts exit prompt'

printf 'E2E INFO ejecutando uninstall\n'
run_installer uninstall > /dev/null
assert_missing "$XDG_DATA_HOME/serveram1/install.env" 'uninstall removed metadata'
assert_missing "$XDG_DATA_HOME/serveram1/venv" 'uninstall removed venv'
assert_missing "$XDG_DATA_HOME/applications/services-monitor-ami.desktop" 'uninstall removed app desktop entry'
assert_missing "$USER_HOME/.local/bin/services-monitor-ami" 'uninstall removed app shim'

printf 'E2E PASS installer lifecycle completed\n'