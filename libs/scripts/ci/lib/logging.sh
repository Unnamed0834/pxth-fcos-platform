










LOG_FORMAT="${1:-standard}"
LOG_FILE="${LOG_FILE:-/var/log/setup.log}"

if [[ "$LOG_FORMAT" == "smoke" ]]; then
    log_info()    { echo "[INFO]    $*" >&2; }
    log_success() { echo "[PASS]    $*" >&2; }
    log_error()   { echo "[FAIL]    $*" >&2; }
    log_warn()    { echo "[WARN]    $*" >&2; }
else
    log_info() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
    }

    log_warn() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
    }

    log_error() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
    }

    log_success() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*" | tee -a "$LOG_FILE" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*" >&2
    }
fi

log_heading() {
    local title="$1"
    local width=40
    local line
    line=$(printf '%*s' "$width" '' | tr ' ' '=')
    log_info "$line"
    log_info "$title"
    log_info "$line"
}






log_init_fallback() {
    local fallback_log_file="${1:-/var/log/setup.log}"
    local success_tag="${2:-[✓]}"

    if type log_info &>/dev/null; then
        return 0
    fi

    log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$fallback_log_file" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2; }
    log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$fallback_log_file" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2; }
    log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$fallback_log_file" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }
    log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${success_tag} $*" | tee -a "$fallback_log_file" >&2 || echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${success_tag} $*" >&2; }
}








setup_log_rotation() {
    local log_pattern="$1"
    local rotate_count="${2:-7}"
    local extra_configs="${3:-}"

    local config_file="/etc/logrotate.d/setup-logs"

    cat > "$config_file" << EOFROTATE
$log_pattern {
    daily
    rotate $rotate_count
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        /bin/kill -HUP \$(cat /var/run/syslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOFROTATE

    if [[ -n "$extra_configs" ]]; then
        echo "" >> "$config_file"
        echo "$extra_configs" >> "$config_file"
    fi

    return 0
}






get_container_runtime() {
    if command -v docker &>/dev/null; then
        echo "docker"
    elif command -v podman &>/dev/null; then
        echo "podman"
    else
        return 1
    fi
}
