#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck source=lib/installer.sh
source "$ROOT_DIR/scripts/lib/installer.sh"

installer_init "$ROOT_DIR"
installer_run_application