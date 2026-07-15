





set -euo pipefail


OEM_DIR="/var/oem"
LOG_FILE="/var/log/node-g1-setup.log"
NVIDIA_RUNTIME_BIN="/usr/bin/nvidia-container-runtime"


CTRD_NAMESPACE="node-g1-vllm"


export PATH="/usr/bin:/bin:/usr/sbin:/sbin"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    log_init_fallback "$LOG_FILE"
fi


cd /var/oem/scripts || {
    log_error "Cannot access /var/oem/scripts"
    exit 1
}





wait_for_nvidia_driver() {
    local max_attempts="${1:-30}"
    local wait_time="${2:-1}"
    local attempts=0

    while [[ $attempts -lt $max_attempts ]]; do
        if nvidia-smi -L &>/dev/null; then
            return 0
        fi
        sleep $wait_time
        ((attempts++))
    done
    return 1
}





install_driver() {
    log_info "Phase 0: Waiting for NVIDIA driver (prebuilt sysext)..."

    if [[ -f /etc/node-g1-driver-installed ]]; then
        log_info "Driver already verified, skipping"
        return 0
    fi



    log_info "Waiting for NVIDIA driver from sysext..."
    if wait_for_nvidia_driver 30 1; then
        log_success "NVIDIA driver ready (prebuilt from sysext)"
        log_info "Driver version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
        touch /etc/node-g1-driver-installed
        return 0
    fi


    log_info "Attempting to load NVIDIA modules..."
    modprobe nvidia 2>/dev/null || true
    modprobe nvidia-uvm 2>/dev/null || true

    if wait_for_nvidia_driver 20 1; then
        log_success "NVIDIA driver ready (after module load)"
        log_info "Driver version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
        touch /etc/node-g1-driver-installed
        return 0
    fi

    log_error "Timeout waiting for NVIDIA driver after 50 seconds"
    log_error "Check: systemd-sysext status && lsmod | grep nvidia"
    return 1
}





install_sysext() {
    log_info "Phase 1: Verifying NVIDIA sysexts..."

    if [[ -f /etc/node-g1-sysext-installed ]]; then
        log_info "Sysexts already verified, skipping"
        return 0
    fi



    if [[ ! -f /etc/extensions/flatcar-nvidia-drivers-570-open.raw ]]; then
        log_error "NVIDIA driver sysext not found at /etc/extensions/flatcar-nvidia-drivers-570-open.raw"
        log_error "Should have been installed by nvidia-sysexts-install.service"
        return 1
    fi
    log_success "NVIDIA driver sysext verified"


    if [[ ! -f /etc/extensions/nvidia-runtime.raw ]]; then
        log_error "NVIDIA runtime sysext not found at /etc/extensions/nvidia-runtime.raw"
        log_error "Should have been installed by nvidia-sysexts-install.service"
        return 1
    fi
    log_success "NVIDIA runtime sysext verified"


    log_info "Checking if NVIDIA sysexts are active..."
    if systemd-sysext status 2>/dev/null | grep -q "flatcar-nvidia-drivers"; then
        log_success "NVIDIA driver sysext is active"
    else
        log_warn "NVIDIA driver sysext not active, attempting refresh..."
        systemd-sysext refresh 2>/dev/null || log_error "Sysext refresh failed"
    fi

    if systemd-sysext status 2>/dev/null | grep -q "nvidia-runtime"; then
        log_success "NVIDIA runtime sysext is active"
    else
        log_warn "NVIDIA runtime sysext not detected"
    fi


    log_info "Starting containerd..."
    systemctl enable --now containerd


    log_info "Waiting for containerd socket..."
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if [[ -S /run/containerd/containerd.sock ]]; then
            log_success "Containerd socket ready"
            break
        fi
        sleep 2
        ((attempts++))
    done

    if [[ $attempts -eq 30 ]]; then
        log_error "Containerd socket not available after 60 seconds"
        return 1
    fi

    log_success "NVIDIA sysexts verified, containerd running"
    touch /etc/node-g1-sysext-installed
}





configure_nvidia_toolkit() {
    log_info "Phase 2: Configuring NVIDIA Container Toolkit..."

    if [[ -f /etc/node-g1-toolkit-configured ]]; then
        log_info "NVIDIA toolkit already configured, skipping"
        return 0
    fi



    NVIDIA_RUNTIME_BIN="/usr/bin/nvidia-container-runtime"

    if [[ ! -x "$NVIDIA_RUNTIME_BIN" ]]; then
        log_warn "nvidia-container-runtime not found at $NVIDIA_RUNTIME_BIN"
        log_warn "GPU containers will use manual device mounting"
    else
        log_info "Found nvidia-container-runtime at $NVIDIA_RUNTIME_BIN"


        local ctrd_config="/etc/containerd/config.toml"
        mkdir -p /etc/containerd

        if [[ ! -f "$ctrd_config" ]]; then

            cat > "$ctrd_config" << 'EOFCTRD'
version = 2
[plugins."io.containerd.grpc.v1.cri"]
  [plugins."io.containerd.grpc.v1.cri".containerd]
    default_runtime_name = "nvidia"
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
          BinaryName = "/usr/bin/nvidia-container-runtime"
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
EOFCTRD

            log_success "Created containerd config with NVIDIA runtime"


            ln -sf "$ctrd_config" /etc/containerd/config-nvidia.toml


            systemctl restart containerd
            sleep 2
        else
            log_info "Containerd config exists, checking for NVIDIA runtime..."
            if ! grep -q "nvidia" "$ctrd_config" 2>/dev/null; then
                log_warn "Existing containerd config may not have NVIDIA runtime"
            fi

            ln -sf "$ctrd_config" /etc/containerd/config-nvidia.toml 2>/dev/null || true
        fi
    fi

    touch /etc/node-g1-toolkit-configured
}





set_power_limits() {
    log_info "Phase 3: Setting GPU power limits to 200W..."

    log_info "Waiting for NVIDIA driver (up to 60 seconds)..."

    if ! wait_for_nvidia_driver 30 2; then
        log_error "NVIDIA driver not available after 60 seconds"
        return 1
    fi
    log_success "NVIDIA driver ready"


    local gpu_count=0
    local gpu_list=()


    while IFS= read -r line; do
        if [[ "$line" =~ GPU[[:space:]]+([0-9]+) ]]; then
            gpu_list+=("${BASH_REMATCH[1]}")
            ((gpu_count++))
        fi
    done < <(nvidia-smi -L 2>/dev/null)

    if [[ $gpu_count -eq 0 ]]; then
        log_error "No GPUs detected"
        return 1
    fi

    log_info "Found $gpu_count GPU(s)"


    local success_count=0
    for gpu_id in "${gpu_list[@]}"; do
        if nvidia-smi -i "$gpu_id" -pl 200 &>/dev/null; then
            log_success "GPU $gpu_id: 200W limit set"
            ((success_count++))
        else
            log_warn "GPU $gpu_id: Failed to set power limit"
        fi
    done

    if [[ $success_count -eq 0 ]]; then
        log_error "Failed to set power limits on any GPU"
        return 1
    fi

    log_success "Power limits set on $success_count/$gpu_count GPU(s)"


    local gpu_devices=""
    for gpu_id in "${gpu_list[@]}"; do
        gpu_devices+=" $gpu_id"
    done


    log_info "Enabling persistence mode on GPUs..."
    for gpu_id in "${gpu_list[@]}"; do
        if nvidia-smi -i "$gpu_id" -pm 1 &>/dev/null; then
            log_success "GPU $gpu_id: Persistence mode enabled"
        else
            log_warn "GPU $gpu_id: Failed to enable persistence mode"
        fi
    done


    log_info "Starting nvidia-persistenced service..."
    if command -v nvidia-persistenced &>/dev/null; then

        if [[ ! -f /etc/systemd/system/nvidia-persistenced.service ]]; then
            cat > /etc/systemd/system/nvidia-persistenced.service << 'EOF'
[Unit]
Description=NVIDIA Persistence Daemon
After=nvidia-sysexts-install.service

[Service]
Type=forking
ExecStart=/usr/bin/nvidia-persistenced --user root --verbose
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        fi
        systemctl daemon-reload
        systemctl enable --now nvidia-persistenced.service || log_warn "Failed to start nvidia-persistenced"
    else
        log_warn "nvidia-persistenced not found in PATH"
    fi


    local exec_start_lines=""
    for gpu_id in "${gpu_list[@]}"; do
        exec_start_lines="${exec_start_lines}ExecStart=/bin/bash -c '/usr/bin/nvidia-smi -i ${gpu_id} -pl 200 || true'
"
    done

    cat > /etc/systemd/system/nvidia-power-limit.service << EOF
[Unit]
Description=NVIDIA GPU Power Limit (200W per GPU)
After=nvidia-sysexts-install.service nvidia-persistenced.service
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="PATH=/usr/bin:/bin"
ExecStartPre=/bin/bash -c 'for i in {1..30}; do if pgrep -x nvidia-persistenced >/dev/null 2>&1 || systemctl is-active --quiet nvidia-persistenced; then echo "nvidia-persistenced ready"; exit 0; fi; sleep 1; done; echo "Warning: nvidia-persistenced may not be ready"'
${exec_start_lines}ExecStartPost=/bin/bash -c 'echo "Power limits set:"; /usr/bin/nvidia-smi -q -d POWER | grep "Current Power Limit"'

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nvidia-power-limit.service
    systemctl start nvidia-power-limit.service || log_warn "Power limit service failed to start, will apply on next boot"
    log_success "Power limit service configured and started"
}





mount_nfs() {
    log_info "Phase 4: Mounting NFS for GGUF models..."

    mkdir -p /mnt/gguf


    if ! grep -q "assets/gguf" /etc/fstab 2>/dev/null; then
        echo "${NFS_SERVER:-198.51.100.10}:/mnt/storage/private/assets/gguf /mnt/gguf nfs4 ro,bg,soft,timeo=60,_netdev,x-systemd.requires=network-online.target,x-systemd.mount-timeout=120 0 0" >> /etc/fstab
    fi


    (
        while true; do
            if mountpoint -q /mnt/gguf 2>/dev/null; then
                exit 0
            fi
            mount /mnt/gguf 2>/dev/null && exit 0
            sleep 60
        done
    ) &

    log_success "NFS mount started (background retry)"
}





setup_vllm() {
    log_info "Phase 6: Importing vLLM container..."

    local vllm_image_tar="$OEM_DIR/containers/vllm/vllm-openai-v0.21.0-cu129-ubuntu2404.tar"
    if [[ -z "${VLLM_IMAGE:-}" ]]; then
        log_error "VLLM_IMAGE not set — expected from build configuration"
        return 1
    fi
    local vllm_image_ref="$VLLM_IMAGE"

    if [[ ! -f "$vllm_image_tar" ]]; then
        log_info "vLLM container image not found in OEM - skipping vLLM import"
        return 0
    fi

    log_info "Loading vLLM container image into containerd..."


    if ! ctr -n "$CTRD_NAMESPACE" namespace ls 2>/dev/null | grep -q "$CTRD_NAMESPACE"; then
        log_info "Creating containerd namespace: $CTRD_NAMESPACE"
        ctr namespace create "$CTRD_NAMESPACE" 2>/dev/null || true
    fi


    if ! ctr -n "$CTRD_NAMESPACE" images import "$vllm_image_tar" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Failed to import vLLM image"
        return 0
    fi

    log_success "vLLM image imported: $vllm_image_ref"
    log_info "Namespace: $CTRD_NAMESPACE"
    log_info ""
    log_info "To run vLLM manually:"
    log_info "  sudo ctr -n node-g1-vllm run --rm --privileged --net-host \\"
    log_info "    --device /dev/nvidia0 --device /dev/nvidia1 --device /dev/nvidia2 --device /dev/nvidia3 \\"
    log_info "    --env CUDA_VISIBLE_DEVICES=0,1,2,3 \\"
    log_info "    $vllm_image_ref vllm \\"
    log_info "    vllm serve --model <model-path> --tensor-parallel-size 4 --host 0.0.0.0 --port 8000"
}





setup_llama_server() {
    log_info "Phase 6b: Setting up llama-server (GGUF container)..."


    local llama_image_tar=""
    local llama_image_ref=""

    if [[ -f "$OEM_DIR/containers/llama-server/llama.cpp-server-cuda12-b9592.tar" ]]; then
        llama_image_tar="$OEM_DIR/containers/llama-server/llama.cpp-server-cuda12-b9592.tar"
        if [[ -z "${LLAMA_SERVER_IMAGE:-}" ]]; then
               log_error "LLAMA_SERVER_IMAGE not set — expected from build configuration"
            return 1
        fi
        llama_image_ref="$LLAMA_SERVER_IMAGE"
    else

        llama_image_tar=$(find "$OEM_DIR/containers/llama-server" -name "*.tar" -type f 2>/dev/null | head -1)
        if [[ -n "$llama_image_tar" ]]; then
            if [[ -z "${LLAMA_SERVER_IMAGE:-}" ]]; then
           log_error "LLAMA_SERVER_IMAGE not set — expected from build configuration"
                return 1
            fi
            llama_image_ref="$LLAMA_SERVER_IMAGE"
        fi
    fi

    if [[ -z "$llama_image_tar" || ! -f "$llama_image_tar" ]]; then
        log_info "llama-server container image not found in OEM - skipping llama import"
        return 0
    fi

    log_info "Loading llama-server container image into containerd..."
    log_info "Image file: $(basename "$llama_image_tar")"

    local llama_namespace="node-g1-llama"
    ctr namespace create "$llama_namespace" 2>/dev/null || true

    if ! ctr -n "$llama_namespace" images import "$llama_image_tar" 2>&1 | tee -a "$LOG_FILE"; then
        log_warn "Failed to import llama-server container"
        return 0
    fi

    log_success "llama-server image imported: $llama_image_ref"
    log_info "Namespace: $llama_namespace"
    log_info ""
    log_info "Example command to run GGUF models:"
    log_info "  sudo ctr -n node-g1-llama run --rm --privileged --net-host \\"
    log_info "    --device /dev/nvidia0 --device /dev/nvidia1 --device /dev/nvidia2 --device /dev/nvidia3 \\"
    log_info "    --mount type=bind,src=/path/to/models,dst=/models,options=rbind:ro \\"
    log_info "    --mount type=bind,src=/opt/nvidia/current/usr/lib64,dst=/usr/lib64/nvidia,options=rbind:ro \\"
    log_info "    --env LD_LIBRARY_PATH=/usr/lib64/nvidia:/usr/local/cuda/lib64 \\"
    log_info "    $llama_image_ref mymodel \\"
    log_info "    /app/llama-server -m /models/<model.gguf> --host 0.0.0.0 --port 8000 -ngl 99"
}






enable_services() {
    log_info "Phase 8: Enabling services..."


    systemctl daemon-reload

    log_success "Services enabled"
}





verify_setup() {
    log_info "Phase 9: Verifying setup..."

    local errors=0


    if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null; then
        log_success "NVIDIA driver working"
    else
        log_error "NVIDIA driver not working"
        errors=$((errors + 1))
    fi


    if [[ -S /run/containerd/containerd.sock ]]; then
        log_success "Containerd socket exists"
    else
        log_error "Containerd socket not found"
        errors=$((errors + 1))
    fi


    if [[ -f /etc/extensions/nvidia-runtime.raw ]]; then
        log_success "NVIDIA sysext installed"
    else
        log_warn "NVIDIA sysext not found in /etc/extensions"
    fi


    if mountpoint -q /mnt/models-gguf 2>/dev/null || mountpoint -q /mnt/models-safetensors 2>/dev/null; then
        log_success "NFS mounts active"
    else
        log_warn "NFS mounts not yet active (will auto-mount on access)"
    fi


    case "$engine" in
        vllm)
            if ctr -n "$CTRD_NAMESPACE" images ls 2>/dev/null | grep -q "vllm-openai"; then
                log_success "vLLM image available in containerd"
            else
                log_error "vLLM image not loaded"
                errors=$((errors + 1))
            fi
            ;;
        llama-server)
            if ctr -n node-g1-llama images ls 2>/dev/null | grep -q "llama.cpp"; then
                log_success "llama-server image available in containerd"
            else
                log_error "llama-server image not loaded"
                errors=$((errors + 1))
            fi
            ;;
    esac

    return $errors
}





main() {
    log_heading "GPU INFERENCE NODE - CONTAINERD SETUP"
    log_info "Starting GPU node configuration..."
    log_info ""


    local failures=0


    if ! install_driver; then
        log_error "Phase 0 failed: NVIDIA driver installation"
        failures=$((failures + 1))
    fi


    if ! install_sysext; then
        log_error "Phase 1 failed: Sysext installation"
        failures=$((failures + 1))
    fi


    if ! configure_nvidia_toolkit; then
        log_warn "Phase 2 failed: NVIDIA toolkit configuration (non-critical)"
    fi


    if ! set_power_limits; then
        log_warn "Phase 3 failed: Power limits (non-critical)"
    fi


    if ! mount_nfs; then
        log_warn "Phase 4 failed: NFS configuration (non-critical)"
    fi


    local engine="${INFERENCE_ENGINE:-llama-server}"
    case "$engine" in
        vllm)
            if ! setup_vllm; then
                log_error "Phase 6 failed: vLLM setup"
                failures=$((failures + 1))
            fi
            ;;
        llama-server)
            if ! setup_llama_server; then
                log_error "Phase 6 failed: llama-server setup"
                failures=$((failures + 1))
            fi
            ;;
        *)
            log_error "Unknown INFERENCE_ENGINE: $engine (expected vllm or llama-server)"
            failures=$((failures + 1))
            ;;
    esac


    local vllm_extra='/var/log/vllm/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
}'
    if ! setup_log_rotation "/var/log/node-g1-setup.log" 7 "$vllm_extra"; then
        log_warn "Phase 7 failed: Log rotation (non-critical)"
    fi


    enable_services || log_warn "Phase 8 had issues (non-critical)"


    if ! verify_setup; then
        log_warn "Phase 9: Verification found issues (review above)"
    fi


    if [[ $failures -eq 0 ]]; then
        touch /etc/node-g1-setup-complete
        log_success "Setup marked complete"
    else
        log_warn "Setup completed with $failures failures"
    fi

    log_info ""
    log_heading "GPU Setup Complete!"
    log_info "Inference engine: $engine"
    log_info "Services configured:"
    log_info "  ✓ nvidia-power-limit.service (200W per GPU)"
    log_info "  ✓ nfs-mount-monitor.service"
    log_info "  ✓ ${engine}.service (auto-started in ready mode)"
    log_info ""
    log_info "Management commands:"
    log_info "  Setup Logs:         sudo journalctl -u node-g1-setup -f"
    log_info ""
    case "$engine" in
        vllm)
            log_info "To load a model in vLLM:"
            log_info "  sudo ctr -n node-g1-vllm exec vllm vllm --model /mnt/models-gguf/llm/<model> \\n    --tensor-parallel-size 4 --host 0.0.0.0 --port 8000"
            log_info ""
            log_info "API Endpoint:"
            log_info "  vLLM:      http://198.51.100.51:8000 (requires manual model load)"
            ;;
        llama-server)
            log_info "To run llama-server (GGUF):"
            log_info "  llama-server-run.sh /mnt/models-gguf/llm/<model.gguf> [port]"
            log_info "  Example: llama-server-run.sh /mnt/models-gguf/llm/Qwen3.6-35B-A3B-MTP-UD-Q6_K_XL.gguf 8080"
            log_info ""
            log_info "API Endpoint:"
            log_info "  llama:     http://198.51.100.51:8080 (manual start, GGUF support)"
            ;;
    esac
    echo ""

    return $((failures > 0 ? 1 : 0))
}


main "$@"
