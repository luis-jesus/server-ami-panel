#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$SCRIPT_DIR/lib/detect.sh"

RUN_TS=$(date -u +"%Y%m%dT%H%M%SZ")
HOSTNAME_SAFE=$(hostname 2>/dev/null || uname -n)
HOSTNAME_SAFE=${HOSTNAME_SAFE//[^A-Za-z0-9._-]/_}
OUTPUT_ROOT="$ROOT_DIR/update-reports"
CONFIG_DIR="$ROOT_DIR/config"
TRUST_ALLOWLIST_FILE="$CONFIG_DIR/trusted-sources.txt"
MODE="check"
AUTO_YES=0
REFRESH_METADATA=1
ALLOW_UNTRUSTED_SOURCES=0

print_usage() {
    cat <<'EOF'
Usage: bash scripts/update_packages.sh [options]

Options:
      --check             Generate update and security reports without changing packages.
      --apply             Apply package updates and record what changed.
      --no-refresh        Skip metadata refresh before planning or applying updates.
    --allow-untrusted-sources
                  Do not block apply mode when the trust report finds
                  insecure or manually reviewed sources.
  -y, --yes               Use non-interactive confirmation flags where supported.
  -o, --output-root DIR   Override the base output directory for reports.
  -h, --help              Show this help message.

Notes:
  - Security classification depends on the package backend. Some distros expose
    native security advisories; others only allow a limited report.
  - In apply mode the script uses root directly, or sudo if it is available.
EOF
}

parse_args() {
    while (($# > 0)); do
        case $1 in
            --check)
                MODE="check"
                shift
                ;;
            --apply)
                MODE="apply"
                shift
                ;;
            --no-refresh)
                REFRESH_METADATA=0
                shift
                ;;
            --allow-untrusted-sources)
                ALLOW_UNTRUSTED_SOURCES=1
                shift
                ;;
            -y|--yes)
                AUTO_YES=1
                shift
                ;;
            -o|--output-root)
                if (($# < 2)); then
                    printf 'missing value for %s\n' "$1" >&2
                    return 1
                fi
                OUTPUT_ROOT=$2
                shift 2
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

parse_args "$@"

REPORT_DIR="$OUTPUT_ROOT/${HOSTNAME_SAFE}_${RUN_TS}"
MANIFEST_FILE="$REPORT_DIR/manifest.txt"
SUMMARY_FILE="$REPORT_DIR/summary.txt"
JSON_REPORT_FILE="$REPORT_DIR/report.json"
WARNINGS_FILE="$REPORT_DIR/warnings.log"
OPERATIONS_LOG="$REPORT_DIR/operations.log"
PLAN_FILE="$REPORT_DIR/plan.txt"
SECURITY_FILE="$REPORT_DIR/security.txt"
TRUST_FILE="$REPORT_DIR/source-trust.txt"
BEFORE_FILE="$REPORT_DIR/packages-before.tsv"
AFTER_FILE="$REPORT_DIR/packages-after.tsv"
PLANNED_INSTALLED_FILE="$REPORT_DIR/planned-installed.tsv"
PLANNED_UPDATED_FILE="$REPORT_DIR/planned-updated.tsv"
PLANNED_REMOVED_FILE="$REPORT_DIR/planned-removed.tsv"
INSTALLED_FILE="$REPORT_DIR/changes-installed.tsv"
UPDATED_FILE="$REPORT_DIR/changes-updated.tsv"
REMOVED_FILE="$REPORT_DIR/changes-removed.tsv"
REFRESH_FILE="$REPORT_DIR/refresh.txt"

mkdir -p "$REPORT_DIR"
: > "$WARNINGS_FILE"
: > "$OPERATIONS_LOG"

warn() {
    printf '%s\n' "$*" | tee -a "$WARNINGS_FILE" >&2
}

append_manifest() {
    printf '%s=%s\n' "$1" "$2" >> "$MANIFEST_FILE"
}

write_note_file() {
    local file_path=$1
    shift
    printf '%s\n' "$@" > "$file_path"
}

count_lines() {
    local file_path=$1

    if [[ -s "$file_path" ]]; then
        awk 'END { print NR }' "$file_path"
    else
        printf '0\n'
    fi
}

json_escape() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

json_write_object_from_kv_file() {
    local file_path=$1
    local indent=$2
    local first=1
    local key
    local value

    printf '{\n'
    if [[ -f "$file_path" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            if ((first == 0)); then
                printf ',\n'
            fi
            first=0
            printf '%s  "%s": "%s"' "$indent" "$(json_escape "$key")" "$(json_escape "$value")"
        done < "$file_path"
    fi
    printf '\n%s}' "$indent"
}

json_write_lines_array() {
    local file_path=$1
    local indent=$2
    local first=1
    local line

    printf '['
    if [[ -f "$file_path" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if ((first == 1)); then
                printf '\n'
            else
                printf ',\n'
            fi
            first=0
            printf '%s  "%s"' "$indent" "$(json_escape "$line")"
        done < "$file_path"
    fi

    if ((first == 1)); then
        printf ']'
    else
        printf '\n%s]' "$indent"
    fi
}

count_trust_classification() {
    local classification=$1

    awk -F '\t' -v prefix="$classification" '$1 == prefix { count++ } END { print count + 0 }' "$TRUST_FILE" 2>/dev/null
}

read_backend_value() {
    local file_path=$1

    awk -F '=' '/^backend=/{print $2; exit}' "$file_path" 2>/dev/null
}

list_report_sections() {
    local file_path=$1

    awk '/^## /{sub(/^## /, ""); print}' "$file_path" 2>/dev/null
}

extract_report_section() {
    local file_path=$1
    local section_name=$2

    awk -v target="$section_name" '
        $0 == "## " target {
            in_section = 1
            next
        }
        /^## / && in_section {
            exit
        }
        in_section {
            print
        }
    ' "$file_path" 2>/dev/null
}

extract_report_body_lines() {
    local file_path=$1

    awk '/^backend=/{next} NF {print}' "$file_path" 2>/dev/null
}

json_write_file_lines_array() {
    local file_path=$1
    local indent=$2
    local first=1
    local line

    printf '['
    if [[ -f "$file_path" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if ((first == 1)); then
                printf '\n'
            else
                printf ',\n'
            fi
            first=0
            printf '%s  "%s"' "$indent" "$(json_escape "$line")"
        done < "$file_path"
    fi

    if ((first == 1)); then
        printf ']'
    else
        printf '\n%s]' "$indent"
    fi
}

json_write_section_array() {
    local file_path=$1
    local section_name=$2
    local indent=$3
    local tmp_file

    tmp_file=$(mktemp)
    extract_report_section "$file_path" "$section_name" > "$tmp_file"
    json_write_file_lines_array "$tmp_file" "$indent"
    rm -f "$tmp_file"
}

json_write_report_sections_object() {
    local file_path=$1
    local indent=$2
    local first=1
    local section_name
    local tmp_file

    printf '{'

    if [[ -f "$file_path" ]] && grep -q '^## ' "$file_path" 2>/dev/null; then
        while IFS= read -r section_name; do
            [[ -z "$section_name" ]] && continue
            if ((first == 1)); then
                printf '\n'
            else
                printf ',\n'
            fi
            first=0
            printf '%s  "%s": ' "$indent" "$(json_escape "$section_name")"
            json_write_section_array "$file_path" "$section_name" "$indent  "
        done < <(list_report_sections "$file_path")
    elif [[ -f "$file_path" ]]; then
        tmp_file=$(mktemp)
        extract_report_body_lines "$file_path" > "$tmp_file"
        printf '\n%s  "content": ' "$indent"
        json_write_file_lines_array "$tmp_file" "$indent  "
        rm -f "$tmp_file"
        first=0
    fi

    if ((first == 1)); then
        printf '}'
    else
        printf '\n%s}' "$indent"
    fi
}

json_write_trust_sources_array() {
    local file_path=$1
    local indent=$2
    local first=1
    local classification
    local source_name
    local tmp_file

    tmp_file=$(mktemp)
    extract_report_section "$file_path" 'origin-classification' > "$tmp_file"

    printf '['
    if [[ -s "$tmp_file" ]]; then
        while IFS=$'\t' read -r classification source_name; do
            [[ -z "$classification" || -z "$source_name" || "$classification" == 'none' ]] && continue
            if ((first == 1)); then
                printf '\n'
            else
                printf ',\n'
            fi
            first=0
            printf '%s  {"classification": "%s", "source": "%s"}' \
                "$indent" \
                "$(json_escape "$classification")" \
                "$(json_escape "$source_name")"
        done < "$tmp_file"
    fi
    rm -f "$tmp_file"

    if ((first == 1)); then
        printf ']'
    else
        printf '\n%s]' "$indent"
    fi
}

json_write_trust_source_names_array() {
    local file_path=$1
    local wanted_classification=$2
    local indent=$3
    local first=1
    local classification
    local source_name
    local tmp_file

    tmp_file=$(mktemp)
    extract_report_section "$file_path" 'origin-classification' > "$tmp_file"

    printf '['
    if [[ -s "$tmp_file" ]]; then
        while IFS=$'\t' read -r classification source_name; do
            [[ "$classification" != "$wanted_classification" || -z "$source_name" ]] && continue
            if ((first == 1)); then
                printf '\n'
            else
                printf ',\n'
            fi
            first=0
            printf '%s  "%s"' "$indent" "$(json_escape "$source_name")"
        done < "$tmp_file"
    fi
    rm -f "$tmp_file"

    if ((first == 1)); then
        printf ']'
    else
        printf '\n%s]' "$indent"
    fi
}

run_capture() {
    local output_file=$1
    shift

    printf '$ %s\n' "$*" >> "$OPERATIONS_LOG"
    "$@" > "$output_file" 2>> "$OPERATIONS_LOG"
}

run_capture_allow_codes() {
    local output_file=$1
    local allowed_codes=$2
    shift 2
    local exit_code

    printf '$ %s\n' "$*" >> "$OPERATIONS_LOG"
    if "$@" > "$output_file" 2>> "$OPERATIONS_LOG"; then
        return 0
    fi

    exit_code=$?
    printf 'exit_code=%s\n' "$exit_code" >> "$output_file"
    case ",$allowed_codes," in
        *",$exit_code,"*) return 0 ;;
        *) return "$exit_code" ;;
    esac
}

run_as_privileged() {
    if ((EUID == 0)); then
        "$@"
        return $?
    fi

    if command_exists sudo; then
        sudo "$@"
        return $?
    fi

    return 127
}

refresh_requires_privilege() {
    case $1 in
        dpkg|apk|xbps|portage|rpm|zypper|pacman)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_allowlisted_source() {
    local backend=$1
    local source_name=$2

    if [[ ! -f "$TRUST_ALLOWLIST_FILE" ]]; then
        return 1
    fi

    grep -Eq "^${backend}[[:space:]]+${source_name}([[:space:]]|$)" "$TRUST_ALLOWLIST_FILE"
}

is_official_apt_origin() {
    case $1 in
        deb.debian.org|security.debian.org|archive.ubuntu.com|security.ubuntu.com|ports.ubuntu.com)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

collect_dpkg_trust_report() {
    local output_file=$1
    local trust_status='trusted'
    local insecure_entries
    local signature_warnings
    local origin_name
    local found_origin=0
    local review_count=0
    local tmp_origins

    tmp_origins=$(mktemp)

    {
        printf 'backend=dpkg\n\n'
        printf '## source-files\n'
        grep -RhnE '^[[:space:]]*deb(-src)?[[:space:]]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || printf 'none\n'
        printf '\n## deb822-sources\n'
        grep -RhnE '^[[:space:]]*(Types|URIs|Suites|Components|Signed-By):' /etc/apt/sources.list.d 2>/dev/null || printf 'none\n'
        printf '\n## allowlist-file\n%s\n' "$TRUST_ALLOWLIST_FILE"
        printf '\n## insecure-overrides\n'
    } > "$output_file"

    insecure_entries=$(grep -RhnE '\[.*trusted=yes.*\]' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true)
    if [[ -n "$insecure_entries" ]]; then
        printf '%s\n' "$insecure_entries" >> "$output_file"
        trust_status='failed'
    else
        printf 'none\n' >> "$output_file"
    fi

    {
        printf '\n## apt-policy-origins\n'
        apt-cache policy 2>/dev/null
        printf '\n## origin-classification\n'
    } >> "$output_file"

    apt-cache policy 2>/dev/null | awk '/^[[:space:]]+origin / {print $2}' | LC_ALL=C sort -u > "$tmp_origins"
    while IFS= read -r origin_name; do
        [[ -z "$origin_name" ]] && continue
        found_origin=1
        if is_official_apt_origin "$origin_name"; then
            printf 'official\t%s\n' "$origin_name" >> "$output_file"
        elif is_allowlisted_source 'dpkg' "$origin_name"; then
            printf 'allowed\t%s\n' "$origin_name" >> "$output_file"
        else
            printf 'review\t%s\n' "$origin_name" >> "$output_file"
            review_count=$((review_count + 1))
        fi
    done < "$tmp_origins"
    rm -f "$tmp_origins"

    if ((found_origin == 0)); then
        printf 'none\n' >> "$output_file"
    fi

    {
        printf '\n## signature-warnings\n'
    } >> "$output_file"

    signature_warnings=$(grep -Ei 'NO_PUBKEY|EXPKEYSIG|BADSIG|repository .* is not signed|GPG error|signature verification failed' "$REFRESH_FILE" 2>/dev/null || true)
    if [[ -n "$signature_warnings" ]]; then
        printf '%s\n' "$signature_warnings" >> "$output_file"
        trust_status='failed'
    else
        printf 'none\n' >> "$output_file"
    fi

    if [[ "$trust_status" != 'failed' ]] && ((review_count > 0)); then
        trust_status='review'
    fi

    printf '%s\n' "$trust_status"
}

collect_rpm_family_trust_report() {
    local backend=$1
    local output_file=$2
    local trust_status='trusted'
    local insecure_entries

    {
        printf 'backend=%s\n\n' "$backend"
        printf '## allowlist-file\n%s\n\n' "$TRUST_ALLOWLIST_FILE"
        printf '## repo-files\n'
        grep -RhnE '^(\[|name=|baseurl=|metalink=|mirrorlist=|enabled=|gpgcheck=|repo_gpgcheck=)' /etc/yum.repos.d /etc/zypp/repos.d 2>/dev/null || printf 'none\n'
        printf '\n## insecure-gpg-settings\n'
    } > "$output_file"

    insecure_entries=$(grep -RhnE '^(gpgcheck|repo_gpgcheck)=0' /etc/yum.repos.d /etc/zypp/repos.d 2>/dev/null || true)
    if [[ -n "$insecure_entries" ]]; then
        printf '%s\n' "$insecure_entries" >> "$output_file"
        trust_status='failed'
    else
        printf 'none\n' >> "$output_file"
    fi

    printf '\n## repo-list\n' >> "$output_file"
    if [[ "$backend" == 'zypper' ]]; then
        zypper repos --details 2>/dev/null >> "$output_file" || printf 'unavailable\n' >> "$output_file"
    elif command_exists dnf; then
        dnf repolist --all 2>/dev/null >> "$output_file" || printf 'unavailable\n' >> "$output_file"
    elif command_exists yum; then
        yum repolist all 2>/dev/null >> "$output_file" || printf 'unavailable\n' >> "$output_file"
    else
        printf 'unavailable\n' >> "$output_file"
    fi

    printf '%s\n' "$trust_status"
}

collect_pacman_trust_report() {
    local output_file=$1
    local trust_status='trusted'
    local insecure_entries

    {
        printf 'backend=pacman\n\n'
        printf '## allowlist-file\n%s\n\n' "$TRUST_ALLOWLIST_FILE"
        printf '## pacman-conf\n'
        if command_exists pacman-conf; then
            pacman-conf 2>/dev/null
        else
            cat /etc/pacman.conf 2>/dev/null || printf 'unavailable\n'
        fi
        printf '\n## insecure-signature-settings\n'
    } > "$output_file"

    insecure_entries=$(grep -RhnE '^[[:space:]]*SigLevel[[:space:]]*=[[:space:]]*(Never|Optional TrustAll)' /etc/pacman.conf /etc/pacman.d 2>/dev/null || true)
    if [[ -n "$insecure_entries" ]]; then
        printf '%s\n' "$insecure_entries" >> "$output_file"
        trust_status='failed'
    else
        printf 'none\n' >> "$output_file"
    fi

    printf '%s\n' "$trust_status"
}

collect_apk_trust_report() {
    local output_file=$1
    local trust_status='trusted'
    local key_count=0

    {
        printf 'backend=apk\n\n'
        printf '## allowlist-file\n%s\n\n' "$TRUST_ALLOWLIST_FILE"
        printf '## repositories\n'
        cat /etc/apk/repositories 2>/dev/null || printf 'unavailable\n'
        printf '\n## trusted-keys\n'
        if [[ -d /etc/apk/keys ]]; then
            find /etc/apk/keys -maxdepth 1 -type f | LC_ALL=C sort
        else
            printf 'none\n'
        fi
    } > "$output_file"

    if [[ -d /etc/apk/keys ]]; then
        key_count=$(find /etc/apk/keys -maxdepth 1 -type f | wc -l | tr -d ' ')
    fi

    if [[ "$key_count" == '0' ]]; then
        trust_status='failed'
    fi

    printf '%s\n' "$trust_status"
}

collect_generic_trust_report() {
    local backend=$1
    local output_file=$2

    write_note_file "$output_file" \
        "backend=$backend" \
        "allowlist_file=$TRUST_ALLOWLIST_FILE" \
        '' \
        'Native source trust verification is limited for this backend in the current script.' \
        'Review repository configuration and the distribution advisory process before applying updates.'
    printf '%s\n' 'limited'
}

collect_source_trust_report() {
    local backend=$1
    local output_file=$2

    case $backend in
        dpkg)
            collect_dpkg_trust_report "$output_file"
            ;;
        rpm|zypper)
            collect_rpm_family_trust_report "$backend" "$output_file"
            ;;
        pacman)
            collect_pacman_trust_report "$output_file"
            ;;
        apk)
            collect_apk_trust_report "$output_file"
            ;;
        xbps|portage|nix)
            collect_generic_trust_report "$backend" "$output_file"
            ;;
        *)
            collect_generic_trust_report "$backend" "$output_file"
            ;;
    esac
}

should_block_apply_for_trust() {
    local trust_status=$1

    if ((ALLOW_UNTRUSTED_SOURCES == 1)); then
        return 1
    fi

    case $trust_status in
        failed)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

list_installed_packages() {
    local backend=$1
    local output_file=$2

    case $backend in
        dpkg)
            dpkg-query -W -f='${binary:Package}\t${Version}\n' | LC_ALL=C sort > "$output_file"
            ;;
        rpm|zypper)
            rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | LC_ALL=C sort > "$output_file"
            ;;
        pacman)
            pacman -Q | LC_ALL=C sort > "$output_file"
            ;;
        apk)
            apk list --installed 2>/dev/null | awk 'NR > 1 {print $1}' | LC_ALL=C sort > "$output_file"
            ;;
        xbps)
            xbps-query -l | awk '{print $2}' | LC_ALL=C sort > "$output_file"
            ;;
        portage)
            qlist -Iv | LC_ALL=C sort > "$output_file"
            ;;
        nix)
            if command_exists nix; then
                nix profile list 2>/dev/null | awk 'NR > 1 {print $3 "\t" $4}' | LC_ALL=C sort > "$output_file"
            elif command_exists nix-env; then
                nix-env -q 2>/dev/null | LC_ALL=C sort > "$output_file"
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

parse_dpkg_plan() {
    local plan_file=$1

    awk '
        /^Inst / {
            package_name=$2
            old_version=""
            new_version=""

            if ($3 ~ /^\[/) {
                old_version=$3
                gsub(/^[[]|[]]$/, "", old_version)
            }

            if (match($0, /\(([^ )]+)/)) {
                new_version=substr($0, RSTART + 1, RLENGTH - 1)
            }

            if (old_version != "") {
                printf "%s\t%s\t%s\n", package_name, old_version, new_version
            } else {
                printf "%s\t%s\n", package_name, new_version
            }
        }
    ' "$plan_file" > "$PLANNED_UPDATED_FILE.tmp"

    awk -F'\t' 'NF == 2 { print }' "$PLANNED_UPDATED_FILE.tmp" | LC_ALL=C sort > "$PLANNED_INSTALLED_FILE"
    awk -F'\t' 'NF == 3 { print }' "$PLANNED_UPDATED_FILE.tmp" | LC_ALL=C sort > "$PLANNED_UPDATED_FILE"
    rm -f "$PLANNED_UPDATED_FILE.tmp"

    awk '
        /^Remv / {
            package_name=$2
            old_version=$3
            gsub(/^[[]|[]]$/, "", old_version)
            printf "%s\t%s\n", package_name, old_version
        }
    ' "$plan_file" | LC_ALL=C sort > "$PLANNED_REMOVED_FILE"
}

compute_package_changes() {
    local before_file=$1
    local after_file=$2

    : > "$INSTALLED_FILE"
    : > "$UPDATED_FILE"
    : > "$REMOVED_FILE"

    awk -F'\t' '
        FNR == NR {
            before[$1] = $0
            before_ver[$1] = (NF > 1 ? $2 : "")
            next
        }
        {
            after[$1] = $0
            after_ver[$1] = (NF > 1 ? $2 : "")
        }
        END {
            for (name in before) {
                if (!(name in after)) {
                    print before[name] > removed
                } else if (before_ver[name] != after_ver[name]) {
                    printf "%s\t%s\t%s\n", name, before_ver[name], after_ver[name] > updated
                }
            }
            for (name in after) {
                if (!(name in before)) {
                    print after[name] > installed
                }
            }
        }
    ' removed="$REMOVED_FILE" updated="$UPDATED_FILE" installed="$INSTALLED_FILE" "$before_file" "$after_file"

    LC_ALL=C sort -o "$REMOVED_FILE" "$REMOVED_FILE" 2>/dev/null || :
    LC_ALL=C sort -o "$UPDATED_FILE" "$UPDATED_FILE" 2>/dev/null || :
    LC_ALL=C sort -o "$INSTALLED_FILE" "$INSTALLED_FILE" 2>/dev/null || :
}

refresh_metadata() {
    local backend=$1

    case $backend in
        dpkg)
            run_as_privileged apt-get update > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        pacman)
            run_as_privileged pacman -Sy > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        zypper)
            run_as_privileged zypper --non-interactive refresh > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        rpm)
            if command_exists dnf; then
                run_as_privileged dnf makecache > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            else
                run_as_privileged yum makecache > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            fi
            ;;
        apk)
            run_as_privileged apk update > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        xbps)
            run_as_privileged xbps-install -S > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        portage)
            run_as_privileged emerge --sync > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            ;;
        nix)
            if command_exists nix-channel; then
                nix-channel --update > "$REFRESH_FILE" 2>> "$OPERATIONS_LOG"
            else
                write_note_file "$REFRESH_FILE" 'No refresh command available for nix backend.'
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

collect_security_report() {
    local backend=$1

    case $backend in
        dpkg)
            {
                printf 'backend=dpkg\n\n'
                printf '## security-upgradable\n'
                if command_exists apt; then
                    apt list --upgradable 2>/dev/null | awk 'NR == 1 || /security/'
                else
                    printf 'apt not available\n'
                fi
                printf '\n## debsecan\n'
                if command_exists debsecan; then
                    debsecan --format packages --only-fixed 2>/dev/null || printf 'debsecan returned no data\n'
                else
                    printf 'not-installed\n'
                fi
            } > "$SECURITY_FILE"
            ;;
        pacman)
            {
                printf 'backend=pacman\n\n'
                printf '## arch-audit\n'
                if command_exists arch-audit; then
                    arch-audit -u 2>/dev/null || printf 'arch-audit returned no data\n'
                else
                    printf 'not-installed\n'
                fi
            } > "$SECURITY_FILE"
            ;;
        zypper)
            run_capture_allow_codes "$SECURITY_FILE" "0" zypper --non-interactive list-patches --category security
            ;;
        rpm)
            if command_exists dnf; then
                run_capture_allow_codes "$SECURITY_FILE" "0,100" dnf -q updateinfo list security
            else
                run_capture_allow_codes "$SECURITY_FILE" "0,100" yum updateinfo list security
            fi
            ;;
        apk)
            if command_exists apk; then
                run_capture_allow_codes "$SECURITY_FILE" "0,1" apk audit
            else
                write_note_file "$SECURITY_FILE" 'backend=apk' 'apk audit not available'
            fi
            ;;
        xbps)
            write_note_file "$SECURITY_FILE" 'backend=xbps' 'Native security advisory feed not available in this script. Review distro advisories.'
            ;;
        portage)
            if command_exists glsa-check; then
                run_capture_allow_codes "$SECURITY_FILE" "0,1" glsa-check -t affected
            else
                write_note_file "$SECURITY_FILE" 'backend=portage' 'glsa-check not installed.'
            fi
            ;;
        nix)
            if command_exists vulnix; then
                run_capture_allow_codes "$SECURITY_FILE" "0,1" vulnix --system
            else
                write_note_file "$SECURITY_FILE" 'backend=nix' 'Native advisory scan not available; review NixOS or Nix advisories.'
            fi
            ;;
        *)
            write_note_file "$SECURITY_FILE" 'backend=unknown' 'Security report not available for this backend.'
            ;;
    esac
}

plan_updates() {
    local backend=$1

    : > "$PLANNED_INSTALLED_FILE"
    : > "$PLANNED_UPDATED_FILE"
    : > "$PLANNED_REMOVED_FILE"

    case $backend in
        dpkg)
            run_capture "$PLAN_FILE" apt-get -s full-upgrade && parse_dpkg_plan "$PLAN_FILE"
            ;;
        pacman)
            run_capture_allow_codes "$PLAN_FILE" "0,1" pacman -Qu
            ;;
        zypper)
            run_capture "$PLAN_FILE" zypper --non-interactive list-updates
            ;;
        rpm)
            if command_exists dnf; then
                run_capture_allow_codes "$PLAN_FILE" "0,100" dnf check-update
            else
                run_capture_allow_codes "$PLAN_FILE" "0,100" yum check-update
            fi
            ;;
        apk)
            run_capture_allow_codes "$PLAN_FILE" "0,1" apk version -l '<'
            ;;
        xbps)
            run_capture_allow_codes "$PLAN_FILE" "0,1" xbps-install -un
            ;;
        portage)
            run_capture "$PLAN_FILE" emerge -puDN @world
            ;;
        nix)
            if command_exists nixos-rebuild; then
                run_capture "$PLAN_FILE" nixos-rebuild dry-build --upgrade
            elif command_exists nix-env; then
                run_capture_allow_codes "$PLAN_FILE" "0,1" nix-env -u --dry-run '*'
            else
                write_note_file "$PLAN_FILE" 'No plan command available for nix backend.'
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

apply_updates() {
    local backend=$1

    case $backend in
        dpkg)
            if ((AUTO_YES == 1)); then
                run_as_privileged env DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade >> "$OPERATIONS_LOG" 2>&1
            else
                run_as_privileged apt-get full-upgrade >> "$OPERATIONS_LOG" 2>&1
            fi
            ;;
        pacman)
            if ((AUTO_YES == 1)); then
                run_as_privileged pacman -Syu --noconfirm >> "$OPERATIONS_LOG" 2>&1
            else
                run_as_privileged pacman -Syu >> "$OPERATIONS_LOG" 2>&1
            fi
            ;;
        zypper)
            if ((AUTO_YES == 1)); then
                run_as_privileged zypper --non-interactive update >> "$OPERATIONS_LOG" 2>&1
            else
                run_as_privileged zypper update >> "$OPERATIONS_LOG" 2>&1
            fi
            ;;
        rpm)
            if command_exists dnf; then
                if ((AUTO_YES == 1)); then
                    run_as_privileged dnf -y upgrade >> "$OPERATIONS_LOG" 2>&1
                else
                    run_as_privileged dnf upgrade >> "$OPERATIONS_LOG" 2>&1
                fi
            else
                if ((AUTO_YES == 1)); then
                    run_as_privileged yum -y update >> "$OPERATIONS_LOG" 2>&1
                else
                    run_as_privileged yum update >> "$OPERATIONS_LOG" 2>&1
                fi
            fi
            ;;
        apk)
            run_as_privileged apk upgrade >> "$OPERATIONS_LOG" 2>&1
            ;;
        xbps)
            if ((AUTO_YES == 1)); then
                run_as_privileged xbps-install -Su -y >> "$OPERATIONS_LOG" 2>&1
            else
                run_as_privileged xbps-install -Su >> "$OPERATIONS_LOG" 2>&1
            fi
            ;;
        portage)
            if ((AUTO_YES == 1)); then
                run_as_privileged emerge -uDN @world --ask=n >> "$OPERATIONS_LOG" 2>&1
            else
                run_as_privileged emerge -uDN @world >> "$OPERATIONS_LOG" 2>&1
            fi
            ;;
        nix)
            if command_exists nixos-rebuild; then
                run_as_privileged nixos-rebuild switch --upgrade >> "$OPERATIONS_LOG" 2>&1
            elif command_exists nix-env; then
                run_as_privileged nix-env -u '*' >> "$OPERATIONS_LOG" 2>&1
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

write_json_report() {
    {
        printf '{\n'
        printf '  "manifest": '
        json_write_object_from_kv_file "$MANIFEST_FILE" '  '
        printf ',\n'
        printf '  "summary": '
        json_write_object_from_kv_file "$SUMMARY_FILE" '  '
        printf ',\n'
        printf '  "trust": {\n'
        printf '    "backend": "%s",\n' "$(json_escape "$(read_backend_value "$TRUST_FILE")")"
        printf '    "status": "%s",\n' "$(json_escape "$TRUST_STATUS")"
        printf '    "allowlist_file": "%s",\n' "$(json_escape "$TRUST_ALLOWLIST_FILE")"
        printf '    "report_file": "%s",\n' "$(json_escape "$TRUST_FILE")"
        printf '    "official_count": %s,\n' "$(count_trust_classification official)"
        printf '    "allowed_count": %s,\n' "$(count_trust_classification allowed)"
        printf '    "review_count": %s,\n' "$(count_trust_classification review)"
        printf '    "detected_sources": '
        json_write_trust_sources_array "$TRUST_FILE" '    '
        printf ',\n'
        printf '    "official_sources": '
        json_write_trust_source_names_array "$TRUST_FILE" 'official' '    '
        printf ',\n'
        printf '    "allowed_sources": '
        json_write_trust_source_names_array "$TRUST_FILE" 'allowed' '    '
        printf ',\n'
        printf '    "review_sources": '
        json_write_trust_source_names_array "$TRUST_FILE" 'review' '    '
        printf ',\n'
        printf '    "sections": '
        json_write_report_sections_object "$TRUST_FILE" '    '
        printf '  },\n'
        printf '  "security": {\n'
        printf '    "backend": "%s",\n' "$(json_escape "$(read_backend_value "$SECURITY_FILE")")"
        printf '    "report_file": "%s",\n' "$(json_escape "$SECURITY_FILE")"
        printf '    "sections": '
        json_write_report_sections_object "$SECURITY_FILE" '    '
        printf '\n  },\n'
        printf '  "planned_changes": {\n'
        printf '    "installed": '
        json_write_lines_array "$PLANNED_INSTALLED_FILE" '    '
        printf ',\n'
        printf '    "updated": '
        json_write_lines_array "$PLANNED_UPDATED_FILE" '    '
        printf ',\n'
        printf '    "removed": '
        json_write_lines_array "$PLANNED_REMOVED_FILE" '    '
        printf '\n  },\n'
        printf '  "applied_changes": {\n'
        printf '    "installed": '
        json_write_lines_array "$INSTALLED_FILE" '    '
        printf ',\n'
        printf '    "updated": '
        json_write_lines_array "$UPDATED_FILE" '    '
        printf ',\n'
        printf '    "removed": '
        json_write_lines_array "$REMOVED_FILE" '    '
        printf '\n  },\n'
        printf '  "files": {\n'
        printf '    "plan": "%s",\n' "$(json_escape "$PLAN_FILE")"
        printf '    "security": "%s",\n' "$(json_escape "$SECURITY_FILE")"
        printf '    "source_trust": "%s",\n' "$(json_escape "$TRUST_FILE")"
        printf '    "before_packages": "%s",\n' "$(json_escape "$BEFORE_FILE")"
        printf '    "after_packages": "%s"\n' "$(json_escape "$AFTER_FILE")"
        printf '  }\n'
        printf '}\n'
    } > "$JSON_REPORT_FILE"
}

write_summary() {
    {
        printf 'mode=%s\n' "$MODE"
        printf 'report_dir=%s\n' "$REPORT_DIR"
        printf 'trust_status=%s\n' "$TRUST_STATUS"
        printf 'planned_installed=%s\n' "$(count_lines "$PLANNED_INSTALLED_FILE")"
        printf 'planned_updated=%s\n' "$(count_lines "$PLANNED_UPDATED_FILE")"
        printf 'planned_removed=%s\n' "$(count_lines "$PLANNED_REMOVED_FILE")"
        printf 'installed=%s\n' "$(count_lines "$INSTALLED_FILE")"
        printf 'updated=%s\n' "$(count_lines "$UPDATED_FILE")"
        printf 'removed=%s\n' "$(count_lines "$REMOVED_FILE")"
        printf 'warnings=%s\n' "$(count_lines "$WARNINGS_FILE")"
    } > "$SUMMARY_FILE"
}

main() {
    local os_id='unknown'
    local os_like='unknown'
    local os_name='unknown'
    local distro_family='unknown'
    local backend='unknown'

    TRUST_STATUS='unknown'

    detect_os_release os_id os_like os_name
    distro_family=$(infer_distro_family "$os_id" "$os_like")
    backend=$(detect_package_backend)

    append_manifest 'timestamp_utc' "$RUN_TS"
    append_manifest 'report_dir' "$REPORT_DIR"
    append_manifest 'hostname' "$HOSTNAME_SAFE"
    append_manifest 'user' "${SUDO_USER:-${USER:-unknown}}"
    append_manifest 'effective_uid' "$(id -u)"
    append_manifest 'os_id' "$os_id"
    append_manifest 'os_like' "$os_like"
    append_manifest 'os_name' "$os_name"
    append_manifest 'distro_family' "$distro_family"
    append_manifest 'package_backend' "$backend"
    append_manifest 'mode' "$MODE"
    append_manifest 'auto_yes' "$AUTO_YES"
    append_manifest 'refresh_metadata' "$REFRESH_METADATA"
    append_manifest 'allow_untrusted_sources' "$ALLOW_UNTRUSTED_SOURCES"
    append_manifest 'trust_allowlist_file' "$TRUST_ALLOWLIST_FILE"
    append_manifest 'json_report' "$JSON_REPORT_FILE"

    if [[ "$backend" == 'unknown' ]]; then
        warn 'No supported package backend was detected.'
        return 1
    fi

    if ((REFRESH_METADATA == 1)); then
        if [[ "$MODE" == 'check' ]] && refresh_requires_privilege "$backend" && ((EUID != 0)); then
            warn 'Metadata refresh skipped in check mode because root privileges are not available.'
            append_manifest 'refresh_status' 'skipped_no_root'
        else
            if refresh_metadata "$backend"; then
                append_manifest 'refresh_status' 'ok'
            else
                warn 'Metadata refresh failed.'
                append_manifest 'refresh_status' 'failed'
            fi
        fi
    else
        append_manifest 'refresh_status' 'disabled'
    fi

    if list_installed_packages "$backend" "$BEFORE_FILE"; then
        append_manifest 'before_snapshot' "$BEFORE_FILE"
    else
        warn 'Failed to collect the initial package inventory.'
        return 1
    fi

    TRUST_STATUS=$(collect_source_trust_report "$backend" "$TRUST_FILE")
    append_manifest 'trust_report' "$TRUST_FILE"
    append_manifest 'trust_status' "$TRUST_STATUS"

    case "$TRUST_STATUS" in
        trusted)
            ;;
        review)
            warn 'Source trust report requires manual review for one or more non-official repositories.'
            ;;
        limited)
            warn 'Source trust verification is limited for this backend; review repositories manually before applying updates.'
            ;;
        failed)
            warn 'Source trust verification detected insecure repository settings or signature problems.'
            ;;
    esac

    if collect_security_report "$backend"; then
        append_manifest 'security_report' "$SECURITY_FILE"
    else
        warn 'Failed to collect the security report.'
    fi

    : > "$INSTALLED_FILE"
    : > "$UPDATED_FILE"
    : > "$REMOVED_FILE"

    if [[ "$MODE" == 'apply' ]]; then
        if should_block_apply_for_trust "$TRUST_STATUS"; then
            warn 'Apply mode blocked because the trust report found insecure sources. Use --allow-untrusted-sources only if you have reviewed them manually.'
            append_manifest 'transaction_status' 'blocked_untrusted_sources'
            write_summary
            return 1
        fi

        if ! apply_updates "$backend"; then
            warn 'Package update failed.'
            append_manifest 'transaction_status' 'failed'
            write_summary
            return 1
        fi

        append_manifest 'transaction_status' 'applied'

        if list_installed_packages "$backend" "$AFTER_FILE"; then
            compute_package_changes "$BEFORE_FILE" "$AFTER_FILE"
            append_manifest 'after_snapshot' "$AFTER_FILE"
        else
            warn 'Failed to collect the final package inventory.'
        fi
    else
        if plan_updates "$backend"; then
            append_manifest 'transaction_status' 'planned'
        else
            warn 'Failed to build the update plan.'
            append_manifest 'transaction_status' 'plan_failed'
        fi
    fi

    write_summary
    write_json_report
    printf 'report_dir=%s\n' "$REPORT_DIR"
}

main "$@"