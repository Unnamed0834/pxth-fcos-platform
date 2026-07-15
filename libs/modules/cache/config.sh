



set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_ROOT="$SCRIPT_DIR"
CACHE_LIB="$SCRIPT_DIR/lib"
SHARED_LIB="$(cd "$SCRIPT_DIR/../../scripts/ci/lib" && pwd)"



source "$SHARED_LIB/module-config.sh" cache



source "$SHARED_LIB/logging.sh"




source "$SHARED_LIB/artifact-config.sh"
