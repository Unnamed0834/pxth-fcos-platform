













set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_LIB_DIR/gpg/trust.sh"

source "$_LIB_DIR/digest.sh"


cache_download_file() {
    local url="$1"
    local dest_path="$2"
    local expected_checksum="${3:-}"
    local min_size="${4:-$MIN_SIZE_BINARY}"

    local filename
    filename=$(basename "$dest_path")

    if [[ -f "$dest_path" ]]; then
        log_success "File $filename already cached"
        return 0
    fi

    log_info "Downloading: $filename"

    local dest_dir
    dest_dir=$(dirname "$dest_path")
    mkdir -p "$dest_dir"

    local tmp_dir
    tmp_dir=$(mktemp -d "${dest_dir}/.tmp_download.XXXXXX")
    trap 'rm -rf "$tmp_dir"' RETURN
    local temp_file="$tmp_dir/$filename"

    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$url" -o "$temp_file"; then
        log_error "Download failed: $url"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    if (( file_size < min_size )); then
        log_error "Downloaded file too small: $file_size bytes (min: $min_size)"
        return 1
    fi

    if [[ -n "$expected_checksum" ]]; then
        local computed_checksum
        computed_checksum=$(sha256sum "$temp_file" | cut -d' ' -f1)
        if [[ "$computed_checksum" != "$expected_checksum" ]]; then
            log_error "SHA256 mismatch for $filename"
            return 1
        fi
    fi

    mv "$temp_file" "$dest_path"
    log_success "Downloaded: $filename ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
    return 0
}




cache_download_signed_file() {
    local url="$1"
    local dest_path="$2"
    local digests_url="$3"
    local digests_asc_url="${4:-}"
    local hash_algo="${5:-sha512}"
    local min_size="${6:-$MIN_SIZE_BINARY}"
    local gpg_key_name="${7:-flatcar}"

    cache_hash_algo_ok "$hash_algo" || return 1

    if [[ -z "$digests_url" || -z "$digests_asc_url" ]]; then
        log_error "Signed download requires both a .DIGESTS URL and a .asc signature URL"
        return 1
    fi

    local filename
    filename=$(basename "$dest_path")
    local url_filename
    url_filename=$(basename "$url")
    local dest_dir
    dest_dir=$(dirname "$dest_path")
    mkdir -p "$dest_dir"


    if [[ -f "$dest_path" ]] && [[ -f "${dest_path}.verified" ]]; then
        local marker_algo marker_sig
        marker_algo=$(awk -F= '$1=="hash_algo"{print $2}' "${dest_path}.verified" || true)
        marker_sig=$(awk -F= '$1=="sig_verified"{print $2}' "${dest_path}.verified" || true)
        if [[ "$marker_sig" == "true" ]] && { [[ "$marker_algo" == "sha256" || "$marker_algo" == "sha512" ]]; }; then
            log_success "File $filename already verified"
            return 0
        fi
        log_warn "Existing marker is weak/unsigned for $filename; re-downloading"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "${dest_dir}/.tmp_download.XXXXXX")
    trap 'rm -rf "$tmp_dir"' RETURN
    local digests_file="$tmp_dir/${filename}.DIGESTS"
    local asc_file="$tmp_dir/${filename}.DIGESTS.asc"
    local verified_digests="$tmp_dir/${filename}.DIGESTS.verified"
    local temp_file="$tmp_dir/$filename"

    log_info "Downloading digests: $(basename "$digests_url")"
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$digests_url" -o "$digests_file"; then
        log_error "Failed to download digests: $digests_url"
        return 1
    fi

    log_info "Downloading signature: $(basename "$digests_asc_url")"
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$digests_asc_url" -o "$asc_file"; then
        log_error "Failed to download signature: $digests_asc_url"
        return 1
    fi


    if ! cache_gpg_verify_and_extract "$asc_file" "$gpg_key_name" "$digests_file" "$verified_digests"; then
        log_error "Refusing to use $filename: signature verification failed"
        return 1
    fi

    local expected_hash
    expected_hash=$(cache_extract_expected_hash "$verified_digests" "$hash_algo" "$url_filename")
    if [[ -z "$expected_hash" ]]; then
        log_error "Could not extract a valid $hash_algo hash from the signed digests"
        return 1
    fi
    log_info "Expected $hash_algo (signed): $expected_hash"

    log_info "Downloading: $filename"
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$url" -o "$temp_file"; then
        log_error "Download failed: $url"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    if (( file_size < min_size )); then
        log_error "Downloaded file too small: $file_size bytes (min: $min_size)"
        return 1
    fi

    local computed_hash
    computed_hash=$(cache_compute_hash "$hash_algo" "$temp_file") || return 1
    if [[ "$computed_hash" != "$expected_hash" ]]; then
        log_error "Hash mismatch for $filename"
        log_error "  Expected ($hash_algo): $expected_hash"
        log_error "  Computed ($hash_algo): $computed_hash"
        return 1
    fi
    log_success "Hash verified ($hash_algo): $computed_hash"

    mv "$temp_file" "$dest_path"

    local config fingerprint
    config=$(cache_gpg_trust_config "$gpg_key_name")
    fingerprint="${config#*|}"; fingerprint="${fingerprint%%|*}"
    cat > "${dest_path}.verified" <<EOF
verified_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
hash_algo=$hash_algo
hash=$computed_hash
sig_verified=true
signer_fingerprint=$fingerprint
source_url=$url
digests_url=$digests_url
EOF

    log_success "Downloaded and PGP-verified: $filename ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
    return 0
}
