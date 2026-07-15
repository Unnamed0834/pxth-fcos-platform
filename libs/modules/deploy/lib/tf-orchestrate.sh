
















set -euo pipefail

deploy_tf_orchestrate() {
    local node="$1"


    umask 077

    local tofu_bin
    tofu_bin="$(command -v tofu 2>/dev/null || printf '%s' 'tofu')"

    local apps_dir="${APPS_DIR:-$REPO_ROOT/apps}"


    cp -r "$DEPLOY_ROOT/../tofu" "$TF_WORK_DIR/"


    export TF_WORK_DIR NODE APPS_DIR
    export MANIFEST_PATH="${apps_dir}/${node}/manifest.json"
    export SPEC_PATH="${apps_dir}/${node}/node-spec.json"
    export PROJECT_ROOT="${REPO_ROOT}"
    export SECRETS_DIR="${REPO_ROOT}/secrets"
    export RESOLVED_SECRETS_JSON RESOLVED_VARIABLES_JSON
    bash "$SCRIPTS_LIB/tf-config.sh"




    local var_file
    var_file="$(mktemp "$TF_WORK_DIR/.tofu-secrets.XXXXXX")"
    chmod 600 "$var_file"
    deploy_secret_files+=("$var_file")




    python3 - "$var_file" <<'PY'
import json
import os
import sys

secrets = json.loads(os.environ.get("RESOLVED_SECRETS_JSON", "{}") or "{}")
variables = json.loads(os.environ.get("RESOLVED_VARIABLES_JSON", "{}") or "{}")

repo_root = os.path.abspath(os.environ["PROJECT_ROOT"])
node = os.environ["NODE"]
artifacts_root = os.path.join(repo_root, "artifacts")
artifacts_dir = os.path.join(artifacts_root, node)
version = str(variables.get("cache_manifest_version", ""))

variables["artifacts_root"] = artifacts_root
variables["artifacts_dir"] = artifacts_dir
variables["cache_manifest_path"] = os.path.join(
    artifacts_dir, "versions", version, ".cache-manifest.json"
)
variables["oem_metadata_path"] = os.path.join(
    artifacts_dir, "upload", "oem-metadata.json"
)

payload = {
    "resolved_secrets": secrets,
    "resolved_variables": variables,
}

with open(sys.argv[1], "w") as handle:
    json.dump(payload, handle)
PY



    local -a values=()
    mapfile -d '' -t values < <(python3 - <<'PY'
import json
import os
import sys

secrets = json.loads(os.environ.get("RESOLVED_SECRETS_JSON", "{}") or "{}")
variables = json.loads(os.environ.get("RESOLVED_VARIABLES_JSON", "{}") or "{}")

fields = [
    variables.get("pve_url", ""),
    secrets.get("api_token", ""),
    secrets.get("private_key", ""),
    variables.get("ssh_public_key", ""),
    variables.get("region", ""),
    variables.get("datastore_os", ""),
    variables.get("datastore_vm", ""),
    variables.get("datastore_snippet", ""),
    variables.get("interface", ""),
    variables.get("node", ""),
    variables.get("pve_node_ip", ""),
    variables.get("cache_manifest_version", ""),
    variables.get("ignition_config_pattern", ""),
]
sys.stdout.buffer.write(b"\0".join(str(v).encode() for v in fields) + b"\0")
PY
)
    if [[ ${#values[@]} -ne 13 ]]; then
        echo "ERROR: Failed to parse resolved secrets/variables" >&2
        exit 1
    fi

    local PVE_URL="${values[0]}"
    local PVE_TOKEN="${values[1]}"
    local SSH_PRIVATE_KEY="${values[2]}"
    local SSH_PUBLIC_KEY="${values[3]}"
    local S3_STATE_REGION="${values[4]}"
    local DATASTORE_OS="${values[5]}"
    local DATASTORE_VM="${values[6]}"
    local DATASTORE_SNIPPET="${values[7]}"
    local PVE_INTERFACE="${values[8]}"
    local PVE_NODE="${values[9]}"
    local PVE_NODE_IP="${values[10]}"
    local CACHE_MANIFEST_VERSION="${values[11]}"
    local IGNITION_CONFIG_PATTERN="${values[12]}"
    unset values


    export TF_VAR_apps_dir="$apps_dir"
    export TF_VAR_proxmox_api_url="$PVE_URL"
    export TF_VAR_proxmox_api_token="$PVE_TOKEN"
    export TF_VAR_proxmox_node="$PVE_NODE"
    export TF_VAR_proxmox_node_ip="$PVE_NODE_IP"
    export TF_VAR_ssh_private_key_content="$SSH_PRIVATE_KEY"
    export TF_VAR_ssh_public_key="$SSH_PUBLIC_KEY"
    export TF_VAR_s3_state_region="$S3_STATE_REGION"
    export TF_VAR_s3_state_access_key="${S3_ACCESS_KEY:-}"
    export TF_VAR_s3_state_secret_key="${S3_SECRET_KEY:-}"
    export TF_VAR_datastore_os="$DATASTORE_OS"
    export TF_VAR_datastore_vm="$DATASTORE_VM"
    export TF_VAR_datastore_snippet="$DATASTORE_SNIPPET"
    export TF_VAR_interface="$PVE_INTERFACE"
    export TF_VAR_cache_manifest_version="$CACHE_MANIFEST_VERSION"
    export TF_VAR_ignition_config_pattern="$IGNITION_CONFIG_PATTERN"
    if [[ -n "${S3_ENDPOINT:-}" ]]; then
        export TF_VAR_s3_state_endpoint="$S3_ENDPOINT"
    fi
    if [[ -n "${S3_BUCKET:-}" ]]; then
        export TF_VAR_s3_state_bucket="$S3_BUCKET"
    fi


    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY:-}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY:-}"
    export AWS_DEFAULT_REGION="$S3_STATE_REGION"
    export AWS_REGION="$S3_STATE_REGION"



    local -a BACKEND_CONFIG=()
    if [[ -n "$S3_STATE_REGION" ]]; then
        BACKEND_CONFIG+=("-backend-config=region=$S3_STATE_REGION")
    fi
    if [[ -n "${S3_ENDPOINT:-}" ]]; then
        BACKEND_CONFIG+=("-backend-config=endpoint=${S3_ENDPOINT#*://}")
    fi
    if [[ -n "${S3_BUCKET:-}" ]]; then
        BACKEND_CONFIG+=("-backend-config=bucket=$S3_BUCKET")
    fi
    BACKEND_CONFIG+=("-backend-config=key=${node}/terraform.tfstate")

    local -a TOFU_COMMON_ARGS=("-input=false" "-var-file=$var_file")

    cd "$TF_WORK_DIR"

    "$tofu_bin" init -input=false "${BACKEND_CONFIG[@]}"




    local destroy=0
    if [[ "${DESTROY:-0}" == "1" ]]; then
        if [[ "${DESTROY_CONFIRM:-}" != "yes" ]]; then
            echo "ERROR: DESTROY=1 requires DESTROY_CONFIRM=yes" >&2
            exit 1
        fi
        destroy=1
    fi
    if [[ "$destroy" == "1" ]]; then
        echo "DESTROY confirmed: tearing down existing $node infrastructure"
        "$tofu_bin" destroy -auto-approve "${TOFU_COMMON_ARGS[@]}"
    fi




    local plan_file="$TF_WORK_DIR/tfplan"
    "$tofu_bin" plan -out="$plan_file" "${TOFU_COMMON_ARGS[@]}"

    if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
        echo "Plan saved (not applied): $plan_file"
        return 0
    fi

    "$tofu_bin" apply -input=false "$plan_file"


    rm -f -- "$var_file"
}
