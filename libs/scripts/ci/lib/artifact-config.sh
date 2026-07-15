





if ! type log_error &>/dev/null; then
    log_error() { echo "[ERROR] $*" >&2; }
fi





ARTIFACTS_ROOT="$REPO_ROOT/artifacts"
ARTIFACT_MAX_VERSIONS=3
MIN_SIZE_BINARY=1048576
MIN_SIZE_IMAGE=10485760
DOWNLOAD_TIMEOUT=300






resolve_manifest() {
    local node="$1"
    echo "${APPS_DIR:-$REPO_ROOT/apps}/$node/manifest.json"
}







resolve_ver_dir() {
    local node="$1"
    local versions_dir="$ARTIFACTS_ROOT/$node/versions"
    local version="${CACHE_MANIFEST_VERSION:-v1}"

    if [[ -d "$versions_dir/$version" ]]; then
        echo "$versions_dir/$version"
    else
        log_error "No version directory found for $node at $versions_dir/$version"
        log_error "Run: pcache sync $node to download artifacts first"
        return 1
    fi
}
