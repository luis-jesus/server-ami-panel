#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

ALLOW_DIRTY=0
SKIP_TESTS=0
CI_MODE=0

print_usage() {
    cat <<'EOF'
Usage: bash scripts/check_release.sh [options]

Validate that the repository is ready for a release.

Options:
      --allow-dirty       Do not fail on a dirty worktree.
      --skip-tests        Skip bash tests/run_tests.sh.
      --ci                CI-friendly mode; keeps the same checks but prints stable text.
  -h, --help             Show this help message.

Notes:
    - Runtime-generated cache files should live under ignored paths such as tmp/.
  - The latest tag must follow vX.Y.Z semver.
EOF
}

parse_args() {
    while (($# > 0)); do
        case $1 in
            --allow-dirty)
                ALLOW_DIRTY=1
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=1
                shift
                ;;
            --ci)
                CI_MODE=1
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

normalize_status_path() {
    local raw_line=$1
    local path=${raw_line:3}

    if [[ $path == *' -> '* ]]; then
        path=${path##* -> }
    fi

    printf '%s\n' "$path"
}

check_worktree_clean() {
    local raw_line
    local path
    local -a blocking=()

    while IFS= read -r raw_line; do
        [[ -z $raw_line ]] && continue
        path=$(normalize_status_path "$raw_line")
        blocking+=("$raw_line")
    done < <(git -C "$ROOT_DIR" status --porcelain)

    if ((${#blocking[@]} == 0)); then
        printf 'release_check_worktree=clean\n'
        return 0
    fi

    if ((ALLOW_DIRTY == 1)); then
        printf 'release_check_worktree=warning_allow_dirty\n'
        printf '%s\n' "${blocking[@]}"
        return 0
    fi

    printf 'release_check_worktree=dirty\n' >&2
    printf '%s\n' "${blocking[@]}" >&2
    return 1
}

check_latest_tag() {
    local latest_tag

    latest_tag=$(git -C "$ROOT_DIR" tag --list 'v*' | sort -V | tail -n 1 || true)
    if [[ -z $latest_tag ]]; then
        printf 'release_check_latest_tag=missing\n' >&2
        return 1
    fi

    if [[ ! $latest_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf 'release_check_latest_tag=invalid:%s\n' "$latest_tag" >&2
        return 1
    fi

    printf 'release_check_latest_tag=%s\n' "$latest_tag"
}

run_tests() {
    if ((SKIP_TESTS == 1)); then
        printf 'release_check_tests=skipped\n'
        return 0
    fi

    printf 'release_check_tests=running\n'
    bash "$ROOT_DIR/tests/run_tests.sh"
    printf 'release_check_tests=passed\n'
}

main() {
    parse_args "$@"

    if ((CI_MODE == 1)); then
        printf 'release_check_mode=ci\n'
    else
        printf 'release_check_mode=local\n'
    fi

    check_worktree_clean
    check_latest_tag
    run_tests
    printf 'release_check=passed\n'
}

main "$@"