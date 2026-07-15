



set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$SCRIPT_DIR"
DEPLOY_LIB="$SCRIPT_DIR/lib"
SCRIPTS_LIB="$(cd "$SCRIPT_DIR/../../scripts/lib" && pwd)"
SHARED_LIB="$(cd "$SCRIPT_DIR/../../scripts/ci/lib" && pwd)"


source "$SHARED_LIB/module-config.sh" deploy


source "$SHARED_LIB/artifact-config.sh"
