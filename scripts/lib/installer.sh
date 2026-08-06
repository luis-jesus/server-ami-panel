#!/usr/bin/env bash

if [[ -n ${SERVERAM1_INSTALLER_LIB_LOADED:-} ]]; then
    return 0
fi
SERVERAM1_INSTALLER_LIB_LOADED=1

INSTALLER_LIB_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SERVERAM1_ROOT_DIR_DEFAULT=$(CDPATH='' cd -- "$INSTALLER_LIB_DIR/../.." && pwd)

# shellcheck source=common.sh
source "$INSTALLER_LIB_DIR/common.sh"

SERVERAM1_APP_NAME='Services Monitor AMI'
SERVERAM1_APP_ID='services-monitor-ami'
SERVERAM1_INSTALLER_ID='services-monitor-ami-installer'
SERVERAM1_DEFAULT_HOST='127.0.0.1'
SERVERAM1_DEFAULT_PORT='8765'

installer_init() {
    SERVERAM1_ROOT_DIR=${1:-${SERVERAM1_ROOT_DIR:-$SERVERAM1_ROOT_DIR_DEFAULT}}
    if [[ -n ${SERVERAM1_TARGET_HOME:-} ]]; then
        SERVERAM1_TARGET_HOME=$SERVERAM1_TARGET_HOME
    elif [[ -n ${SUDO_USER:-} ]]; then
        SERVERAM1_TARGET_HOME=$(resolve_target_home)
    else
        SERVERAM1_TARGET_HOME=${HOME:-$(resolve_target_home)}
    fi
    XDG_DATA_HOME=${XDG_DATA_HOME:-$SERVERAM1_TARGET_HOME/.local/share}
    XDG_STATE_HOME=${XDG_STATE_HOME:-$SERVERAM1_TARGET_HOME/.local/state}
    XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$SERVERAM1_TARGET_HOME/.config}

    SERVERAM1_INSTALL_HOME=${SERVERAM1_INSTALL_HOME:-$XDG_DATA_HOME/serveram1}
    SERVERAM1_STATE_DIR=${SERVERAM1_STATE_DIR:-$XDG_STATE_HOME/serveram1}
    SERVERAM1_CONFIG_DIR=${SERVERAM1_CONFIG_DIR:-$XDG_CONFIG_HOME/serveram1}
    SERVERAM1_BIN_DIR=${SERVERAM1_BIN_DIR:-$SERVERAM1_TARGET_HOME/.local/bin}
    SERVERAM1_DESKTOP_DIR=${SERVERAM1_DESKTOP_DIR:-$XDG_DATA_HOME/applications}
    SERVERAM1_ICON_DIR=${SERVERAM1_ICON_DIR:-$XDG_DATA_HOME/icons/hicolor/scalable/apps}

    SERVERAM1_VENV_DIR=${SERVERAM1_VENV_DIR:-$SERVERAM1_INSTALL_HOME/venv}
    SERVERAM1_METADATA_FILE=${SERVERAM1_METADATA_FILE:-$SERVERAM1_INSTALL_HOME/install.env}
    SERVERAM1_LOG_FILE=${SERVERAM1_LOG_FILE:-$SERVERAM1_STATE_DIR/install.log}
    SERVERAM1_PANEL_LOG_FILE=${SERVERAM1_PANEL_LOG_FILE:-$SERVERAM1_STATE_DIR/panel.log}
    SERVERAM1_APP_DESKTOP_FILE=${SERVERAM1_APP_DESKTOP_FILE:-$SERVERAM1_DESKTOP_DIR/${SERVERAM1_APP_ID}.desktop}
    SERVERAM1_INSTALLER_DESKTOP_FILE=${SERVERAM1_INSTALLER_DESKTOP_FILE:-$SERVERAM1_DESKTOP_DIR/${SERVERAM1_INSTALLER_ID}.desktop}
    SERVERAM1_APP_SHIM=${SERVERAM1_APP_SHIM:-$SERVERAM1_BIN_DIR/${SERVERAM1_APP_ID}}
    SERVERAM1_INSTALLER_SHIM=${SERVERAM1_INSTALLER_SHIM:-$SERVERAM1_BIN_DIR/${SERVERAM1_INSTALLER_ID}}
    SERVERAM1_ICON_SOURCE=${SERVERAM1_ICON_SOURCE:-$SERVERAM1_ROOT_DIR/panel/static/services-monitor-ami.svg}
    SERVERAM1_ICON_TARGET=${SERVERAM1_ICON_TARGET:-$SERVERAM1_ICON_DIR/${SERVERAM1_APP_ID}.svg}
    SERVERAM1_PYTHON_BIN=${SERVERAM1_PYTHON_BIN:-$SERVERAM1_VENV_DIR/bin/python}
    SERVERAM1_INSTALLER_COLOR_MODE=${SERVERAM1_INSTALLER_COLOR_MODE:-auto}

    installer_load_metadata
    installer_setup_theme
    installer_update_terminal_size
}

installer_load_metadata() {
    if [[ -f ${SERVERAM1_METADATA_FILE:-} ]]; then
        # shellcheck disable=SC1090
        source "$SERVERAM1_METADATA_FILE"
    fi
}

installer_is_registered() {
    [[ -f "$SERVERAM1_METADATA_FILE" && ${INSTALLATION_REGISTERED:-0} == 1 ]]
}

installer_ensure_base_dirs() {
    mkdir -p "$SERVERAM1_INSTALL_HOME" "$SERVERAM1_STATE_DIR" "$SERVERAM1_CONFIG_DIR" "$SERVERAM1_BIN_DIR" "$SERVERAM1_DESKTOP_DIR" "$SERVERAM1_ICON_DIR"
}

installer_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

installer_log() {
    local level=$1
    shift
    installer_ensure_base_dirs
    printf '%s [%s] %s\n' "$(installer_timestamp)" "$level" "$*" >> "$SERVERAM1_LOG_FILE"
}

installer_setup_theme() {
    INSTALLER_RESET=''
    INSTALLER_RED=''
    INSTALLER_GREEN=''
    INSTALLER_BLUE=''
    INSTALLER_BLACK_BG=''
    INSTALLER_RED_BG=''
    INSTALLER_CLEAR=''

    if installer_supports_color; then
        INSTALLER_RESET=$'\033[0m'
        INSTALLER_RED=$'\033[31m'
        INSTALLER_GREEN=$'\033[32m'
        INSTALLER_BLUE=$'\033[34m'
        INSTALLER_BLACK_BG=$'\033[40m'
        INSTALLER_RED_BG=$'\033[41;97m'
        INSTALLER_CLEAR=$'\033[2J\033[H'
    fi
}

installer_supports_color() {
    case ${SERVERAM1_INSTALLER_COLOR_MODE:-auto} in
        always)
            return 0
            ;;
        never)
            return 1
            ;;
    esac

    if [[ ! -t 1 ]]; then
        return 1
    fi

    if command_exists tput && [[ $(tput colors 2>/dev/null || printf '0') -ge 8 ]]; then
        return 0
    fi

    return 1
}

installer_update_terminal_size() {
    local cols lines

    cols=${COLUMNS:-0}
    lines=${LINES:-0}

    if command_exists tput; then
        cols=$(tput cols 2>/dev/null || printf '%s' "$cols")
        lines=$(tput lines 2>/dev/null || printf '%s' "$lines")
    fi

    if [[ -z $cols || $cols -lt 60 ]]; then
        cols=100
    fi

    if [[ -z $lines || $lines -lt 20 ]]; then
        lines=28
    fi

    SERVERAM1_TERM_WIDTH=$cols
    SERVERAM1_TERM_HEIGHT=$lines
}

installer_repeat_char() {
    local char=$1
    local count=$2
    local out=''
    local index

    for ((index = 0; index < count; index += 1)); do
        out+=$char
    done

    printf '%s' "$out"
}

installer_center_text() {
    local text=$1
    local width=$2
    local text_length=${#text}
    local padding

    if ((text_length >= width)); then
        printf '%s\n' "$text"
        return 0
    fi

    padding=$(((width - text_length) / 2))
    printf '%*s%s\n' "$padding" '' "$text"
}

installer_wrap_line() {
    local prefix=$1
    local text=$2
    local wrap_width=$3

    printf '%s\n' "$text" | fold -s -w "$wrap_width" | while IFS= read -r line; do
        printf '%s%s\n' "$prefix" "$line"
    done
}

installer_available_commands() {
    if installer_is_registered; then
        printf '%s\n' reinstall update uninstall log exit
    else
        printf '%s\n' install log exit
    fi
}

installer_command_description() {
    case $1 in
        install)
            printf '%s\n' 'instala la aplicacion y prepara el entorno virtual(install)'
            ;;
        reinstall)
            printf '%s\n' 'reinstala la aplicacion y regenera el entorno(reinstall)'
            ;;
        update)
            printf '%s\n' 'actualiza la instalacion desde el repositorio(update)'
            ;;
        uninstall)
            printf '%s\n' 'desinstala la aplicacion(uninstall)'
            ;;
        log)
            printf '%s\n' 'muestra el historial del instalador(log)'
            ;;
        exit)
            printf '%s\n' 'sale del instalador(exit)'
            ;;
        run)
            printf '%s\n' 'ejecuta la aplicacion web instalada(run)'
            ;;
    esac
}

installer_is_valid_menu_command() {
    local command_name=$1

    while IFS= read -r allowed; do
        if [[ $allowed == "$command_name" ]]; then
            return 0
        fi
    done < <(installer_available_commands)

    return 1
}

installer_apply_black_background() {
    if [[ -n $INSTALLER_BLACK_BG ]]; then
        printf '%s' "$INSTALLER_BLACK_BG"
    fi
}

installer_render_menu() {
    local command_name
    local wrap_width
    local prompt_commands=''

    installer_update_terminal_size
    wrap_width=$((SERVERAM1_TERM_WIDTH - 6))
    if ((wrap_width < 40)); then
        wrap_width=40
    fi

    printf '%s' "$INSTALLER_CLEAR"
    installer_apply_black_background

    printf '%s%s%s\n' "$INSTALLER_RED" "$(installer_repeat_char '*' "$SERVERAM1_TERM_WIDTH")" "$INSTALLER_RESET"
    printf '%s' "$INSTALLER_GREEN"
    installer_center_text "$SERVERAM1_APP_NAME" "$SERVERAM1_TERM_WIDTH"
    printf '%s' "$INSTALLER_RESET"
    printf '%s%s%s\n\n' "$INSTALLER_RED" "$(installer_repeat_char '*' "$SERVERAM1_TERM_WIDTH")" "$INSTALLER_RESET"

    while IFS= read -r command_name; do
        local line_text="$command_name = $(installer_command_description "$command_name")"
        printf '%s' "$INSTALLER_BLUE"
        installer_wrap_line '  ' "$line_text" "$wrap_width"
        printf '%s' "$INSTALLER_RESET"

        if [[ -n $prompt_commands ]]; then
            prompt_commands+=', '
        fi
        prompt_commands+=$command_name
    done < <(installer_available_commands)

    printf '\n'
    printf '%s%s%s\n' "$INSTALLER_RED" "$(installer_repeat_char '*' "$SERVERAM1_TERM_WIDTH")" "$INSTALLER_RESET"
    printf 'Escribe un comando [%s]: ' "$prompt_commands"
}

installer_show_invalid_command() {
    local command_name=$1
    installer_update_terminal_size
    printf '%s' "$INSTALLER_CLEAR"
    if [[ -n $INSTALLER_RED_BG ]]; then
        printf '%s' "$INSTALLER_RED_BG"
    fi
    printf '%s\n' "$(installer_repeat_char ' ' "$SERVERAM1_TERM_WIDTH")"
    installer_center_text "comando invalido: $command_name" "$SERVERAM1_TERM_WIDTH"
    printf '%s\n' "$(installer_repeat_char ' ' "$SERVERAM1_TERM_WIDTH")"
    printf '%s' "$INSTALLER_RESET"
    printf 'Comandos validos: '
    paste -sd ', ' < <(installer_available_commands)
    printf '\n'
    installer_log ERROR "comando invalido: $command_name"
}

installer_show_log() {
    installer_ensure_base_dirs
    if [[ ! -f $SERVERAM1_LOG_FILE ]]; then
        printf 'No hay registros del instalador disponibles.\n'
        return 0
    fi

    cat "$SERVERAM1_LOG_FILE"
}

installer_progress() {
    local current=$1
    local total=$2
    local label=$3
    local percent fill_width filled empty

    if ((total <= 0)); then
        total=1
    fi

    percent=$((current * 100 / total))
    fill_width=$((SERVERAM1_TERM_WIDTH - 30))
    if ((fill_width < 10)); then
        fill_width=10
    fi
    filled=$((percent * fill_width / 100))
    empty=$((fill_width - filled))

    printf '\r%s[%s%s] %3d%% %s%s' \
        "$INSTALLER_BLUE" \
        "$(installer_repeat_char '#' "$filled")" \
        "$(installer_repeat_char '.' "$empty")" \
        "$percent" \
        "$label" \
        "$INSTALLER_RESET"
}

installer_finish_progress() {
    printf '\n'
}

installer_write_metadata() {
    installer_ensure_base_dirs
    cat > "$SERVERAM1_METADATA_FILE" <<EOF
INSTALLATION_REGISTERED=1
ROOT_DIR=$SERVERAM1_ROOT_DIR
VENV_DIR=$SERVERAM1_VENV_DIR
APP_DESKTOP_FILE=$SERVERAM1_APP_DESKTOP_FILE
INSTALLER_DESKTOP_FILE=$SERVERAM1_INSTALLER_DESKTOP_FILE
APP_SHIM=$SERVERAM1_APP_SHIM
INSTALLER_SHIM=$SERVERAM1_INSTALLER_SHIM
LOG_FILE=$SERVERAM1_LOG_FILE
INSTALLED_AT=$(installer_timestamp)
EOF
}

installer_verify_python() {
    if ! command_exists python3; then
        installer_log ERROR 'python3 no esta disponible'
        printf 'python3 es obligatorio para instalar Services Monitor AMI.\n' >&2
        return 1
    fi
    return 0
}

installer_prepare_venv() {
    rm -rf "$SERVERAM1_VENV_DIR"
    python3 -m venv "$SERVERAM1_VENV_DIR"
    "$SERVERAM1_VENV_DIR/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
    "$SERVERAM1_VENV_DIR/bin/python" -m pip --disable-pip-version-check install -r "$SERVERAM1_ROOT_DIR/requirements.txt" >/dev/null
}

installer_write_shim() {
    local target=$1
    local command_path=$2

    cat > "$target" <<EOF
#!/usr/bin/env bash
exec bash "$command_path" "\$@"
EOF
    chmod +x "$target"
}

installer_write_app_desktop() {
    cat > "$SERVERAM1_APP_DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Services Monitor AMI
Exec=$SERVERAM1_APP_SHIM
Icon=$SERVERAM1_ICON_TARGET
Terminal=false
Categories=System;Monitor;
StartupNotify=true
EOF
}

installer_write_installer_desktop() {
    cat > "$SERVERAM1_INSTALLER_DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Services Monitor AMI Installer
Exec=$SERVERAM1_INSTALLER_SHIM
Icon=$SERVERAM1_ICON_TARGET
Terminal=false
Categories=System;Settings;
StartupNotify=true
EOF
}

installer_install_artifacts() {
    cp "$SERVERAM1_ICON_SOURCE" "$SERVERAM1_ICON_TARGET"
    installer_write_shim "$SERVERAM1_APP_SHIM" "$SERVERAM1_ROOT_DIR/scripts/launch_app.sh"
    installer_write_shim "$SERVERAM1_INSTALLER_SHIM" "$SERVERAM1_ROOT_DIR/scripts/launch_installer.sh"
    installer_write_app_desktop
    installer_write_installer_desktop
}

installer_install() {
    local total=5
    installer_init "$SERVERAM1_ROOT_DIR"
    installer_ensure_base_dirs
    installer_log INFO 'inicio de instalacion'
    installer_progress 1 "$total" 'Preparando directorios'
    installer_ensure_base_dirs

    installer_progress 2 "$total" 'Validando Python'
    installer_verify_python || return 1

    installer_progress 3 "$total" 'Creando entorno virtual'
    installer_prepare_venv || return 1

    installer_progress 4 "$total" 'Instalando accesos directos'
    installer_install_artifacts || return 1

    installer_progress 5 "$total" 'Registrando instalacion'
    installer_write_metadata
    installer_finish_progress
    installer_log INFO 'instalacion completada'
    printf 'Instalacion completada.\n'
}

installer_reinstall() {
    installer_log INFO 'inicio de reinstalacion'
    installer_install
}

installer_run_update_command() {
    if [[ -n ${SERVERAM1_UPDATE_COMMAND:-} ]]; then
        sh -c "$SERVERAM1_UPDATE_COMMAND"
        return 0
    fi

    git -C "$SERVERAM1_ROOT_DIR" pull --ff-only
}

installer_update() {
    local total=4
    installer_init "$SERVERAM1_ROOT_DIR"
    installer_ensure_base_dirs
    installer_log INFO 'inicio de actualizacion'

    installer_progress 1 "$total" 'Actualizando repositorio'
    installer_run_update_command || return 1

    installer_progress 2 "$total" 'Refrescando entorno virtual'
    if [[ ! -x $SERVERAM1_PYTHON_BIN ]]; then
        installer_prepare_venv || return 1
    else
        "$SERVERAM1_PYTHON_BIN" -m pip --disable-pip-version-check install -r "$SERVERAM1_ROOT_DIR/requirements.txt" >/dev/null || return 1
    fi

    installer_progress 3 "$total" 'Regenerando artefactos'
    installer_install_artifacts || return 1

    installer_progress 4 "$total" 'Actualizando registro'
    installer_write_metadata
    installer_finish_progress
    installer_log INFO 'actualizacion completada'
    printf 'Actualizacion completada.\n'
}

installer_uninstall() {
    local total=4
    installer_init "$SERVERAM1_ROOT_DIR"
    installer_log INFO 'inicio de desinstalacion'

    installer_progress 1 "$total" 'Eliminando accesos directos'
    rm -f "$SERVERAM1_APP_DESKTOP_FILE" "$SERVERAM1_INSTALLER_DESKTOP_FILE" "$SERVERAM1_APP_SHIM" "$SERVERAM1_INSTALLER_SHIM" "$SERVERAM1_ICON_TARGET"

    installer_progress 2 "$total" 'Eliminando entorno virtual'
    rm -rf "$SERVERAM1_VENV_DIR"

    installer_progress 3 "$total" 'Limpiando metadatos'
    rm -f "$SERVERAM1_METADATA_FILE"

    installer_progress 4 "$total" 'Finalizando'
    installer_finish_progress
    installer_log INFO 'desinstalacion completada'
    printf 'Desinstalacion completada.\n'
}

installer_healthcheck() {
    local python_bin=$1
    local url="http://${SERVERAM1_DEFAULT_HOST}:${SERVERAM1_DEFAULT_PORT}/api/status"

    "$python_bin" - <<PY >/dev/null 2>&1
from urllib.request import urlopen

urlopen(${url@Q}, timeout=1)
PY
}

installer_wait_for_panel() {
    local python_bin=$1
    local attempt

    for attempt in $(seq 1 40); do
        if installer_healthcheck "$python_bin"; then
            return 0
        fi
        sleep 0.25
    done

    return 1
}

installer_browser_candidates() {
    printf '%s\n' google-chrome-stable google-chrome chromium-browser chromium brave-browser microsoft-edge firefox xdg-open
}

installer_open_url() {
    local url=$1
    local browser

    while IFS= read -r browser; do
        if ! command_exists "$browser"; then
            continue
        fi

        case $browser in
            google-chrome-stable|google-chrome|chromium-browser|chromium|brave-browser|microsoft-edge)
                "$browser" --new-window --app="$url" >/dev/null 2>&1 &
                return 0
                ;;
            firefox)
                "$browser" --new-window "$url" >/dev/null 2>&1 &
                return 0
                ;;
            xdg-open)
                "$browser" "$url" >/dev/null 2>&1 &
                return 0
                ;;
        esac
    done < <(installer_browser_candidates)

    return 1
}

installer_run_application() {
    local panel_python
    installer_init "$SERVERAM1_ROOT_DIR"

    if [[ -x $SERVERAM1_PYTHON_BIN ]]; then
        panel_python=$SERVERAM1_PYTHON_BIN
    else
        panel_python=python3
    fi

    installer_ensure_base_dirs
    if ! installer_healthcheck "$panel_python"; then
        SERVERAM1_PYTHON="$panel_python" bash "$SERVERAM1_ROOT_DIR/scripts/run_panel.sh" --host "$SERVERAM1_DEFAULT_HOST" --port "$SERVERAM1_DEFAULT_PORT" >> "$SERVERAM1_PANEL_LOG_FILE" 2>&1 &
        installer_wait_for_panel "$panel_python" || {
            printf 'No fue posible iniciar el panel web.\n' >&2
            return 1
        }
    fi

    installer_open_url "http://${SERVERAM1_DEFAULT_HOST}:${SERVERAM1_DEFAULT_PORT}/" || {
        printf 'No fue posible abrir el navegador.\n' >&2
        return 1
    }

    installer_log INFO 'aplicacion ejecutada'
}

installer_launch_terminal() {
    local command_string=$1
    local title=${2:-$SERVERAM1_APP_NAME}
    local terminal_bin
    local terminal_pid=''

    terminal_bin=${SERVERAM1_TERMINAL_BIN:-}
    if [[ -z $terminal_bin ]]; then
        if command_exists x-terminal-emulator; then
            terminal_bin=x-terminal-emulator
        elif command_exists xterm; then
            terminal_bin=xterm
        else
            printf 'No se encontro un emulador de terminal compatible.\n' >&2
            return 1
        fi
    fi

    case $terminal_bin in
        xterm)
            "$terminal_bin" -T "$title" -e sh -lc "$command_string" &
            terminal_pid=$!
            ;;
        *)
            "$terminal_bin" -e sh -lc "$command_string" &
            terminal_pid=$!
            ;;
    esac

    installer_try_maximize_window "$title"
    disown 2>/dev/null || true
    [[ -n $terminal_pid ]]
    return 0
}

installer_try_maximize_window() {
    local title=$1
    local attempt

    if ! command_exists wmctrl; then
        return 0
    fi

    for attempt in $(seq 1 30); do
        if wmctrl -r "$title" -b add,maximized_vert,maximized_horz >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    return 0
}

installer_menu_loop() {
    local input_command
    local prompt_commands

    installer_init "$SERVERAM1_ROOT_DIR"

    while true; do
        installer_render_menu
        prompt_commands=$(paste -sd ', ' < <(installer_available_commands))
        read -r input_command
        input_command=${input_command//[$'\t\r\n']/}

        if [[ -z $input_command ]]; then
            continue
        fi

        if ! installer_is_valid_menu_command "$input_command"; then
            installer_show_invalid_command "$input_command"
            continue
        fi

        case $input_command in
            install)
                installer_install
                ;;
            reinstall)
                installer_reinstall
                ;;
            update)
                installer_update
                ;;
            uninstall)
                installer_uninstall
                ;;
            log)
                installer_show_log
                ;;
            exit)
                installer_log INFO 'salida del instalador'
                break
                ;;
        esac

        printf '\nPresiona Enter para continuar...'
        read -r _
    done
}