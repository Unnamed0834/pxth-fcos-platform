













set -euo pipefail

LOG_FILE="/var/log/workload.log"


LLAMA_SERVER_IMAGE="${LLAMA_SERVER_IMAGE:-}"
if [[ -z "$LLAMA_SERVER_IMAGE" ]]; then
    echo "ERROR: LLAMA_SERVER_IMAGE not set — expected from build configuration"
    exit 1
fi

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}


cleanup_stale_resources() {
    local pattern="$1"


    while IFS= read -r container; do
        if [[ -n "$container" ]]; then
            log "Removing stale container: $container"
            sudo ctr -n node-g1-llama containers remove "$container" 2>/dev/null || true
        fi
    done < <(sudo ctr -n node-g1-llama containers ls -q 2>/dev/null | grep "$pattern" || true)


    while IFS= read -r snapshot; do
        if [[ -n "$snapshot" ]]; then
            log "Removing stale snapshot: $snapshot"
            sudo ctr -n node-g1-llama snapshots rm "$snapshot" 2>/dev/null || true
        fi
    done < <(sudo ctr -n node-g1-llama snapshots ls -q 2>/dev/null | grep "$pattern" || true)
}

wait_for_nfs() {
    log "Waiting for NFS mount..."
    mount /mnt/gguf 2>/dev/null || true
    local attempts=0
    local max_attempts=180
    while [[ $attempts -lt $max_attempts ]]; do
        if ls /mnt/gguf/llm/*.gguf >/dev/null 2>&1; then
            log "NFS accessible with models (after ${attempts} attempts)"
            return 0
        fi
        if [[ $((attempts % 12)) -eq 0 ]]; then

            log "  Waiting for NFS... ($attempts/$max_attempts) - $(($attempts * 5 / 60)) min elapsed"
        fi
        sleep 5
        attempts=$((attempts + 1))
    done

    log "ERROR: NFS not accessible after $max_attempts attempts (15 minutes)"
    return 1
}

wait_for_model() {
    local model_path="$1"
    local model_name="$(basename "$model_path")"

    log "Waiting for model to be available: $model_name"
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if [[ -f "$model_path" ]]; then
            log "Model found: $model_name"
            return 0
        fi
        log "  Model not ready, waiting... ($attempts/30)"
        sleep 2
        ((attempts++))
    done

    log "ERROR: Model not found after waiting: $model_path"
    return 1
}

start_t4_workload() {
    log "========================================"
    log "Starting T4 Workload: Qwen3.5-122B"
    log "Tensor Parallel: 4 GPUs (0-3)"
    log "Port: 8000"
    log "========================================"

    cleanup_stale_resources "llama-server"

    if ! wait_for_nfs; then
        return 1
    fi


    local model="${QWEN_MODEL:-Qwen3.5-122B-A10B-UD-Q4_K_XL-00001-of-00003.gguf}"
    local model_path="/mnt/gguf/llm/$model"

    if ! wait_for_model "$model_path"; then
        return 1
    fi

    log "Starting 122B model on port 8000 (tensor parallel GPU 0-3)..."









    sudo ctr -n node-g1-llama run --rm --privileged --net-host \
        --device /dev/nvidia0 \
        --device /dev/nvidia1 \
        --device /dev/nvidia2 \
        --device /dev/nvidia3 \
        --mount type=bind,src=/mnt/gguf,dst=/models,options=rbind:ro \
        --mount type=bind,src=/usr/lib64,dst=/usr/lib64,options=rbind:ro \
        --env LD_LIBRARY_PATH=/usr/lib64:/usr/local/cuda/lib64 \
        --env CUDA_VISIBLE_DEVICES=0,1,2,3 \
        "$LLAMA_SERVER_IMAGE" \
        llama-server-t4 \
        /app/llama-server \
        -m /models/llm/$model \
        --host 0.0.0.0 \
        --port 8000 \
        -ngl 99 \
        --threads 32 \
        --batch-size 4096 \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --repeat-penalty 1.0 \
        --n-predict -1 \
        --reasoning on \
        --jinja &
    local ctr_pid=$!

    sleep 8
    if ! sudo ctr -n node-g1-llama tasks ls 2>/dev/null | grep -q "llama-server-t4"; then
        log "ERROR: llama-server-t4 container task not found after startup"
        wait "$ctr_pid" 2>/dev/null || true
        return 1
    fi
    log "T4 workload started: 122B on port 8000 (GPU 0-3)"
    log "========================================"
}

start_t2_workload() {
    log "========================================"
    log "Starting T2 Workload: Qwen3.6-35B-MTP (2 instances)"
    log "Instance 1: GPU 0-1, port 8000"
    log "Instance 2: GPU 2-3, port 8001"
    log "========================================"

    cleanup_stale_resources "llama-server"

    if ! wait_for_nfs; then
        return 1
    fi


    local model="${QWEN_MODEL:-Qwen3.6-35B-A3B-MTP-UD-Q6_K_XL.gguf}"
    local model_path="/mnt/gguf/llm/$model"

    if ! wait_for_model "$model_path"; then
        return 1
    fi


    log "Starting 35B instance 1 on port 8000 (tensor parallel GPU 0-1)..."









    sudo ctr -n node-g1-llama run --rm --privileged --net-host \
        --device /dev/nvidia0 \
        --device /dev/nvidia1 \
        --mount type=bind,src=/mnt/gguf,dst=/models,options=rbind:ro \
        --mount type=bind,src=/usr/lib64,dst=/usr/lib64,options=rbind:ro \
        --env LD_LIBRARY_PATH=/usr/lib64:/usr/local/cuda/lib64 \
        --env CUDA_VISIBLE_DEVICES=0,1 \
        "$LLAMA_SERVER_IMAGE" \
        llama-server-t2-0 \
        /app/llama-server \
        -m /models/llm/$model \
        --host 0.0.0.0 \
        --port 8000 \
        -ngl 99 -fa on -np 1 \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        --threads 16 \
        --batch-size 2048 \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --repeat-penalty 1.0 \
        --n-predict -1 \
        --reasoning on \
        --jinja &
    local ctr1_pid=$!
    sleep 8
    if ! sudo ctr -n node-g1-llama tasks ls 2>/dev/null | grep -q "llama-server-t2-0"; then
        log "ERROR: llama-server-t2-0 container task not found after startup"
        wait "$ctr1_pid" 2>/dev/null || true
        return 1
    fi
    log "Instance 1 started: 35B MTP on port 8000 (GPU 0-1)"
    sleep 10


    log "Starting 35B MTP instance 2 on port 8001 (tensor parallel GPU 2-3)..."









    sudo ctr -n node-g1-llama run --rm --privileged --net-host \
        --device /dev/nvidia2 \
        --device /dev/nvidia3 \
        --mount type=bind,src=/mnt/gguf,dst=/models,options=rbind:ro \
        --mount type=bind,src=/usr/lib64,dst=/usr/lib64,options=rbind:ro \
        --env LD_LIBRARY_PATH=/usr/lib64:/usr/local/cuda/lib64 \
        --env CUDA_VISIBLE_DEVICES=2,3 \
        "$LLAMA_SERVER_IMAGE" \
        llama-server-t2-1 \
        /app/llama-server \
        -m /models/llm/$model \
        --host 0.0.0.0 \
        --port 8001 \
        -ngl 99 -fa on -np 1 \
        --spec-type draft-mtp --spec-draft-n-max 2 \
        --threads 16 \
        --batch-size 2048 \
        --temp 0.6 \
        --top-p 0.95 \
        --top-k 20 \
        --repeat-penalty 1.0 \
        --n-predict -1 \
        --reasoning on \
        --jinja &
    local ctr2_pid=$!
    sleep 8
    if ! sudo ctr -n node-g1-llama tasks ls 2>/dev/null | grep -q "llama-server-t2-1"; then
        log "ERROR: llama-server-t2-1 container task not found after startup"
        wait "$ctr2_pid" 2>/dev/null || true
        return 1
    fi
    log "Instance 2 started: 35B on port 8001 (GPU 2-3)"
    log "========================================"
}

start_workload() {
    local preset="${WORKLOAD_PRESET:-T4}"

    log "Starting llama.cpp workload with preset: $preset"


    local gpu_name=$(nvidia-smi --query-gpu=gpu_name --format=csv,noheader | head -1)
    local gpu_count=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
    log "Detected: $gpu_count x $gpu_name"

    case "$preset" in
        T4|t4)
            start_t4_workload
            ;;
        T2|t2)
            start_t2_workload
            ;;
        *)
            log "ERROR: Unknown workload preset: $preset"
            log "Valid presets: T4 (default), T2"
            return 1
            ;;
    esac

    log "Workload startup complete"
}

set_preset() {
    local preset="$1"
    local model="$2"
    local config_file="/etc/node-g1-workload.conf"

    if [[ -z "$preset" ]]; then
        log "ERROR: Preset required. Usage: node-g1-workload.sh set T4|T2 [model_filename]"
        return 1
    fi


    if [[ "$preset" != "T4" && "$preset" != "T2" && "$preset" != "t4" && "$preset" != "t2" ]]; then
        log "ERROR: Invalid preset. Use T4 or T2"
        return 1
    fi

    preset=$(echo "$preset" | tr '[:lower:]' '[:upper:]')


    if [[ -z "$model" ]]; then
        if [[ "$preset" == "T4" ]]; then
            model="Qwen3.5-122B-A10B-UD-Q4_K_XL-00001-of-00003.gguf"
        else
            model="Qwen3.6-35B-A3B-MTP-UD-Q6_K_XL.gguf"
        fi
    fi


    cat > "$config_file" << EOF
WORKLOAD_PRESET=$preset
QWEN_MODEL=$model
EOF

    log "Workload preset set to: $preset"
    log "Model: $model"
    log "Config written to: $config_file"
    log "Reboot or run 'node-g1-workload.sh start' to apply"
}

stop_workload() {
    log "Stopping llama.cpp workloads..."
    sudo ctr -n node-g1-llama tasks ls 2>/dev/null | grep llama-server | awk '{print $1}' | xargs -r sudo ctr -n node-g1-llama tasks kill --signal SIGKILL || true
    sudo ctr -n node-g1-llama containers ls 2>/dev/null | grep llama-server | awk '{print $1}' | xargs -r sudo ctr -n node-g1-llama containers rm || true
    log "Workloads stopped"
}

status_workload() {
    log "Checking workload status..."
    sudo ctr -n node-g1-llama containers ls 2>/dev/null | grep llama-server || echo "No workloads running"
}

case "${1:-start}" in
    start)
        start_workload
        ;;
    stop)
        stop_workload
        ;;
    status)
        status_workload
        ;;
    set)
        set_preset "$2" "$3"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|set}"
        echo ""
        echo "Commands:"
        echo "  start  - Start workload based on /etc/node-g1-workload.conf"
        echo "  stop   - Stop all workloads"
        echo "  status - Show current workload status"
        echo "  set    - Set persistent preset (requires reboot or restart)"
        echo ""
        echo "Set command: $0 set T4|T2 [model_filename]"
        echo ""
        echo "Examples:"
        echo "  $0 set T4  # Use 122B model (default)"
        echo "  $0 set T2  # Use 35B dual instance"
        echo "  $0 set T2 Qwen3.6-35B-A3B-MTP-UD-Q6_K_XL.gguf  # Custom model"
        exit 1
        ;;
esac
