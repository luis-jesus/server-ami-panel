#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
FAILED=0

# shellcheck source=../scripts/lib/release.sh
source "$ROOT_DIR/scripts/lib/release.sh"

assert_eq() {
    local expected=$1
    local actual=$2
    local message=$3

    if [[ $actual == "$expected" ]]; then
        printf 'PASS %s\n' "$message"
    else
        printf 'FAIL %s: expected [%s], got [%s]\n' "$message" "$expected" "$actual" >&2
        FAILED=1
    fi
}

assert_fails() {
    local message=$1
    shift

    if "$@" >/dev/null 2>&1; then
        printf 'FAIL %s: command succeeded unexpectedly\n' "$message" >&2
        FAILED=1
    else
        printf 'PASS %s\n' "$message"
    fi
}

assert_file_contains() {
    local path=$1
    local pattern=$2
    local message=$3

    if grep -Fq -- "$pattern" "$path"; then
        printf 'PASS %s\n' "$message"
    else
        printf 'FAIL %s: pattern [%s] not found in %s\n' "$message" "$pattern" "$path" >&2
        FAILED=1
    fi
}

assert_eq major "$(release_kind_for_branch 'feature-major/api-v2')" 'feature-major maps to major'
assert_eq minor "$(release_kind_for_branch 'feature/dashboard')" 'feature maps to minor'
assert_eq minor "$(release_kind_for_branch 'bugfix/cache')" 'bugfix maps to minor'
assert_eq patch "$(release_kind_for_branch 'hotfix/login')" 'hotfix maps to patch'
assert_eq minor "$(release_kind_for_branch '3-titulo-de-mercado-a-indice-y-divisas')" 'legacy branch maps to minor'
assert_fails 'unsupported branch is rejected' release_kind_for_branch 'chore/docs'

assert_eq major "$(release_highest_kind patch minor major)" 'major has highest precedence'
assert_eq minor "$(release_highest_kind patch minor patch)" 'minor has precedence over patch'
assert_eq patch "$(release_highest_kind patch)" 'patch remains patch'
assert_fails 'invalid release kind is rejected' release_highest_kind minor unknown

assert_eq v2.0.0 "$(release_next_tag v1.4.2 major)" 'major tag increments and resets'
assert_eq v1.5.0 "$(release_next_tag v1.4.2 minor)" 'minor tag increments and resets patch'
assert_eq v1.4.3 "$(release_next_tag v1.4.2 patch)" 'patch tag increments'
assert_fails 'invalid tag is rejected' release_next_tag 1.4.2 patch
assert_fails 'invalid tag kind is rejected' release_next_tag v1.4.2 unknown

assert_file_contains "$ROOT_DIR/.github/workflows/branch-policy.yml" 'feature-major/*' 'branch policy accepts major feature branches'
assert_file_contains "$ROOT_DIR/.github/workflows/branch-policy.yml" 'head_ref" == develop' 'branch policy accepts develop promotion'
assert_file_contains "$ROOT_DIR/.github/workflows/release-promotion.yml" "basehead: 'master...develop'" 'promotion compares unreleased develop changes'
assert_file_contains "$ROOT_DIR/.github/workflows/release-promotion.yml" 'pendingCommits.length < comparison.data.ahead_by' 'promotion paginates all pending commits'
assert_file_contains "$ROOT_DIR/.github/workflows/release-promotion.yml" 'draft: true' 'promotion PR is created as draft'
assert_file_contains "$ROOT_DIR/.github/workflows/release-management.yml" "git tag --points-at HEAD --list 'v*'" 'release rerun reuses a tag on HEAD'
assert_file_contains "$ROOT_DIR/.github/workflows/release-management.yml" 'does not match planned tag' 'release validates the planned tag'
assert_file_contains "$ROOT_DIR/.github/workflows/release-management.yml" "sourceBranch.startsWith('hotfix/')" 'hotfix kind comes from branch name'

if ((FAILED != 0)); then
    exit 1
fi

printf 'PASS release workflow policy\n'