








set -euo pipefail



source "$(dirname "${BASH_SOURCE[0]}")/lib/downloader.sh"

source "$(dirname "${BASH_SOURCE[0]}")/lib/container.sh"

source "$(dirname "${BASH_SOURCE[0]}")/lib/s3.sh"

source "$(dirname "${BASH_SOURCE[0]}")/lib/versioner.sh"

source "$(dirname "${BASH_SOURCE[0]}")/build/caddy.sh"







cache_load_manifest() {
    local node="$1"
    local manifest_file
    manifest_file=$(resolve_manifest "$node")

    if [[ ! -f "$manifest_file" ]]; then
        log_error "Manifest not found: $manifest_file"
        log_error "Run: pcache nodes  (to see available nodes)"
        return 1
    fi

    CACHE_MANIFEST_FILE="$manifest_file"
    CACHE_MANIFEST_DIR="$(dirname "$manifest_file")"
    return 0
}





cache_engine_path() {
    local node="$1"

    if ! cache_load_manifest "$node"; then
        return 1
    fi


    local cache_node="$node"
    local cache_ref
    cache_ref=$(python3 "$CACHE_LIB/get-cache-ref.py" --manifest "$CACHE_MANIFEST_FILE") || return 1
    [[ -n "$cache_ref" ]] && cache_node="$cache_ref"

    local ver_dir
    ver_dir=$(resolve_ver_dir "$cache_node")
    echo "$ver_dir"
}





cache_require_hmac_key() {
    local key_file="${PXTH_CACHE_HMAC_KEY_FILE:-/run/secrets/pxth-cache-hmac.env}"
    if [[ -z "${PXTH_CACHE_HMAC_KEY:-}" ]] && [[ ! -f "$key_file" ]]; then
        log_error "Cache HMAC key is not available"
        log_error "Set PXTH_CACHE_HMAC_KEY (64 hex chars) or provision $key_file"
        log_error "The key is delivered out-of-band; it is never stored in the repository."
        return 1
    fi
    return 0
}





cache_engine_sync() {
    local node="$1"
    local force="${2:-false}"

    if ! cache_load_manifest "$node"; then
        return 1
    fi
    cache_require_hmac_key || return 1

    log_heading "Artifact Sync: $node"


    local cache_node="$node"
    local cache_ref
    cache_ref=$(python3 "$CACHE_LIB/get-cache-ref.py" --manifest "$CACHE_MANIFEST_FILE") || return 1
    [[ -n "$cache_ref" ]] && cache_node="$cache_ref"


    MAX_AGE="${MAX_AGE:-172800}"
    if [[ "$force" != "true" ]] && cache_is_fresh "$cache_node" "$MAX_AGE"; then
        local ver_dir
        ver_dir=$(resolve_ver_dir "$cache_node")
        log_info "Current version is fresh (checking for missing artifacts...)"
        local errors=0
        if _pcache_sync_artifacts "$node" "$ver_dir"; then :; else errors=$?; fi

        _pcache_write_cache_manifest "$node" "$ver_dir"
        if (( errors == 0 )); then
            log_success "Resumed sync complete: $node/versions/v1"
        else
            log_warn "Resumed sync complete with $errors errors: $node/versions/v1"
        fi
        return $errors
    else
        local ver_dir
        ver_dir=$(resolve_ver_dir "$cache_node" 2>/dev/null) || ver_dir=""
        if [[ -n "$ver_dir" ]] && [[ -d "$ver_dir" ]]; then
            local ver_age
            ver_age=$(($(date +%s) - $(stat -c %Y "$ver_dir" 2>/dev/null || echo 0)))
            ver_age=$((ver_age / 86400))
            log_info "Current version is stale (${ver_age} days old), creating new version"
        else
            log_info "No current version found, creating new version"
        fi
    fi


    local new_version
    new_version=$(cache_create_new_version "$cache_node")
    ver_dir="$ARTIFACTS_ROOT/$cache_node/versions/$new_version"


    _pcache_init_ver_structure "$node" "$ver_dir"


    local errors=0
    if _pcache_sync_artifacts "$node" "$ver_dir"; then :; else errors=$?; fi


    cache_apply_retention "$cache_node"


    _pcache_write_cache_manifest "$node" "$ver_dir"

    if (( errors == 0 )); then
        log_success "Artifact sync complete: $node/$new_version"
    else
        log_warn "Artifact sync complete with $errors errors: $node/$new_version"
    fi
    log_heading "Artifact sync complete"

    return $errors
}


_pcache_init_ver_structure() {
    local node="$1"
    local ver_dir="$2"

    CACHE_MANIFEST_FILE="$CACHE_MANIFEST_FILE" VER_DIR="$ver_dir" python3 "$CACHE_LIB/init-ver-structure.py"

    log_info "Version directory initialized: $ver_dir"
}


_pcache_sync_artifacts() {
    local node="$1"
    local ver_dir="$2"
    local errors=0


    local artifact_keys
    artifact_keys=$(python3 "$CACHE_LIB/resolve-artifacts.py" --manifest "$CACHE_MANIFEST_FILE")

    if [[ -z "$artifact_keys" ]]; then
        log_warn "No artifacts defined in manifest for $node"
        return 0
    fi


    local build_dests
    build_dests=$(CACHE_MANIFEST_FILE="$CACHE_MANIFEST_FILE" python3 -c "
import json, os, sys
m = json.load(open(os.environ['CACHE_MANIFEST_FILE']))
for k, a in m.get('artifacts', {}).items():
    if a.get('type') == 'build':
        print(a.get('dest', ''))
")

    while IFS= read -r key; do
        [[ -z "$key" ]] && continue

        local art_type art_url art_dest art_image art_min_size art_digests_url art_digests_asc art_hash_algo art_gpg_key art_digest art_bucket art_s3_key art_endpoint
        IFS='|' read -r art_type art_url art_dest art_image art_min_size art_digests_url art_digests_asc art_hash_algo art_gpg_key art_digest art_bucket art_s3_key art_endpoint <<< \
            "$(python3 "$CACHE_LIB/resolve-artifacts.py" --manifest "$CACHE_MANIFEST_FILE" --key "$key")"

        local dest_path="$ver_dir/$art_dest"

        case "$art_type" in
            url)
                if [[ -n "$art_digests_url" ]]; then

                    if ! cache_download_signed_file "$art_url" "$dest_path" "$art_digests_url" "$art_digests_asc" "${art_hash_algo:-sha512}" "${art_min_size:-$MIN_SIZE_BINARY}" "${art_gpg_key:-flatcar}"; then
                        errors=$((errors + 1))
                    fi
                else
                    if ! cache_download_file "$art_url" "$dest_path" "" "${art_min_size:-$MIN_SIZE_BINARY}"; then
                        errors=$((errors + 1))
                    fi
                fi
                ;;
            s3)

                local s3_endpoint="${art_endpoint:-}"
                if [[ -n "${art_digests_url:-}" ]]; then

                    if ! cache_s3_download_signed "${art_bucket}" "${art_s3_key}" "$dest_path" "$s3_endpoint" "${art_digests_url}" "${art_digests_asc:-}" "${art_hash_algo:-sha512}" "${art_min_size:-$MIN_SIZE_BINARY}" "${art_gpg_key:-flatcar}"; then
                        errors=$((errors + 1))
                    fi
                else
                    if ! cache_s3_download "${art_bucket}" "${art_s3_key}" "$dest_path" "$s3_endpoint" "${art_min_size:-$MIN_SIZE_BINARY}"; then
                        errors=$((errors + 1))
                    fi
                fi
                ;;
            container)

                local skip_container=false
                while IFS= read -r bdest; do
                    [[ -z "$bdest" ]] && continue
                    if [[ "$dest_path" == "$ver_dir/$bdest"/* ]]; then
                        skip_container=true
                        break
                    fi
                done <<< "$build_dests"
                if [[ "$skip_container" == "true" ]]; then
                    log_info "Skipping container $art_image (overridden by build: $key)"
                    continue
                fi
                if ! cache_download_image "$art_image" "$ver_dir/containers" "$key" "${art_digest:-}"; then
                    errors=$((errors + 1))
                fi
                ;;
            build)

                case "$key" in
                    caddy)
                        if ! cache_build_caddy_cloudflare "$ver_dir" "${art_digest:-}" "$key"; then
                            log_warn "Caddy Cloudflare build failed, using standard image"
                            errors=$((errors + 1))
                        fi
                        ;;
                    *)
                        log_warn "Unknown build artifact type: $key, skipping"
                        ;;
                esac
                ;;
            *)
                log_warn "Unknown artifact type '$art_type' for $key, skipping"
                ;;
        esac
    done <<< "$artifact_keys"

    return $errors
}


_pcache_write_cache_manifest() {
    local node="$1"
    local ver_dir="$2"
    local manifest_path="$ver_dir/.cache-manifest.json"

    if ! python3 "$CACHE_LIB/write-cache-manifest.py" \
        --manifest "$manifest_path" \
        --ver-dir "$ver_dir" \
        --node "$node" \
        --source-manifest "$CACHE_MANIFEST_FILE"; then
        log_error "Failed to write/sign cache manifest: $manifest_path"
        return 1
    fi

    log_info "Cache manifest written and HMAC-signed: $manifest_path"
}





cache_engine_verify() {
    local node="$1"

    if ! cache_load_manifest "$node"; then
        return 1
    fi
    cache_require_hmac_key || return 1


    local cache_node="$node"
    local cache_ref
    cache_ref=$(python3 "$CACHE_LIB/get-cache-ref.py" --manifest "$CACHE_MANIFEST_FILE") || return 1
    [[ -n "$cache_ref" ]] && cache_node="$cache_ref"

    local ver_dir
    ver_dir=$(resolve_ver_dir "$cache_node") || return 1

    log_heading "Verification: $node"

    local manifest_path="$ver_dir/.cache-manifest.json"

    if [[ ! -f "$manifest_path" ]]; then
        log_error "No cache manifest found at $manifest_path"
        log_error "Verification is fail-closed. Run: pcache sync $node"
        return 1
    fi


    python3 "$CACHE_LIB/verify-cache.py" \
        --manifest "$manifest_path" \
        --ver-dir "$ver_dir" \
        --source-manifest "$CACHE_MANIFEST_FILE"
    return $?
}
