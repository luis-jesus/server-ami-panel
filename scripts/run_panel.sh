#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

if ! command -v python3 >/dev/null 2>&1; then
    printf 'python3 is required to run the monitoring panel\n' >&2
    exit 1
fi

exec python3 "$ROOT_DIR/panel/server.py" "$@"