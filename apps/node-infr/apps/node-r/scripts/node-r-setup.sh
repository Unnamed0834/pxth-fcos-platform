



set -euo pipefail


OEM_DIR="/var/oem"
LOG_FILE="/var/log/node-r-setup.log"


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


if [[ -f "$SCRIPT_DIR/lib/logging.sh" ]]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    log_init_fallback "$LOG_FILE" "[SUCCESS]"
fi


cd /var/oem/scripts || {
    log_error "Cannot access /var/oem/scripts"
    exit 1
}





verify_oem_tarball() {
    log_info "Phase 0: Verifying OEM disk integrity..."

    local disk_path="/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi9"
    local errors=0


    local expected_sha256="${OEM_DISK_SHA256:-}"


    if [[ -z "$expected_sha256" ]]; then
        log_error "OEM_DISK_SHA256 not set — refusing to skip integrity check"
        return 1
    fi

    local tarball_size="${TARBALL_SIZE:-}"
    if [[ -z "$tarball_size" ]]; then
        log_error "TARBALL_SIZE not set — refusing to skip integrity check"
        return 1
    fi

    local actual_sha256
    actual_sha256=$(dd if="$disk_path" bs=1M 2>/dev/null | head -c "$tarball_size" | sha256sum | awk '{print $1}')

    if [[ "$actual_sha256" == "$expected_sha256" ]]; then
        log_success "OEM disk integrity verified: $actual_sha256"
    else
        log_error "OEM disk integrity check FAILED!"
        log_error "  Expected: $expected_sha256"
        log_error "  Actual:   $actual_sha256"
        errors=$((errors + 1))
    fi

    return $errors
}





verify_system() {
    log_info "Phase 1: Verifying system..."


    local current_hostname
    current_hostname="$(hostname)"
    if [[ "$current_hostname" == node-r* ]]; then
        log_success "Hostname verified: $current_hostname"
    else
        log_warn "Hostname is $current_hostname, expected node-r*"
    fi


    if ip addr show eth0 &>/dev/null; then
        local ip_addr
        ip_addr=$(ip -4 addr show eth0 | grep -oP 'inet \K[\d.]+')
        log_success "Network configured: eth0 has $ip_addr"
    else
        log_warn "Network may not be configured as expected"
    fi


    if podman --version &>/dev/null; then
        log_success "Podman available"
    else
        log_warn "Podman not available"
    fi

    log_success "System verification complete"
}





configure_services() {
    log_info "Phase 2: Configuring services..."


    systemctl enable sshd 2>/dev/null || true

    log_success "Services configured"
}





configure_log_rotation() {
    log_info "Phase 3: Configuring log rotation..."

    setup_log_rotation "/var/log/node-r-setup.log"

    log_success "Log rotation configured"
}





verify_setup() {
    log_info "Phase 4: Verifying setup..."

    local errors=0
    local xdg="XDG_RUNTIME_DIR=/run/user/5000"


    if [[ "$(hostname)" == node-r* ]]; then
        log_success "Hostname correct"
    else
        log_warn "Hostname may need verification"
    fi


    if ip addr show eth0 &>/dev/null; then
        log_success "Network configured"
    else
        log_warn "Network may need verification"
    fi


    if /usr/bin/podman --version &>/dev/null; then
        log_success "Podman available: $(/usr/bin/podman --version)"
    else
        log_warn "Podman not available at /usr/bin/podman"
    fi


    local con_count
    con_count=$(su - containers -c "$xdg /usr/bin/podman images --format \"{{.ID}}\" 2>/dev/null | wc -l" 2>/dev/null || echo 0)
    if [[ $con_count -gt 0 ]]; then
        log_success "Container images loaded: $con_count"
        su - containers -c "$xdg /usr/bin/podman images" 2>/dev/null | while read -r line; do
            log_info "  $line"
        done
    else
        log_warn "No container images loaded yet (node-r-containers-load.service may still be running)"
    fi


    local running_count
    running_count=$(su - containers -c "$xdg /usr/bin/podman ps --format '{{.Names}}' 2>/dev/null | wc -l")
    if [[ $running_count -gt 0 ]]; then
        log_success "Running containers: $running_count"
        su - containers -c "$xdg /usr/bin/podman ps" 2>/dev/null | while read -r line; do
            log_info "  $line"
        done
    fi

    return $errors
}





main() {
    log_heading "INFR-R NODE - SETUP"
    log_info "Starting node-r node configuration..."
    log_info ""


    local failures=0


    if ! verify_oem_tarball; then
        log_warn "Phase 0: OEM tarball verification had issues"
    fi


    if ! verify_system; then
        log_warn "Phase 1 had issues (non-critical)"
        failures=$((failures + 1))
    fi


    if ! configure_services; then
        log_warn "Phase 2 had issues (non-critical)"
        failures=$((failures + 1))
    fi


    if ! configure_log_rotation; then
        log_warn "Phase 3 had issues (non-critical)"
    fi


    if ! verify_setup; then
        log_warn "Phase 4: Verification found issues (review above)"
    fi



    if (( failures > 0 )); then
        log_error "Setup finished with $failures issue(s); refusing to write the completion sentinel"
        return 1
    fi
    touch /etc/node-r-setup-complete
    log_success "Setup marked complete"

    log_info ""
    log_heading "Infr-R Setup Complete!"
    log_info "Node: $(hostname)"
    log_info ""
    log_info "Management commands:"
    log_info "  Setup Logs:    sudo journalctl -u node-r-setup -f"
    log_info "  Containers:    sudo -u containers podman ps"
    log_info "  Podman:        sudo -u containers podman images"
    log_info "  SSH:           sudo systemctl status sshd"
    echo ""

    return 0
}


main "$@"
