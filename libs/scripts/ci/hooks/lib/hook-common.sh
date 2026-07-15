














set -euo pipefail

HOOK_TITLE="${HOOK_TITLE:-Hook checks}"
HOOK_ERRORS=0


HOOK_REPO_ROOT="${HOOK_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)}"

hook_skip() { echo "SKIP: $1"; return 0; }
hook_fail() { echo "ERROR: $1"; HOOK_ERRORS=$((HOOK_ERRORS + 1)); }
hook_ok()   { echo "OK: $1"; }
hook_exit() {
    if [[ $HOOK_ERRORS -gt 0 ]]; then
        echo "$HOOK_ERRORS check(s) failed."
        exit 1
    fi
    echo "$HOOK_TITLE: all checks passed."
}
