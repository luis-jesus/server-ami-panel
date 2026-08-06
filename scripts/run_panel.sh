#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
PYTHON_BIN=${SERVERAM1_PYTHON:-python3}

if [[ $PYTHON_BIN == */* ]]; then
    if [[ ! -x $PYTHON_BIN ]]; then
        printf '%s is required to run the monitoring panel\n' "$PYTHON_BIN" >&2
        exit 1
    fi
elif ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    printf '%s is required to run the monitoring panel\n' "$PYTHON_BIN" >&2
    exit 1
fi

exec "$PYTHON_BIN" "$ROOT_DIR/panel/server.py" "$@"