







deploy_tmp=""
TF_PLUGIN_CACHE_DIR=""



declare -a deploy_secret_files=()

deploy_cleanup() {
    local f
    for f in "${deploy_secret_files[@]-}"; do
        if [[ -n "${f:-}" ]]; then
            rm -f -- "$f" 2>/dev/null || true
        fi
    done
    if [[ -n "$deploy_tmp" && -d "$deploy_tmp" ]]; then
        rm -rf -- "$deploy_tmp"
    fi
}





deploy_extract_s3_creds() {
    if [[ -z "${SECRETS_PATH:-}" || ! -f "$SECRETS_PATH" ]]; then
        S3_ACCESS_KEY=""
        S3_SECRET_KEY=""
        S3_ENDPOINT=""
        S3_BUCKET=""
        return
    fi

    echo "Extracting S3 credentials from $SECRETS_PATH..."
    local s3_creds_json
    s3_creds_json=$(export SOPS_AGE_KEY_FILE="$SOPS_AGE_KEY_FILE" && sops -d "$SECRETS_PATH" 2>/dev/null | python3 -c "
import json, sys, yaml

data = yaml.safe_load(sys.stdin)
s3_config = {}

def find_s3(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, dict) and 'access_key_id' in v:
                s3_config.update({
                    'access_key': v.get('access_key_id', ''),
                    'secret_key': v.get('secret_access_key', ''),
                    'endpoint': v.get('endpoint', ''),
                    'bucket': v.get('bucket', '')
                })
            elif isinstance(v, dict):
                find_s3(v)

find_s3(data)
print(json.dumps(s3_config))
" 2>/dev/null)

    if [[ -n "$s3_creds_json" ]]; then
        S3_ACCESS_KEY=$(echo "$s3_creds_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_key',''))")
        S3_SECRET_KEY=$(echo "$s3_creds_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('secret_key',''))")
        S3_ENDPOINT=$(echo "$s3_creds_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('endpoint',''))")
        S3_BUCKET=$(echo "$s3_creds_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('bucket',''))")
    else
        echo "ERROR: Failed to extract S3 credentials from $SECRETS_PATH"
        exit 1
    fi
}





deploy_workspace_setup() {
    local node="$1"


    if [[ -z "${SOPS_AGE_KEY_FILE:-}" ]]; then
        echo "ERROR: SOPS_AGE_KEY_FILE not set"
        exit 1
    fi
    if [[ -z "${COMMON_SECRETS_DIR:-}" ]]; then
        echo "ERROR: COMMON_SECRETS_DIR not set"
        exit 1
    fi
    if [[ -z "${COMMON_VARS_DIR:-}" ]]; then
        echo "ERROR: COMMON_VARS_DIR not set"
        exit 1
    fi


    local project_root="${REPO_ROOT}"


    deploy_extract_s3_creds


    UPLOAD_DIR="$project_root/artifacts/$node/upload"
    mkdir -p "$UPLOAD_DIR"


    deploy_tmp="$(cd "$DEPLOY_ROOT" && pwd)/.tmp"
    mkdir -p "$deploy_tmp"
    TF_WORK_DIR=$(mktemp -d "$deploy_tmp/tofu-XXXXXX")
    NODE="$node"


    trap deploy_cleanup EXIT

    echo "Creating temporary Terraform workspace..."


    mkdir -p "${TF_PLUGIN_CACHE_DIR:-$deploy_tmp/tf-plugin-cache}"
}
