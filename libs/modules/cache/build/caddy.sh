









set -euo pipefail







cache_build_caddy_cloudflare() {
    local ver_dir="$1"
    local expected_digest="$2"
    local component="${3:-caddy}"


    local caddy_tmp_dir
    caddy_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/pxth-caddy.XXXXXX")
    trap 'rm -rf "$caddy_tmp_dir"' RETURN


    local home_dir="${HOME:-/home/operator}"
    [[ -d "$home_dir/.local/bin" ]] && export PATH="$home_dir/.local/bin:$PATH"


    if ! get_container_runtime &>/dev/null; then
        log_error "No container runtime found - cannot build custom Caddy"
        return 1
    fi


    local go_version
    go_version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//') || go_version=""
    if [[ -n "$go_version" ]]; then
        local go_major minor
        go_major=$(echo "$go_version" | cut -d. -f1)
        go_minor=$(echo "$go_version" | cut -d. -f2)
        if (( go_major < 1 || (go_major == 1 && go_minor < 25) )); then
            log_warn "Go $go_version detected - Caddy v2.11+ requires Go 1.25+"
            log_info "Standard Caddy image will be used instead"
            return 1
        fi
    fi


    local dest_dir="$ver_dir/containers/$component"
    local dest_path="$dest_dir/caddy-latest.tar"
    mkdir -p "$dest_dir"

    if [[ -f "$dest_path" ]]; then
        if [[ -n "$expected_digest" ]]; then
            local cached_digest
            cached_digest=$(cat "${dest_path}.digest" 2>/dev/null || echo "")
            local expected_normalized="${expected_digest#sha256:}"
            if [[ "$cached_digest" == "$expected_normalized" ]]; then
                log_success "Caddy Cloudflare image already cached (manifest digest verified)"
                return 0
            fi
            log_warn "Cached Caddy manifest digest mismatch, rebuilding"
        else
            log_success "Caddy Cloudflare image already cached"
            return 0
        fi
    fi


    if ! command -v xcaddy &> /dev/null; then
        log_info "Installing xcaddy..."
        local xcaddy_version
        if ! xcaddy_version=$(curl -fsSL https://api.github.com/repos/caddyserver/xcaddy/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/'); then
            xcaddy_version=""
        fi
        if [[ -z "$xcaddy_version" ]]; then
            log_warn "Could not determine latest xcaddy version; build will be skipped"
            return 1
        fi
        local xcaddy_url="https://github.com/caddyserver/xcaddy/releases/download/v${xcaddy_version}/xcaddy_${xcaddy_version}_linux_amd64.tar.gz"
        local temp_dir="$caddy_tmp_dir/install"
        mkdir -p "$temp_dir"

        if curl -fsSL "$xcaddy_url" -o "$temp_dir/xcaddy.tar.gz"; then
            if tar xzf "$temp_dir/xcaddy.tar.gz" -C "$temp_dir" 2>/dev/null && \
               chmod +x "$temp_dir/xcaddy" && \
               mv "$temp_dir/xcaddy" /usr/local/bin/xcaddy 2>/dev/null; then
                log_success "xcaddy v${xcaddy_version} installed to /usr/local/bin/xcaddy"
            elif mkdir -p "$home_dir/.local/bin" && mv "$temp_dir/xcaddy" "$home_dir/.local/bin/xcaddy" 2>/dev/null; then
                export PATH="$home_dir/.local/bin:$PATH"
                log_success "xcaddy v${xcaddy_version} installed to $HOME/.local/bin/xcaddy"
            else
                rm -rf "$temp_dir"
            fi
        fi

        rm -rf "$temp_dir"

        if ! command -v xcaddy &> /dev/null; then
            log_warn "xcaddy installation failed - build will be skipped"
            return 1
        fi
    fi


    log_info "Building custom Caddy with Cloudflare DNS plugin..."
    local build_temp_dir="$caddy_tmp_dir/build"
    mkdir -p "$build_temp_dir"
    local dockerfile="$build_temp_dir/Dockerfile"

    cat > "$dockerfile" <<DOCKERFILE
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache git gcc musl-dev
ENV GOPATH=/go
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
WORKDIR /build
RUN /go/bin/xcaddy build --output /caddy --with github.com/caddy-dns/cloudflare

FROM caddy:latest
COPY --chmod=755 --from=builder /caddy /usr/bin/caddy
DOCKERFILE

    log_info "Building custom Caddy Docker image..."
    local build_runtime
    build_runtime=$(get_container_runtime) || {
        log_error "No container runtime found - cannot build custom Caddy"
        rm -rf "$build_temp_dir"
        return 1
    }
    if ! $build_runtime build -t caddy:cloudflare "$build_temp_dir" 2>&1; then
        log_error "Failed to build custom Caddy Docker image"
        rm -rf "$build_temp_dir"
        return 1
    fi

    rm -rf "$build_temp_dir"


    log_info "Saving custom Caddy image to: $dest_path"
    rm -f "$dest_path"
    local runtime
    runtime=$(get_container_runtime) || {
        log_error "Failed to save Caddy image"
        return 1
    }
    if ! $runtime save caddy:cloudflare -o "$dest_path" 2>&1; then
        log_error "Failed to save Caddy image"
        return 1
    fi

    local file_size
    file_size=$(stat -c%s "$dest_path" 2>/dev/null || stat -f%z "$dest_path" 2>/dev/null || echo "0")

    if (( file_size < MIN_SIZE_IMAGE )); then
        log_error "Saved file too small: $file_size bytes (min: $MIN_SIZE_IMAGE)"
        rm -f "$dest_path" "${dest_path}.digest" 2>/dev/null
        return 1
    fi


    local image_digest
    image_digest=$($runtime inspect --format "{{index .RepoDigests 0}}" caddy:cloudflare 2>/dev/null | sed 's/.*@sha256://' || echo "")
    if [[ -n "$image_digest" ]]; then
        echo "$image_digest" > "${dest_path}.digest"
    fi


    if [[ -n "$expected_digest" ]]; then
        if [[ -z "$image_digest" ]]; then
            log_error "Could not read image manifest digest for caddy:cloudflare"
            return 1
        fi
        local expected_normalized="${expected_digest#sha256:}"
        if [[ "$image_digest" != "$expected_normalized" ]]; then
            log_error "Caddy image manifest digest mismatch"
            log_error "  Expected: $expected_digest"
            log_error "  Got:      $image_digest"
            return 1
        fi
        log_info "Caddy image manifest digest verified: $image_digest"
    fi

    if (( file_size > 0 )); then
        log_success "Built Caddy with Cloudflare DNS plugin ($(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"))"
    fi

    return 0
}
