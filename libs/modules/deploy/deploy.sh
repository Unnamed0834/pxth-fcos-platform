









set -euo pipefail

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


source "$MY_DIR/config.sh"

source "$MY_DIR/engine.sh"

command="${1:-help}"
shift || true

case "$command" in
    nodes)
        echo "Available nodes:"
        python3 "$SCRIPTS_LIB/list-nodes.py" --apps-dir "${APPS_DIR:-$REPO_ROOT/apps}"
        ;;
    deploy)
        node="${1:-}"
        if [[ -z "$node" ]]; then
            echo "Usage: $0 deploy <node>"
            exit 1
        fi
        if [[ "${DESTROY:-0}" == "1" && "${DESTROY_CONFIRM:-}" != "yes" ]]; then
            echo "ERROR: DESTROY=1 requires DESTROY_CONFIRM=yes" >&2
            exit 1
        fi
        deploy_engine_run "$node"
        ;;
    help|--help|-h)
        echo "pxth-deploy - VM deployment orchestration"
        echo ""
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  nodes              List all known nodes"
        echo "  deploy <node>      Deploy a node (or fleet)"
        echo ""
        echo "Environment:"
        echo "  SOPS_AGE_KEY_FILE  Path to SOPS age key"
        echo "  COMMON_SECRETS_DIR Path to shared secrets (pve/, tofu/)"
        echo "  COMMON_VARS_DIR    Path to shared variables"
        echo "  SECRETS_PATH       Path to S3 tfstate secrets for node"
        echo ""
        echo "Safety (all default to non-destructive):"
        echo "  PLAN_ONLY=1        Plan and save for review; do not apply"
        echo "  DESTROY=1          Opt in to teardown (requires DESTROY_CONFIRM=yes)"
        echo "  DESTROY_CONFIRM=yes Explicit second confirmation for destroy"
        ;;
    *)
        echo "Unknown command: $command"
        echo "Run: $0 help"
        exit 1
        ;;
esac
