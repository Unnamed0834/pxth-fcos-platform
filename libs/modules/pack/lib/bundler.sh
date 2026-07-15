







set -euo pipefail


























pack_pack_bundle() {
    local bundle_dir="$1"
    local manifest_file="$2"
    local ver_dir="${3:-}"
    local node_name="${4:-}"

    if [[ ! -f "$manifest_file" ]]; then
        log_error "Manifest not found: $manifest_file"
        return 1
    fi

    python3 "$PACK_LIB/pack-bundle.py" \
        --bundle-dir "$bundle_dir" \
        --manifest "$manifest_file" \
        --ver-dir "$ver_dir" \
        --inference-engine "${INFERENCE_ENGINE:-}" \
        --node-name "$node_name"
}





pack_create_tarball() {
    local source_dir="$1"
    local output_tarball="$2"

    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory not found: $source_dir"
        return 1
    fi

    mkdir -p "$(dirname "$output_tarball")"

    log_info "Creating tarball..."
    (cd "$source_dir" && tar czf "$output_tarball" .)

    local size
    size=$(stat -c%s "$output_tarball" 2>/dev/null || stat -f%z "$output_tarball" 2>/dev/null || echo "0")
    log_success "Tarball: $size bytes"
}
