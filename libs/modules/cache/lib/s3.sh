















set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_LIB_DIR/gpg/trust.sh"

source "$_LIB_DIR/digest.sh"


cache_s3_ls() {
    local bucket="$1"
    local prefix="$2"
    local endpoint="${3:-}"

    local aws_args=()
    if [[ -n "$endpoint" ]]; then
        aws_args+=("--endpoint-url" "$endpoint")
    fi

    aws s3 ls "s3://${bucket}/${prefix}" "${aws_args[@]}" | \
        grep 'PRE ' | sed 's/.*PRE //' | sed 's/\/$//'
}


cache_s3_download() {
    local bucket="$1"
    local key="$2"
    local dest_path="$3"
    local endpoint="${4:-}"
    local min_size="${5:-$MIN_SIZE_BINARY}"

    local filename
    filename=$(basename "$dest_path")

    if [[ -f "$dest_path" ]]; then
        local existing_size
        existing_size=$(stat -c%s "$dest_path" 2>/dev/null || stat -f%z "$dest_path" 2>/dev/null || echo "0")
        if (( existing_size >= min_size )); then
            log_success "S3 cached: $filename ($(numfmt --to=iec "$existing_size" 2>/dev/null || echo "${existing_size}B"))"
            return 0
        fi
    fi

    local aws_args=()
    if [[ -n "$endpoint" ]]; then
        aws_args+=("--endpoint-url" "$endpoint")
    fi

    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "AWS credentials not set (need AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)"
        return 1
    fi

    mkdir -p "$(dirname "$dest_path")"

    local tmp_dir
    tmp_dir=$(mktemp -d "$(dirname "$dest_path")/.tmp_s3.XXXXXX")
    trap 'rm -rf "$tmp_dir"' RETURN
    local temp_file="$tmp_dir/$filename"

    log_info "Downloading from S3: $bucket/$key"
    if ! aws s3 cp "s3://${bucket}/${key}" "$temp_file" "${aws_args[@]}"; then
        log_error "S3 download failed: s3://${bucket}/${key}"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null || echo "0")
    if (( file_size < min_size )); then
        log_error "S3 download too small: $file_size bytes (min: $min_size)"
        return 1
    fi

    mv "$temp_file" "$dest_path"
    log_success "Downloaded from S3: $filename ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
    return 0
}


_s3_digest_from_url() {
    local url="$1"
    local ep="$2"
    [[ -z "$ep" ]] && return 1
    local ep_host url_host url_path s3_bucket s3_key
    ep_host=$(echo "$ep" | sed 's|https\?://||' | sed 's|/.*||')
    url_host=$(echo "$url" | sed 's|https\?://||' | sed 's|/.*||')
    [[ "$ep_host" != "$url_host" ]] && return 1
    url_path=$(echo "$url" | sed 's|https\?://[^/]*||')
    s3_bucket=$(echo "$url_path" | cut -d'/' -f2)
    s3_key=$(echo "$url_path" | cut -d'/' -f3- | sed 's|^/||')
    [[ -z "$s3_bucket" || -z "$s3_key" ]] && return 1
    echo "${s3_bucket}|${s3_key}"
    return 0
}


_s3_fetch_aux() {
    local url="$1"
    local endpoint="$2"
    local output="$3"

    if [[ -n "$endpoint" ]]; then
        local info
        if info=$(_s3_digest_from_url "$url" "$endpoint"); then
            local bucket key
            bucket=$(echo "$info" | cut -d'|' -f1)
            key=$(echo "$info" | cut -d'|' -f2)
            if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
                log_error "AWS credentials not set (need AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)"
                return 1
            fi
            if ! aws s3 cp "s3://${bucket}/${key}" "$output" --endpoint-url "$endpoint"; then
                log_error "Failed to download from S3: s3://${bucket}/${key}"
                return 1
            fi
            return 0
        fi
    fi
    if ! curl -fsSL --max-time "$DOWNLOAD_TIMEOUT" --progress-bar "$url" -o "$output"; then
        log_error "Failed to download: $url"
        return 1
    fi
    return 0
}


cache_s3_download_signed() {
    local bucket="$1"
    local key="$2"
    local dest_path="$3"
    local endpoint="${4:-}"
    local digests_url="${5:-}"
    local digests_asc_url="${6:-}"
    local hash_algo="${7:-sha512}"
    local min_size="${8:-$MIN_SIZE_BINARY}"
    local gpg_key_name="${9:-flatcar}"

    cache_hash_algo_ok "$hash_algo" || return 1

    if [[ -z "$digests_url" || -z "$digests_asc_url" ]]; then
        log_error "Signed S3 download requires both a .DIGESTS URL and a .asc signature URL"
        return 1
    fi

    local filename
    filename=$(basename "$dest_path")
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
    tmp_dir=$(mktemp -d "${dest_dir}/.tmp_s3.XXXXXX")
    trap 'rm -rf "$tmp_dir"' RETURN
    local digests_file="$tmp_dir/${filename}.DIGESTS"
    local asc_file="$tmp_dir/${filename}.DIGESTS.asc"
    local verified_digests="$tmp_dir/${filename}.DIGESTS.verified"
    local temp_file="$tmp_dir/$filename"

    log_info "Downloading digests: $(basename "$digests_url")"
    _s3_fetch_aux "$digests_url" "$endpoint" "$digests_file" || return 1

    log_info "Downloading signature: $(basename "$digests_asc_url")"
    _s3_fetch_aux "$digests_asc_url" "$endpoint" "$asc_file" || return 1

    if ! cache_gpg_verify_and_extract "$asc_file" "$gpg_key_name" "$digests_file" "$verified_digests"; then
        log_error "Refusing to use $filename: signature verification failed"
        return 1
    fi

    local expected_hash
    expected_hash=$(cache_extract_expected_hash "$verified_digests" "$hash_algo" "$filename")
    if [[ -z "$expected_hash" ]]; then
        log_error "Could not extract a valid $hash_algo hash from the signed digests"
        return 1
    fi
    log_info "Expected $hash_algo (signed): $expected_hash"

    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "AWS credentials not set (need AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)"
        return 1
    fi

    local aws_args=()
    if [[ -n "$endpoint" ]]; then
        aws_args+=("--endpoint-url" "$endpoint")
    fi
    log_info "Downloading from S3: $bucket/$key"
    if ! aws s3 cp "s3://${bucket}/${key}" "$temp_file" "${aws_args[@]}"; then
        log_error "S3 download failed: s3://${bucket}/${key}"
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
source_s3=s3://${bucket}/${key}
digests_url=$digests_url
EOF

    log_success "Downloaded and PGP-verified from S3: $filename ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
    return 0
}
