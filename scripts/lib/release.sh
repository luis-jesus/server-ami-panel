#!/usr/bin/env bash

if [[ -n ${SERVERAM1_RELEASE_LIB_LOADED:-} ]]; then
    return 0
fi
SERVERAM1_RELEASE_LIB_LOADED=1

release_kind_for_branch() {
    case $1 in
        feature-major/*)
            printf '%s\n' major
            ;;
        feature/*|bugfix/*|3-titulo-de-mercado-a-indice-y-divisas)
            printf '%s\n' minor
            ;;
        hotfix/*)
            printf '%s\n' patch
            ;;
        *)
            return 1
            ;;
    esac
}

release_kind_rank() {
    case $1 in
        major)
            printf '%s\n' 3
            ;;
        minor)
            printf '%s\n' 2
            ;;
        patch)
            printf '%s\n' 1
            ;;
        *)
            return 1
            ;;
    esac
}

release_highest_kind() {
    local highest=''
    local highest_rank=0
    local kind
    local rank

    for kind in "$@"; do
        rank=$(release_kind_rank "$kind") || return 1
        if ((rank > highest_rank)); then
            highest=$kind
            highest_rank=$rank
        fi
    done

    [[ -n $highest ]] || return 1
    printf '%s\n' "$highest"
}

release_is_semver_tag() {
    [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

release_next_tag() {
    local current_tag=$1
    local release_kind=$2
    local major
    local minor
    local patch

    release_is_semver_tag "$current_tag" || return 1
    release_kind_rank "$release_kind" >/dev/null || return 1

    IFS=. read -r major minor patch <<< "${current_tag#v}"
    case $release_kind in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
    esac

    printf 'v%s.%s.%s\n' "$major" "$minor" "$patch"
}