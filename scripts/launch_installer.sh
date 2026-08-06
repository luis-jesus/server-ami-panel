#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck source=lib/installer.sh
source "$ROOT_DIR/scripts/lib/installer.sh"

installer_init "$ROOT_DIR"
installer_launch_terminal "printf '\033]0;%s\007' '${SERVERAM1_APP_NAME}'; exec '$ROOT_DIR/install.sh'" "$SERVERAM1_APP_NAME"