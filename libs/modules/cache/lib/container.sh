






set -euo pipefail




cache_download_image() {
    local image_ref="$1"
    local dest_dir="$2"
    local component="${3:-misc}"
    local expected_digest="${4:-}"

    local image_name
    local image_tag
    image_name=$(echo "$image_ref" | sed 's/.*\///' | sed 's/:.*//')
    image_tag=$(echo "$image_ref" | sed 's/.*://')

    local dest_filename="${image_name}-${image_tag}.tar"
    local component_dir="$dest_dir/$component"
    local dest_path="$component_dir/$dest_filename"

    mkdir -p "$component_dir"

    if [[ -f "$dest_path" ]]; then

        if [[ -n "$expected_digest" ]]; then
            local cached_digest
            cached_digest=$(cat "${dest_path}.digest" 2>/dev/null || echo "")
            local expected_normalized="${expected_digest#sha256:}"
                if [[ "$cached_digest" == "$expected_normalized" ]]; then
                log_success "Image $image_name:$image_tag already cached (manifest digest verified)"
                return 0
            fi
            log_warn "Cached image manifest digest mismatch, re-pulling: $image_ref"
        else
            log_success "Image $image_name:$image_tag already cached"
            return 0
        fi
    fi

    log_info "Pulling image: $image_ref"

    local runtime
    runtime=$(get_container_runtime) || {
        log_error "No container runtime found (need podman or docker)"
        return 1
    }

    log_info "Using runtime: $runtime"


    if ! $runtime pull --platform linux/amd64 "$image_ref" 2>&1; then
        log_error "Failed to pull image: $image_ref"
        return 1
    fi

    log_info "Saving image to: $dest_path"
    rm -f "$dest_path"
    if ! $runtime save "$image_ref" -o "$dest_path" 2>&1; then
        log_error "Failed to save image: $image_ref"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$dest_path" 2>/dev/null || stat -f%z "$dest_path" 2>/dev/null || echo "0")

    if (( file_size < MIN_SIZE_IMAGE )); then
        log_error "Saved file too small: $file_size bytes (min: $MIN_SIZE_IMAGE)"
        rm -f "$dest_path" "${dest_path}.digest" 2>/dev/null
        return 1
    fi


    local image_digest
    image_digest=$($runtime inspect --format "{{index .RepoDigests 0}}" "$image_ref" 2>/dev/null | sed 's/.*@sha256://' || echo "")
    if [[ -n "$image_digest" ]]; then
        echo "$image_digest" > "${dest_path}.digest"
    fi


    if [[ -n "$expected_digest" ]]; then
        if [[ -z "$image_digest" ]]; then
            log_error "Could not read image manifest digest for $image_ref"
            return 1
        fi
        local expected_normalized="${expected_digest#sha256:}"
        if [[ "$image_digest" != "$expected_normalized" ]]; then
            log_error "Image manifest digest mismatch for $image_ref"
            log_error "  Expected: $expected_digest"
            log_error "  Got:      $image_digest"
            return 1
        fi
        log_info "Image manifest digest verified: $image_digest"
    fi

    log_success "Saved image: $image_name:$image_tag ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
   return 0
}