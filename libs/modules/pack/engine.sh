









set -euo pipefail



source "$(dirname "${BASH_SOURCE[0]}")/lib/bundler.sh"

source "$(dirname "${BASH_SOURCE[0]}")/lib/disk-builder.sh"





PACK_MANIFEST_FILE=""
PACK_MANIFEST_DIR=""


pack_resolve_temp_dir() {
    local node="$1"
    echo "$ARTIFACTS_ROOT/$node/.tmp"
}


pack_resolve_upload_dir() {
    local node="$1"
    echo "$ARTIFACTS_ROOT/$node/upload"
}


pack_load_manifest() {
    local node="$1"
    local manifest_file
    manifest_file=$(resolve_manifest "$node")

    if [[ ! -f "$manifest_file" ]]; then
        log_error "Manifest not found: $manifest_file"
        return 1
    fi

    PACK_MANIFEST_FILE="$manifest_file"
    PACK_MANIFEST_DIR="$(dirname "$manifest_file")"
    return 0
}






resolve_pack_cache_node() {
    local node="$1"
    if ! pack_load_manifest "$node"; then
        return 1
    fi


    local cache_ref
    cache_ref=$(CACHE_MANIFEST_FILE="$PACK_MANIFEST_FILE" python3 -c '
import json, os, re, sys
try:
    with open(os.environ["CACHE_MANIFEST_FILE"], encoding="utf-8") as handle:
        ref = json.load(handle).get("cache_ref", "")
except (OSError, ValueError) as exc:
    print(f"resolve_pack_cache_node: {exc}", file=sys.stderr)
    sys.exit(1)
if not isinstance(ref, str):
    sys.exit(1)
if ref and not re.match(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", ref):
    print(f"resolve_pack_cache_node: unsafe cache_ref: {ref!r}", file=sys.stderr)
    sys.exit(1)
print(ref)
') || return 1

    if [[ -n "$cache_ref" ]]; then
        echo "$cache_ref"
    else
        echo "$node"
    fi
}


resolve_pack_ver_dir() {
    local node="$1"
    local cache_node
    cache_node=$(resolve_pack_cache_node "$node") || return 1
    resolve_ver_dir "$cache_node"
}







pack_verify_cache_contract() {
    local node="$1"
    local ver_dir="$2"

    if ! pack_load_manifest "$node"; then
        return 1
    fi

    local cache_manifest="$ver_dir/.cache-manifest.json"

    if [[ ! -f "$cache_manifest" ]]; then
        log_error "No cache manifest found at $cache_manifest"
        log_error "Cache contract verification is fail-closed. Run: pcache sync $node"
        return 1
    fi

    log_heading "Cache Contract Verification: $node"

    python3 "$PACK_LIB/verify-contract.py" \
        --cache-manifest "$cache_manifest" \
        --manifest "$PACK_MANIFEST_FILE" \
        --ver-dir "$ver_dir" \
        --inference-engine "${INFERENCE_ENGINE:-}"
    return $?
}





pack_engine_oem() {
    local node="$1"
    shift
    local ver_dir="${1:-}"
    shift || true
    local extra_args="${*:-}"

    if ! pack_load_manifest "$node"; then
        return 1
    fi

    if [[ -z "$ver_dir" ]]; then
        log_error "ver_dir not provided. Pass the resolved version directory path."
        return 1
    fi
    if [[ ! -d "$ver_dir" ]]; then
        log_error "No cached artifacts for $node: $ver_dir"
        return 1
    fi


    local spec_path="${APPS_DIR}/${node}/node-spec.json"
    local is_multi_node=false
    local node_names=()

    if [[ -f "$spec_path" ]]; then
        local nodes_json
        if nodes_json=$(python3 "$PACK_LIB/list_subnodes.py" --spec "$spec_path"); then
            if [[ -n "$nodes_json" ]]; then
                is_multi_node=true
                while IFS= read -r nname; do
                    [[ -z "$nname" ]] && continue
                    node_names+=("$nname")
                done <<< "$nodes_json"
            fi
        fi
    fi


    local oem_vals
    oem_vals=$(PACK_MANIFEST_FILE="$PACK_MANIFEST_FILE" python3 -c '
import json, os
with open(os.environ["PACK_MANIFEST_FILE"], encoding="utf-8") as handle:
    oem = json.load(handle).get("oem", {})
print(oem.get("disk_raw", ""))
print(oem.get("tarball", ""))
print(oem.get("headroom", 64))
print(oem.get("no_flatcar", False))
')
    local oem_disk_raw="" oem_tarball="" oem_headroom="64" oem_no_flatcar="False"
    {
        read -r oem_disk_raw || true
        read -r oem_tarball || true
        read -r oem_headroom || true
        read -r oem_no_flatcar || true
    } <<< "$oem_vals"

    if [[ "$oem_no_flatcar" == "True" ]]; then
        export OEM_NO_FLATCAR="true"
    fi

    local artifact_prefix="${node//-/_}"

    if [[ "$is_multi_node" == "true" ]]; then
        _pack_engine_oem_multi "$node" "$ver_dir" "$oem_headroom" "$artifact_prefix" "${node_names[@]}"
        return $?
    fi

    _pack_engine_oem_single "$node" "$ver_dir" "$oem_headroom" "$artifact_prefix" "$oem_disk_raw" "$oem_tarball"
}


_pack_engine_oem_single() {
    local node="$1"
    local ver_dir="$2"
    local oem_headroom="$3"
    local artifact_prefix="$4"
    local oem_disk_raw="$5"
    local oem_tarball="$6"

    log_heading "OEM Build: $node"
    log_info "Using cached artifacts: $ver_dir"

    oem_disk_raw="$ARTIFACTS_ROOT/$node/$oem_disk_raw"
    oem_tarball="$ARTIFACTS_ROOT/$node/$oem_tarball"

    local temp_dir
    temp_dir=$(pack_resolve_temp_dir "$node")
    local upload_dir
    upload_dir=$(pack_resolve_upload_dir "$node")
    rm -rf "$temp_dir" "$upload_dir"
    mkdir -p "$temp_dir" "$upload_dir"

    local oem_tarball_tmp="$temp_dir/${node}.tar.gz"

    log_heading "Packing OEM Bundle"
    local bundle_dir="$temp_dir/bundle"
    export INFERENCE_ENGINE="${INFERENCE_ENGINE:-}"
    pack_pack_bundle "$bundle_dir" "$PACK_MANIFEST_FILE" "$ver_dir"
    log_success "Bundle packed: $(du -sh "$bundle_dir" | cut -f1)"

    pack_create_tarball "$bundle_dir" "$oem_tarball_tmp"
    pack_create_disk "$oem_tarball_tmp" "$temp_dir/${node}.img" "$oem_headroom"


    local tarball_sha256 tarball_size
    tarball_sha256=$(sha256sum "$oem_tarball_tmp" | awk '{print $1}')
    tarball_size=$(stat -c%s "$oem_tarball_tmp" 2>/dev/null || stat -f%z "$oem_tarball_tmp" 2>/dev/null || echo "0")


    local flatcar_src="$ver_dir/images/flatcar/flatcar_production_proxmoxve_image.img"
    local flatcar_dest="$upload_dir/${artifact_prefix}_flatcar_production_proxmoxve_image.qcow2"
    pack_create_flatcar_symlink "$flatcar_src" "$flatcar_dest" || true


    local oem_metadata_json="$temp_dir/oem-metadata.json"
    if [[ -n "$tarball_sha256" ]] && [[ "$tarball_size" -gt 0 ]]; then
        python3 "$PACK_LIB/oem_metadata.py" write \
            --node "$node" \
            --sha256 "$tarball_sha256" \
            --size "$tarball_size" \
            --output "$oem_metadata_json"
        log_success "OEM tarball metadata written to $oem_metadata_json"
        log_info "  SHA256: $tarball_sha256"
        log_info "  Size:   $tarball_size bytes"
    else
        log_error "Could not compute tarball hash/bytes; refusing to publish metadata"
        return 1
    fi

    local oem_disk_dest="$upload_dir/${artifact_prefix}_oem_disk.raw"
    cp "$temp_dir/${node}.img" "$oem_disk_dest"

    if [[ -f "$oem_metadata_json" ]]; then
        cp "$oem_metadata_json" "$upload_dir/oem-metadata.json"
        log_info "Preserved oem-metadata.json to $upload_dir/"
    fi

    rm -rf "$temp_dir"

    log_heading "OEM Build Complete: $node"
    log_info "Disk: $oem_disk_raw"
    log_info "Upload: $upload_dir"
}


_pack_engine_oem_multi() {
    local node="$1"
    local ver_dir="$2"
    shift 2
    local oem_headroom="$1"
    shift
    local artifact_prefix="$1"
    shift
    local subnodes=("$@")

    log_heading "OEM Build (Multi-Node): $node"
    log_info "Subnodes: ${subnodes[*]}"
    log_info "Using cached artifacts: $ver_dir"

    local temp_dir
    temp_dir=$(pack_resolve_temp_dir "$node")
    local upload_dir
    upload_dir=$(pack_resolve_upload_dir "$node")
    rm -rf "$temp_dir" "$upload_dir"
    mkdir -p "$temp_dir" "$upload_dir"

    local flatcar_src="$ver_dir/images/flatcar/flatcar_production_proxmoxve_image.img"
    local flatcar_dest="$upload_dir/${artifact_prefix}_flatcar_production_proxmoxve_image.qcow2"
    pack_create_flatcar_symlink "$flatcar_src" "$flatcar_dest" || true

    local metadata_accum="$temp_dir/.metadata-accum.json"
    printf '{}\n' > "$metadata_accum"

    for subnode in "${subnodes[@]}"; do
        echo ""
        log_heading "OEM Build: $node/$subnode"

        local subnode_temp="$temp_dir/$subnode"
        rm -rf "$subnode_temp"
        mkdir -p "$subnode_temp"

        local oem_tarball_tmp="$subnode_temp/${subnode}.tar.gz"

        log_heading "Packing OEM Bundle"
        local bundle_dir="$subnode_temp/bundle"
        export INFERENCE_ENGINE="${INFERENCE_ENGINE:-}"
        pack_pack_bundle "$bundle_dir" "$PACK_MANIFEST_FILE" "$ver_dir" "$subnode"
        log_success "Bundle packed: $(du -sh "$bundle_dir" | cut -f1)"

        pack_create_tarball "$bundle_dir" "$oem_tarball_tmp"
        pack_create_disk "$oem_tarball_tmp" "$subnode_temp/${subnode}.img" "$oem_headroom"

        local tarball_sha256 tarball_size
        tarball_sha256=$(sha256sum "$oem_tarball_tmp" | awk '{print $1}')
        tarball_size=$(stat -c%s "$oem_tarball_tmp" 2>/dev/null || stat -f%z "$oem_tarball_tmp" 2>/dev/null || echo "0")

        if [[ -n "$tarball_sha256" ]] && [[ "$tarball_size" -gt 0 ]]; then
            local oem_metadata_json="$subnode_temp/oem-metadata-${subnode}.json"
            python3 "$PACK_LIB/oem_metadata.py" write \
                --node "$subnode" \
                --sha256 "$tarball_sha256" \
                --size "$tarball_size" \
                --output "$oem_metadata_json"

            python3 "$PACK_LIB/oem_metadata.py" add \
                --accum "$metadata_accum" \
                --node "$subnode" \
                --sha256 "$tarball_sha256" \
                --size "$tarball_size"

            log_success "OEM metadata for $subnode written to $oem_metadata_json"
            log_info "  SHA256: $tarball_sha256"
            log_info "  Size:   $tarball_size bytes"
        else
            log_error "Could not compute tarball hash/bytes for $subnode"
            return 1
        fi

        local oem_disk_dest="$upload_dir/${subnode}_oem_disk.raw"
        cp "$subnode_temp/${subnode}.img" "$oem_disk_dest"
        log_success "OEM disk for $subnode: $oem_disk_dest"

        rm -rf "$subnode_temp"
    done

    local oem_metadata_json="$temp_dir/oem-metadata.json"
    python3 "$PACK_LIB/oem_metadata.py" finalize \
        --accum "$metadata_accum" \
        --output "$oem_metadata_json"
    cp "$oem_metadata_json" "$upload_dir/oem-metadata.json"
    log_info "Combined OEM metadata written to $upload_dir/oem-metadata.json"

    rm -rf "$temp_dir"

    log_heading "OEM Build Complete: $node (${#subnodes[@]} nodes)"
    log_info "Upload: $upload_dir"
}
