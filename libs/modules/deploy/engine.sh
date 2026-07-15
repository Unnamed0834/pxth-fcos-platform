









source "$(dirname "${BASH_SOURCE[0]}")/lib/workspace.sh"

source "$(dirname "${BASH_SOURCE[0]}")/lib/tf-orchestrate.sh"

DEPLOY_DISCOVER_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/lib/discover-nodes.py"





deploy_discover_nodes() {
    local base_node="$1"
    local spec_path="${APPS_DIR}/${base_node}/node-spec.json"

    if [[ ! -f "$spec_path" ]]; then
        echo "$base_node"
        return
    fi

    local nodes_json
    nodes_json=$(python3 "$DEPLOY_DISCOVER_SCRIPT" --spec-path "$spec_path" 2>/dev/null || true)

    if [[ -n "$nodes_json" ]]; then
        echo "$nodes_json"
    else
        echo "$base_node"
    fi
}





deploy_resolve_secrets() {
    local node="$1"
    echo "Resolving secrets..."
    RESOLVED_SECRETS_JSON=$(APP_NAME="$node" python3 "$SCRIPTS_LIB/resolve-secrets.py" \
        2>/dev/null)


    export RESOLVED_SECRETS_JSON
}

deploy_resolve_variables() {
    local node="$1"
    echo "Resolving variables..."
    local contract_dir
    contract_dir="$(dirname "$COMMON_VARS_DIR")"
    RESOLVED_VARIABLES_JSON=$(VARS_DIR="${contract_dir}/variables" NODE="$node" \
        python3 "$SCRIPTS_LIB/resolve-variables.py" \
        2>/dev/null)
    export RESOLVED_VARIABLES_JSON
}









deploy_validate_secrets() {
    local node="$1"
    local missing
    missing=$(python3 - <<'PY'
import json
import os
import sys

required = ("api_token", "pve_root_password", "private_key")
secrets = json.loads(os.environ.get("RESOLVED_SECRETS_JSON", "{}") or "{}")
missing = [name for name in required if not str(secrets.get(name, "")).strip()]
if missing:
    print(",".join(missing))
PY
)
    if [[ -n "$missing" ]]; then
        echo "ERROR: Required secret(s) not resolved: $missing" >&2
        exit 1
    fi
    echo "Secret presence validation passed for $node"
}

deploy_validate_variables() {
    local node="$1"
    local missing
    missing=$(python3 - <<'PY'
import json
import os

required = (
    "pve_url", "ssh_public_key", "datastore_os", "datastore_vm",
    "datastore_snippet", "interface", "cache_manifest_version",
    "ignition_config_pattern",
)
variables = json.loads(os.environ.get("RESOLVED_VARIABLES_JSON", "{}") or "{}")
missing = [name for name in required if not str(variables.get(name, "")).strip()]
if missing:
    print(",".join(missing))
PY
)
    if [[ -n "$missing" ]]; then
        echo "ERROR: Required variable(s) not resolved: $missing" >&2
        exit 1
    fi
}





deploy_engine_run() {
    local node="$1"

    deploy_workspace_setup "$node"
    deploy_resolve_secrets "$node"
    deploy_resolve_variables "$node"
    deploy_validate_secrets "$node"
    deploy_validate_variables "$node"
    deploy_tf_orchestrate "$node"

    echo "✓ $NODE node deployed"
}
