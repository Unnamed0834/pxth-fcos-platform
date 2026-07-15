


















set -euo pipefail

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"



source "$MY_DIR/config.sh"

source "$MY_DIR/engine.sh"







_load_s3_credentials() {
    local secret_file="${PXTH_S3_ENV_FILE:-/run/secrets/s3-flatcar.env}"

    if [[ ! -f "$secret_file" ]] && [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        log_info "No S3 credentials provisioned; continuing with URL/container artifacts"
        return 0
    fi
    if [[ -f "$secret_file" ]]; then
        local line key value
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            [[ -z "$line" ]] && continue
            key="${line%%=*}"
            value="${line#*=}"
            key="${key//[[:space:]]/}"
            value="${value#\"}"; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"
            case "$key" in
                AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)
                    export "$key=$value"
                    ;;
            esac
        done < "$secret_file"
    fi

    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] || [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "S3 credentials not available"
        log_error "Export AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or provision"
        log_error "${secret_file} via systemd credentials (out-of-band)."
        return 1
    fi
    return 0
}





cache_engine_status() {
    local node="$1"

    if ! cache_load_manifest "$node"; then
        return 1
    fi

    local ver_dir
    ver_dir=$(cache_engine_path "$node") || return 1

    log_heading "Cache Status: $node"

    if [[ ! -d "$ver_dir" ]]; then
        log_error "No cached artifacts for $node"
        return 1
    fi

    local manifest_path="$ver_dir/.cache-manifest.json"
    python3 "$CACHE_LIB/status-display.py" \
        --manifest "$manifest_path" \
        --ver-dir "$ver_dir" \
        --node "$node"
}





command="${1:-help}"
shift || true

case "$command" in
    nodes)
        echo "Available nodes:"
        python3 "$CACHE_LIB/list-nodes.py" --apps-dir "${APPS_DIR:-$REPO_ROOT/apps}"
        ;;
    path)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 path <node>"
            exit 1
        fi
        path_node="${node%%:*}"
        cache_engine_path "$path_node"
        ;;
    sync)
        node="${1:-}"
        force="${2:-false}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 sync <node> [force]"
            exit 1
        fi

        sync_node="${node%%:*}"
        _load_s3_credentials || true
        cache_engine_sync "$sync_node" "$force"
        ;;
    verify)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 verify <node>"
            exit 1
        fi
        verify_node="${node%%:*}"
        cache_engine_verify "$verify_node"
        ;;
    status)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 status <node>"
            exit 1
        fi
        status_node="${node%%:*}"
        cache_engine_status "$status_node"
        ;;
    help|--help|-h)
        echo "pxth-cache - Artifact cache management"
        echo ""
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  nodes              List all known nodes"
        echo "  path <node>        Print resolved ver directory path"
        echo "  sync <node> [force] Sync artifacts for node"
        echo "  verify <node>      Verify artifacts for node (fail-closed)"
        echo "  status <node>      Show cache status summary"
        echo ""
        echo "OEM/disk operations: use pxth-pack module instead"
        echo ""
        echo "Runtime secrets: AWS_* from environment or /run/secrets/s3-flatcar.env;"
        echo "PXTH_CACHE_HMAC_KEY from environment or /run/secrets/pxth-cache-hmac.env."
        echo ""
        echo "Examples:"
        echo "  $0 sync <node>"
        echo "  $0 path <node>"
        echo "  $0 verify <node>"
        ;;
    *)
        echo "Unknown command: $command"
        echo "Run: $0 help"
        exit 1
        ;;
esac
