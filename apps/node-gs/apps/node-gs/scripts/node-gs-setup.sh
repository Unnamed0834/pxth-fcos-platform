



set -euo pipefail

OEM_DIR="/var/oem"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE" >&2; }
    log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE" >&2; }
    log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }
    log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "$LOG_FILE" >&2; }
fi

cd /var/oem/scripts || {
    log_error "Cannot access /var/oem/scripts"
    exit 1
}





verify_system() {
    log_info "Phase 1: Verifying system..."

    local hostname=$(hostname)
    if [[ "$hostname" == node-gs-* ]]; then
        log_success "Hostname verified: $hostname"
    else
        log_warn "Hostname is $hostname, expected node-gs-*"
    fi

    if podman --version &>/dev/null; then
        log_success "Podman available"
    else
        log_error "Podman not available"
        exit 1
    fi

    if podman info &>/dev/null; then
        log_success "Podman daemon reachable"
    else
        log_warn "Podman daemon not reachable"
    fi

    if [[ -x /opt/bin/restic ]]; then
        log_success "Restic available at /opt/bin/restic"
    else
        log_warn "Restic not found at /opt/bin/restic (backups disabled)"
    fi

    log_success "System verification complete"
}





verify_arcane_agent() {
    log_info "Phase 2: Verifying arcane-edge-agent..."

    if podman ps --format '{{.Names}}' 2>/dev/null | grep -q "arcane-edge-agent"; then
        local status=$(podman inspect --format '{{.State.Status}}' arcane-edge-agent 2>/dev/null)
        log_success "arcane-edge-agent is $status"
    else
        log_warn "arcane-edge-agent not running"
    fi

    log_success "Arcane agent check complete"
}





setup_log_rotation() {
    log_info "Phase 3: Configuring log rotation..."

    cat > /etc/logrotate.d/node-gs-setup << 'EOFROTATE'
/var/log/node-gs-setup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOFROTATE

    log_success "Log rotation configured"
}





main() {
    log_info "========================================"
    log_info "node-gs Setup Starting"
    log_info "========================================"

    verify_system
    verify_arcane_agent
    setup_log_rotation

    log_info "========================================"
    log_info "Setup Complete"
    log_info "========================================"
    log_info ""
    log_info "Game server node is configured."
    log_info "Arcane headless agent should be running."
    log_info ""
    log_info "To check status:"
    log_info "  sudo -u containers XDG_RUNTIME_DIR=/run/user/5000 podman ps"
    log_info ""
    log_info "To check agent logs:"
    log_info "  sudo -u containers XDG_RUNTIME_DIR=/run/user/5000 podman logs arcane-edge-agent"
    log_info ""

    touch /etc/node-gs-setup-complete
}

main "$@"
