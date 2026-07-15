



set -euo pipefail


OEM_DIR="/var/oem"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE" >&2; }
    log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE" >&2; }
    log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2; }
    log_success() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [✓] $*" | tee -a "$LOG_FILE" >&2; }
fi


cd /var/oem/scripts || {
    log_error "Cannot access /var/oem/scripts"
    exit 1
}





verify_system() {
    log_info "Phase 1: Verifying system..."

    if [[ "$(hostname)" == "node-gw1" ]]; then
        log_success "Hostname verified: node-gw1"
    else
        log_warn "Hostname is $(hostname), expected node-gw1"
    fi

    if ip addr show eth0 | grep -q "203.0.113.20"; then
        log_success "Network configured correctly"
    else
        log_warn "Network may not be configured as expected"
    fi

    if [[ -x /opt/bin/zerotier-one ]]; then
        log_success "ZeroTier binary available"
    else
        log_warn "ZeroTier binary not found at /opt/bin/zerotier-one"
    fi

    log_success "System verification complete"
}





configure_services() {
    log_info "Phase 2: Configuring services..."

    systemctl enable sshd 2>/dev/null || true

    if [[ -x /opt/bin/restic ]]; then
        log_success "Restic available at /opt/bin/restic"
    else
        log_warn "Restic not found at /opt/bin/restic (backups disabled)"
    fi


    if [[ -x /opt/bin/zerotier-cli ]]; then
        log_info "Checking ZeroTier gateway configuration..."


        if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" == "1" ]]; then
            log_success "IP forwarding enabled"
        else
            log_warn "IP forwarding disabled - gateway routing may not work"
        fi


        if /opt/bin/zerotier-cli info >/dev/null 2>&1; then
            log_success "ZeroTier service responding"
            log_info "ZeroTier status: $(/opt/bin/zerotier-cli info)"
        else
            log_warn "ZeroTier service not responding"
        fi


        networks=$(/opt/bin/zerotier-cli listnetworks 2>/dev/null || echo "")
        if [[ -n "$networks" ]]; then
            log_info "ZeroTier networks:"
            echo "$networks" | while IFS= read -r line; do
                log_info "  $line"
            done
        else
            log_warn "No ZeroTier networks joined"
        fi
    else
        log_warn "ZeroTier CLI not available"
    fi

    log_success "Services configured"
}





setup_log_rotation() {
    log_info "Phase 3: Configuring log rotation..."

    cat > /etc/logrotate.d/node-gw1-setup << 'EOFROTATE'
/var/log/node-gw1-setup.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    sharedscripts
    postrotate
        /bin/kill -HUP $(cat /var/run/syslogd.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOFROTATE

    log_success "Log rotation configured"
}





main() {
    log_info "========================================"
    log_info "NODE Gateway Setup Starting"
    log_info "========================================"

    verify_system
    configure_services
    setup_log_rotation

    log_info "========================================"
    log_info "Setup Complete"
    log_info "========================================"
    log_info ""
    log_info "NODE Gateway is configured."
    log_info "ZeroTier native service should start automatically."
    log_info ""
    log_info "To check status:"
    log_info "  sudo systemctl status zerotier-one.service"
    log_info "  sudo systemctl status node-gw1-routing-setup.service"
    log_info ""
    log_info "To check logs:"
    log_info "  sudo journalctl -u zerotier-one -f"
    log_info "  sudo journalctl -u node-gw1-routing-setup -f"
    log_info ""
    log_info "To check ZeroTier network status:"
    log_info "  sudo /opt/bin/zerotier-cli status"
    log_info "  sudo /opt/bin/zerotier-cli listnetworks"
    log_info ""
    log_info "To manage gateway routing:"
    log_info "  sudo /opt/bin/zerotier-cli set 0000000000000000 allowGlobal=1  # Enable gateway mode"
    log_info "  sudo cat /proc/sys/net/ipv4/ip_forward                         # Check forwarding (should be 1)"
    log_info "  ip route show | grep zt                                        # Show ZeroTier routes"
    log_info "  ip addr show | grep zt                                         # Show ZeroTier interface"
    log_info ""

    touch /etc/node-gw1-setup-complete
}

main "$@"
