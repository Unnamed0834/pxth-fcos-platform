







set -euo pipefail



pack_create_disk() {
    local tarball="$1"
    local output="$2"
    local headroom="${3:-64}"

    if [[ ! -f "$tarball" ]]; then
        log_error "Tarball not found: $tarball"
        return 1
    fi

    log_info "Creating OEM disk image..."

    python3 "$PACK_LIB/create-disk.py" \
        --tarball "$tarball" \
        --output "$output" \
        --headroom "$headroom"

    log_success "  Disk: $output ($(du -h "$output" | cut -f1))"
}



pack_create_flatcar_symlink() {
    local flatcar_img="$1"
    local dest_symlink="$2"


    [[ "${OEM_NO_FLATCAR:-}" == "true" ]] && return 0

    if [[ -f "$flatcar_img" ]]; then
        log_info "Creating Flatcar symlink..."
        mkdir -p "$(dirname "$dest_symlink")"
        rm -f "$dest_symlink"
        ln -sf "$flatcar_img" "$dest_symlink"
        touch -h "$dest_symlink"
        log_success "Flatcar symlink created"
    else
        log_error "Flatcar image not found: $flatcar_img"
        return 1
    fi
}
