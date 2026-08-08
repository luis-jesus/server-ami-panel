#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

RANGE=''
ALLOW_MERGE_COMMITS=1
ALLOWED_PATTERN='^(fix|feature|hotfix|chore)\([[:alnum:]][[:alnum:]._/-]*\)[[:space:]].+'

print_usage() {
    cat <<'EOF'
Usage: bash scripts/check_commit_messages.sh [options]

Validate commit subject naming.

Options:
      --range REV_RANGE    Validate all commit subjects in a git revision range.
      --no-allow-merges    Treat merge commits as invalid instead of skipping them.
  -h, --help              Show this help message.

Valid commit subject format:
  fix(scope) Descripcion de cambios
  feature(scope) Descripcion de cambios
  hotfix(scope) Descripcion de cambios
  chore(scope) Descripcion de cambios

Notes:
  - Branch prefixes and commit prefixes are related but not identical.
  - `bugfix/*` branches should normally contain commits starting with `fix(...)`.
EOF
}

parse_args() {
    while (($# > 0)); do
        case $1 in
            --range)
                if (($# < 2)); then
                    printf 'missing value for %s\n' "$1" >&2
                    return 1
                fi
                RANGE=$2
                shift 2
                ;;
            --no-allow-merges)
                ALLOW_MERGE_COMMITS=0
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

default_range() {
    if git -C "$ROOT_DIR" rev-parse --verify HEAD~1 >/dev/null 2>&1; then
        printf '%s\n' 'HEAD~1..HEAD'
    else
        printf '%s\n' 'HEAD'
    fi
}

is_skippable_commit() {
    local subject=$1

    if ((ALLOW_MERGE_COMMITS == 1)) && [[ $subject == Merge\ * ]]; then
        return 0
    fi

    if [[ $subject == Revert\ * ]]; then
        return 0
    fi

    return 1
}

collect_subjects() {
    local rev_range=$1
    git -C "$ROOT_DIR" log --format='%s' "$rev_range"
}

validate_subjects() {
    local rev_range=$1
    local subject
    local -a invalid=()
    local found_any=0

    while IFS= read -r subject; do
        [[ -z $subject ]] && continue
        found_any=1

        if is_skippable_commit "$subject"; then
            continue
        fi

        if [[ ! $subject =~ $ALLOWED_PATTERN ]]; then
            invalid+=("$subject")
        fi
    done < <(collect_subjects "$rev_range")

    if ((found_any == 0)); then
        printf 'commit_message_check=skipped_no_commits\n'
        return 0
    fi

    if ((${#invalid[@]} == 0)); then
        printf 'commit_message_check=passed\n'
        return 0
    fi

    printf 'commit_message_check=failed\n' >&2
    printf 'allowed_format=%s\n' "$ALLOWED_PATTERN" >&2
    printf 'invalid_commit_subjects:\n' >&2
    printf ' - %s\n' "${invalid[@]}" >&2
    return 1
}

main() {
    parse_args "$@"

    if [[ -z $RANGE ]]; then
        RANGE=$(default_range)
    fi

    validate_subjects "$RANGE"
}

main "$@"