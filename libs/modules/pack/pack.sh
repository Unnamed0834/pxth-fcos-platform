













set -euo pipefail

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"



source "$MY_DIR/config.sh"

source "$MY_DIR/engine.sh"

pack_list_nodes() {
    echo "Available nodes:"
    python3 "$PACK_LIB/list-nodes.py" --apps-dir "${APPS_DIR:-$REPO_ROOT/apps}"
}


pack_engine_path() {
    local node="$1"
    local ver_dir
    ver_dir=$(resolve_pack_ver_dir "$node") || return 1
    echo "$ver_dir"
}

pack_engine_status() {
    local node="$1"
    local manifest_file
    manifest_file=$(resolve_manifest "$node")

    if [[ ! -f "$manifest_file" ]]; then
        log_error "Manifest not found: $manifest_file"
        return 1
    fi

    log_heading "Pack Status: $node"

    local disk_raw headroom no_flatcar
    disk_raw=$(python3 "$PACK_LIB/parse-json-field.py" --file "$manifest_file" --field "oem.disk_raw")
    headroom=$(python3 "$PACK_LIB/parse-json-field.py" --file "$manifest_file" --field "oem.headroom")
    no_flatcar=$(python3 "$PACK_LIB/parse-json-field.py" --file "$manifest_file" --field "oem.no_flatcar")

    echo "  Disk:   ${disk_raw:-?}"
    echo "  Headroom: ${headroom} MB"
    echo "  No Flatcar: $no_flatcar"

    if [[ -n "$disk_raw" ]]; then
        local full_path="$ARTIFACTS_ROOT/$node/$disk_raw"
        if [[ -f "$full_path" ]]; then
            echo ""
            log_success "Disk exists: $full_path ($(du -h "$full_path" | cut -f1))"
        else
            echo ""
            log_warn "Disk not yet built: $full_path"
        fi
    fi
}

command="${1:-help}"
shift || true

case "$command" in
    nodes)
        pack_list_nodes
        ;;
    path)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 path <node>"
            exit 1
        fi
        pack_engine_path "${node%%:*}"
        ;;
    pack)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 pack <node>"
            exit 1
        fi
        node="${node%%:*}"

        echo "INFERENCE_ENGINE: ${INFERENCE_ENGINE:-llama-server (default)}"

        manifest_file=$(resolve_manifest "$node")
        if [[ ! -f "$manifest_file" ]]; then
            log_error "Manifest not found: $manifest_file"
            exit 1
        fi


        ver_dir=$(resolve_pack_ver_dir "$node") || exit 1

        if [[ ! -d "$ver_dir" ]]; then
            log_error "No cached artifacts for $node. Run: pcache sync $node"
            exit 1
        fi

        if ! pack_verify_cache_contract "$node" "$ver_dir"; then
            log_error "Cache contract verification failed — artifacts missing, modified or unsigned"
            log_error "Run: pcache verify $node  to diagnose"
            exit 1
        fi

        pack_engine_oem "$node" "$ver_dir"
        ;;
    status)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 status <node>"
            exit 1
        fi
        pack_engine_status "${node%%:*}"
        ;;
    help|--help|-h)
        echo "pxth-pack - OEM disk packing"
        echo ""
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  nodes              List all known nodes"
        echo "  path <node>        Print resolved ver directory path"
        echo "  pack <node>        Pack OEM disk from cached artifacts"
        echo "  status <node>      Show pack status summary"
        echo ""
        echo "Notes:"
        echo "  The bundle contains artifacts only. Runtime secrets are supplied"
        echo "  out-of-band to /run/secrets/<name>.env, never from the repository."
        echo "  Cache verification is fail-closed and requires PXTH_CACHE_HMAC_KEY"
        echo "  (or /run/secrets/pxth-cache-hmac.env)."
        echo ""
        echo "Examples:"
        echo "  $0 pack <node>"
        echo "  $0 nodes"
        echo "  $0 path <node>"
        ;;
    *)
        echo "Unknown command: $command"
        echo "Run: $0 help"
        exit 1
        ;;
esac
