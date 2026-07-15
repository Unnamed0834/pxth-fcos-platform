



set -euo pipefail

if ! declare -F log_error >/dev/null 2>&1; then
    log_error() { echo "[ERROR] $*" >&2; }
fi


cache_hash_algo_ok() {
    case "${1:-}" in
        sha256|sha512) return 0 ;;
        *)
            log_error "Weak/unsupported hash algorithm rejected: '${1:-<empty>}'"
            log_error "SHA256 is the minimum; SHA512 is preferred."
            return 1
            ;;
    esac
}


cache_compute_hash() {
    local algo="$1"
    local file="$2"
    cache_hash_algo_ok "$algo" || return 1
    case "$algo" in
        sha256) sha256sum "$file" | cut -d' ' -f1 ;;
        sha512) sha512sum "$file" | cut -d' ' -f1 ;;
    esac
}




cache_extract_expected_hash() {
    local digests_file="$1"
    local algo="$2"
    local filename="$3"

    cache_hash_algo_ok "$algo" || return 1

    local hash
    hash=$(awk -v algo="$algo" -v fname="$filename" '
        { lines[NR] = $0 }
        END {
            section = "# " toupper(algo) " HASH"

            for (i = 1; i <= NR; i++) {
                if (toupper(lines[i]) == section) {
                    fallback = ""
                    for (j = i + 1; j <= NR; j++) {
                        if (lines[j] ~ /^#/) { break }
                        if (lines[j] ~ /[^[:space:]]/) {
                            split(lines[j], parts, /[[:space:]]+/)
                            if (parts[2] == fname || parts[2] == "*" fname) {
                                print parts[1]
                                exit
                            }
                            if (fallback == "") { fallback = parts[1] }
                        }
                    }
                    if (fallback != "") { print fallback; exit }
                }
            }

            for (i = 1; i <= NR; i++) {
                n = split(lines[i], parts, /[[:space:]]+/)
                if (n >= 2 && (parts[2] == fname || parts[2] == "*" fname)) {
                    print parts[1]
                    exit
                }
            }
        }
    ' "$digests_file") || hash=""


    case "$algo" in
        sha256)
            [[ "$hash" =~ ^[0-9a-fA-F]{64}$ ]] && printf '%s' "$hash"
            ;;
        sha512)
            [[ "$hash" =~ ^[0-9a-fA-F]{128}$ ]] && printf '%s' "$hash"
            ;;
    esac
    return 0
}
