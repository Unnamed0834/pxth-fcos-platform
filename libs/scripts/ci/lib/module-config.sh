









MODULE_NAME="${1:-}"
if [[ -z "$MODULE_NAME" ]]; then
    echo "ERROR: module-config.sh requires a module name argument" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_ROOT="$(cd "$SCRIPT_DIR/../../../modules/$MODULE_NAME" && pwd)"
MODULE_LIB="$MODULE_ROOT/lib"


if [[ -n "${APPS_DIR:-}" ]]; then
    REPO_ROOT="$(dirname "$APPS_DIR")"
else
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi
