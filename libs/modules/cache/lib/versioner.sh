









set -euo pipefail



cache_get_current_version() {
    local node="$1"
    local v1_dir="$ARTIFACTS_ROOT/$node/versions/v1"

    if [[ -d "$v1_dir" ]]; then
        echo "v1"
    else
        log_error "No version directory found for $node"
        return 1
    fi
}





cache_create_new_version() {
    local node="$1"
    local versions_dir="$ARTIFACTS_ROOT/$node/versions"

    log_info "Rotating versions for CIFS compatibility..."


    if [[ -d "$versions_dir/v2" ]]; then
        log_info "Moving v2 -> v3"
        mv "$versions_dir/v2" "$versions_dir/v3"
    fi


    if [[ -d "$versions_dir/v1" ]]; then
        log_info "Moving v1 -> v2"
        mv "$versions_dir/v1" "$versions_dir/v2"
    fi


    mkdir -p "$versions_dir/v1"

    log_success "Version rotation complete (v1 is latest)"
    echo "v1"
}


cache_apply_retention() {
    local node="$1"
    local max_versions="${2:-$ARTIFACT_MAX_VERSIONS}"
    local versions_dir="$ARTIFACTS_ROOT/$node/versions"

    if [[ ! -d "$versions_dir" ]]; then
        return 0
    fi

    local versions=()
    for dir in "$versions_dir"/v*; do
        if [[ -d "$dir" ]]; then
            versions+=("$(basename "$dir")")
        fi
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        return 0
    fi

    IFS=$'\n' versions=($(sort -V <<<"${versions[*]}"))
    unset IFS

    local total_count=${#versions[@]}

    if (( total_count <= max_versions )); then
        log_info "Retention: $total_count versions (within limit of $max_versions)"
        return 0
    fi

    local to_delete=$((total_count - max_versions))

    log_info "Retention: $total_count versions, removing $to_delete oldest"

    for ((i=0; i<to_delete; i++)); do
        local old_version="${versions[$i]}"
        local old_dir="$versions_dir/$old_version"

        log_warn "Removing old version: $old_version"
        rm -rf "$old_dir"
    done

    log_success "Retention applied: keeping last $max_versions versions"
}



cache_is_fresh() {
    local node="$1"
    local max_age="${2:-172800}"

    local current_dir="$ARTIFACTS_ROOT/$node/versions/v1"

    if [[ ! -d "$current_dir" ]]; then
        return 1
    fi

    local current_age_secs
    current_age_secs=$(($(date +%s) - $(stat -c %Y "$current_dir" 2>/dev/null || stat -f %m "$current_dir" 2>/dev/null || echo 0)))

    if (( current_age_secs < max_age )); then
        return 0
    else
        return 1
    fi
}
