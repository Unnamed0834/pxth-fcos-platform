















set -euo pipefail

if ! declare -F log_error >/dev/null 2>&1; then
    log_error() { echo "[ERROR] $*" >&2; }
fi
if ! declare -F log_info >/dev/null 2>&1; then
    log_info() { echo "[INFO] $*" >&2; }
fi
if ! declare -F log_success >/dev/null 2>&1; then
    log_success() { echo "[OK] $*" >&2; }
fi

_PXTH_GPG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"



cache_gpg_trust_config() {
    local key_name="${1:-}"
    case "$key_name" in
        flatcar)
            printf '%s|%s|%s\n' \
                "$_PXTH_GPG_DIR/flatcar-buildbot.asc" \
                "F88CFEDEFF29A5B4D9523864E25D9AED0593B34A" \
                "E25D9AED0593B34A"
            ;;
        *)
            log_error "Unknown GPG trust root name: $key_name"
            return 1
            ;;
    esac
}


cache_gpg_check_trust_root() {
    local key_file="$1"
    local expected_fpr="$2"
    local expected_keyid="$3"

    if [[ ! -f "$key_file" ]]; then
        log_error "PGP trust root is not provisioned: $key_file"
        log_error "Install the pinned public key out-of-band before running sync."
        log_error "No key will be fetched at runtime."
        return 1
    fi

    local actual_fpr
    actual_fpr=$(gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null | awk -F: \
        -v kid="$expected_keyid" '
        $1 == "pub" { active = ($5 == kid) }
        $1 == "fpr" && active { print $10; active = 0 }
    ' | head -n 1) || actual_fpr=""

    if [[ "$actual_fpr" != "$expected_fpr" ]]; then
        log_error "PGP trust root fingerprint mismatch for $key_file"
        log_error "  Expected: $expected_fpr"
        log_error "  Actual:   ${actual_fpr:-<not found>}"
        log_error "Refusing to use a key that is not pinned."
        return 1
    fi
    return 0
}



_cache_gpg_status_ok() {
    local status_file="$1"
    local expected_fpr="$2"
    awk -v want="$expected_fpr" '
        /^\[GNUPG:\] GOODSIG / { goodsig = 1 }
        /^\[GNUPG:\] VALIDSIG / {
            primary = (NF >= 12) ? toupper($12) : ""
            signer  = toupper($3)
            if (signer == toupper(want) || primary == toupper(want)) {
                if (primary != "" && primary != toupper(want)) { badprimary = 1 }
                algo = $10 + 0
                if (algo == 8 || algo == 9 || algo == 10 || algo == 11) { strong = 1 }
            }
        }
        END { exit (goodsig && strong && !badprimary) ? 0 : 1 }
    ' "$status_file"
}




cache_gpg_verify_and_extract() {
    local asc_file="$1"
    local key_name="${2:-}"
    local digests_file="${3:-}"
    local verified_file="$4"

    local config key_file fingerprint keyid
    config=$(cache_gpg_trust_config "$key_name") || return 1
    IFS='|' read -r key_file fingerprint keyid <<< "$config"
    cache_gpg_check_trust_root "$key_file" "$fingerprint" "$keyid" || return 1

    (
        set -euo pipefail
        local gnupg_home status_file accepted=false

        gnupg_home=$(mktemp -d "${TMPDIR:-/tmp}/pxth-gpg.XXXXXX")
        trap 'rm -rf "$gnupg_home"' EXIT
        status_file="$gnupg_home/status.txt"
        export GNUPGHOME="$gnupg_home"

        if ! gpg --batch --quiet --import "$key_file" >/dev/null 2>&1; then
            log_error "Could not import pinned PGP key: $key_file"
            exit 1
        fi



        rm -f "$verified_file"
        if gpg --batch --yes --status-fd 1 --output "$verified_file" \
                --verify "$asc_file" > "$status_file" 2>/dev/null; then
            if [[ -s "$verified_file" ]] && _cache_gpg_status_ok "$status_file" "$fingerprint"; then
                accepted=true
            fi
        fi


        if [[ "$accepted" != true && -n "$digests_file" && -f "$digests_file" ]]; then
            : > "$verified_file"
            if gpg --batch --yes --status-fd 1 --verify "$asc_file" "$digests_file" \
                    > "$status_file" 2>/dev/null; then
                if _cache_gpg_status_ok "$status_file" "$fingerprint"; then
                    cp "$digests_file" "$verified_file"
                    accepted=true
                fi
            fi
        fi

        if [[ "$accepted" != true ]]; then
            log_error "PGP signature verification FAILED for $(basename "$asc_file")"
            log_error "Expected signer fingerprint: $fingerprint"
            log_error "Weak/missing signatures are rejected; refusing to use this artifact."
            exit 1
        fi

        log_success "PGP signature verified (fingerprint $fingerprint)"
    )
}
