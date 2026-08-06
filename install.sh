#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# shellcheck source=scripts/lib/installer.sh
source "$ROOT_DIR/scripts/lib/installer.sh"

print_usage() {
    cat <<'EOF'
Usage: bash install.sh [command]

Commands:
  install       Install the application for the current user.
  reinstall     Rebuild the managed runtime and desktop integration.
  update        Update the repository checkout and refresh the installation.
  uninstall     Remove the managed installation artifacts.
  log           Show the installer log.
  run           Launch the web application.
  print-menu    Render the current interactive menu.
  --help        Show this help text.

Run without arguments to open the interactive installer menu.
EOF
}

main() {
    installer_init "$ROOT_DIR"

    case ${1:-menu} in
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
        run)
            installer_run_application
            ;;
        print-menu)
            installer_render_menu
            printf '\n'
            ;;
        --help|-h|help)
            print_usage
            ;;
        menu)
            installer_menu_loop
            ;;
        *)
            installer_show_invalid_command "$1"
            exit 1
            ;;
    esac
}

main "$@"