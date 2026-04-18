#!/usr/bin/env bash
set -euo pipefail

ZVM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZVM_VERSIONS_DIR="$ZVM_DIR/versions"
ZVM_SYMLINK="$ZVM_DIR/zig"
ZVM_CACHE_DIR="$ZVM_DIR/cache"
ZVM_INDEX_URL="https://ziglang.org/download/index.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${CYAN}[zvm]${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}[zvm]${RESET} %s\n" "$*"; }
error() { printf "${RED}[zvm]${RESET} %s\n" "$*" >&2; }

zvm_detect_platform() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) error "unsupported architecture: $arch"; return 1 ;;
    esac
    echo "${arch}-linux"
}

zvm_ensure_dirs() {
    mkdir -p "$ZVM_VERSIONS_DIR" "$ZVM_CACHE_DIR"
}

zvm_fetch_index() {
    local cache_file="$ZVM_CACHE_DIR/index.json"
    local max_age=300
    if [[ -f "$cache_file" ]]; then
        local now file_time
        now=$(date +%s)
        file_time=$(stat -c %Y "$cache_file")
        if (( now - file_time < max_age )); then
            cat "$cache_file"
            return
        fi
    fi
    curl -fsSL "$ZVM_INDEX_URL" -o "$cache_file"
    cat "$cache_file"
}

zvm_help() {
    cat <<'EOF'
zvm - Zig Version Manager

Usage:
  zvm install <version>    Install a Zig version (e.g. 0.13.0, master)
  zvm uninstall <version>  Uninstall a Zig version
  zvm use <version>        Switch to a specific Zig version
  zvm ls                   List installed versions
  zvm ls-remote            List all available versions for download
  zvm help                  Show this help message
EOF
}

zvm_ls_remote() {
    zvm_ensure_dirs
    local platform json_data
    platform="$(zvm_detect_platform)"
    json_data="$(zvm_fetch_index)"

    printf "${BOLD}  %-12s %-12s %s${RESET}\n" "VERSION" "DATE" "SIZE"
    printf '  %s\n' "$(printf '%.0s-' {1..45})"

    echo "$json_data" | jq -r --arg plat "$platform" '
        to_entries[] |
        select(.value[$plat] != null) |
        .key as $ver |
        if $ver == "master"
        then "\($ver)\t\(.value.date // "N/A")\t\(.value[$plat].size // "N/A")\t\(.value.version // "dev")"
        else "\($ver)\t\(.value.date // "N/A")\t\(.value[$plat].size // "N/A")\t"
        end
    ' | sort -t$'\t' -k1,1Vr | while IFS=$'\t' read -r ver date size dev_ver; do
        local human_size
        if [[ "$size" =~ ^[0-9]+$ ]]; then
            human_size="$(awk -v s="$size" 'BEGIN {
                if (s >= 1073741824) printf "%.1fG", s / 1073741824
                else if (s >= 1048576) printf "%.1fM", s / 1048576
                else printf "%.1fK", s / 1024
            }')"
        else
            human_size="$size"
        fi
        if [[ -n "$dev_ver" ]]; then
            printf "  %-12s %-12s %s\n" "$ver" "$date" "$human_size"
            printf "  └─ %s\n" "$dev_ver"
        else
            printf "  %-12s %-12s %s\n" "$ver" "$date" "$human_size"
        fi
    done
}

zvm_install() {
    local version="${1:?error: version required (use 'zvm install <version>')}"
    zvm_ensure_dirs
    local platform json_data
    platform="$(zvm_detect_platform)"

    info "fetching version index..."
    json_data="$(zvm_fetch_index)"

    local tarball shasum
    read -r tarball shasum <<< "$(echo "$json_data" | jq -r --arg ver "$version" --arg plat "$platform" '
        [.[$ver][$plat].tarball // empty, .[$ver][$plat].shasum // empty] | @tsv
    ')"
    if [[ -z "$tarball" ]]; then
        error "version '$version' not found or not available for platform '$platform'"
        error "use 'zvm ls-remote' to see available versions"
        return 1
    fi

    local install_dir="$ZVM_VERSIONS_DIR/$version"
    if [[ -d "$install_dir" ]]; then
        if [[ "$version" != "master" ]]; then
            warn "version $version is already installed"
            return 0
        fi
        local installed_shasum=""
        [[ -f "$install_dir/.zvm-shasum" ]] && installed_shasum="$(cat "$install_dir/.zvm-shasum")"
        if [[ -n "$shasum" && "$shasum" == "$installed_shasum" ]]; then
            warn "master is already up to date ($installed_shasum)"
            return 0
        fi
        info "master has a new build, updating..."
        rm -rf "$install_dir"
    fi

    local filename
    filename="$(basename "$tarball")"
    local download_target="$ZVM_CACHE_DIR/$filename"

    local cache_valid=false
    if [[ -f "$download_target" ]]; then
        local actual_shasum
        actual_shasum="$(sha256sum "$download_target" | awk '{print $1}')"
        if [[ -z "$shasum" || "$actual_shasum" == "$shasum" ]]; then
            info "using cached file: $download_target"
            cache_valid=true
        else
            warn "cached file checksum mismatch, re-downloading..."
            rm -f "$download_target"
        fi
    fi

    if [[ "$cache_valid" == "false" ]]; then
        info "downloading zig $version for $platform..."
        info "  url: $tarball"
        if ! curl -fSL --progress-bar -o "$download_target" "$tarball"; then
            rm -f "$download_target"
            error "download failed"
            return 1
        fi

        info "verifying checksum..."
        local actual_shasum
        actual_shasum="$(sha256sum "$download_target" | awk '{print $1}')"
        if [[ -n "$shasum" && "$actual_shasum" != "$shasum" ]]; then
            error "checksum mismatch!"
            error "  expected: $shasum"
            error "  actual:   $actual_shasum"
            rm -f "$download_target"
            return 1
        fi
    fi

    info "extracting..."
    local extract_dir
    extract_dir="$(mktemp -d)"
    trap "rm -rf '$extract_dir'" RETURN

    if ! tar -xf "$download_target" -C "$extract_dir"; then
        error "extraction failed"
        return 1
    fi

    local extracted_root
    extracted_root="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -z "$extracted_root" ]]; then
        error "unexpected archive structure"
        return 1
    fi

    mv "$extracted_root" "$install_dir"

    chmod +x "$install_dir/zig" 2>/dev/null || true
    [[ -n "$shasum" ]] && echo "$shasum" > "$install_dir/.zvm-shasum"

    trap - RETURN

    if [[ ! -L "$ZVM_SYMLINK" ]]; then
        ln -sfn "$install_dir" "$ZVM_SYMLINK"
        printf "${GREEN}[zvm]${RESET} successfully installed and activated zig %s\n" "$version"
    else
        printf "${GREEN}[zvm]${RESET} successfully installed zig %s\n" "$version"
        printf "${GREEN}[zvm]${RESET} run 'zvm use %s' to activate\n" "$version"
    fi
}

zvm_uninstall() {
    local version="${1:?error: version required (use 'zvm uninstall <version>')}"
    local install_dir="$ZVM_VERSIONS_DIR/$version"

    if [[ ! -d "$install_dir" ]]; then
        error "version $version is not installed"
        return 1
    fi

    if [[ -L "$ZVM_SYMLINK" ]]; then
        local target
        target="$(readlink -f "$ZVM_SYMLINK")"
        if [[ "$target" == "$install_dir" ]]; then
            rm -f "$ZVM_SYMLINK"
            warn "removed active symlink (no zig version currently active)"
        fi
    fi

    rm -rf "$install_dir"
    info "uninstalled zig $version"
}

zvm_ls() {
    zvm_ensure_dirs
    local current=""
    if [[ -L "$ZVM_SYMLINK" ]]; then
        current="$(basename "$(readlink -f "$ZVM_SYMLINK")")"
    fi

    shopt -s nullglob
    local dirs=("$ZVM_VERSIONS_DIR"/*)
    shopt -u nullglob

    if [[ ${#dirs[@]} -eq 0 ]]; then
        info "no versions installed"
        info "use 'zvm install <version>' to install a version"
        return 0
    fi

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        local ver label
        ver="$(basename "$dir")"
        if [[ "$ver" == "master" ]]; then
            label="$ver ($("$dir/zig" version 2>/dev/null || echo "unknown"))"
        else
            label="$ver"
        fi
        if [[ "$ver" == "$current" ]]; then
            printf "  ${GREEN}* %s${RESET}\n" "$label"
        else
            printf "    %s\n" "$label"
        fi
    done
}

zvm_use() {
    local version="${1:?error: version required (use 'zvm use <version>')}"
    local install_dir="$ZVM_VERSIONS_DIR/$version"

    if [[ ! -d "$install_dir" ]]; then
        error "version $version is not installed"
        error "use 'zvm install $version' first"
        return 1
    fi

    if [[ ! -x "$install_dir/zig" ]]; then
        error "zig binary not found in $install_dir"
        return 1
    fi

    ln -sfn "$install_dir" "$ZVM_SYMLINK"
    printf "${GREEN}[zvm]${RESET} now using zig %s\n" "$version"
}

main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        install)    zvm_install "$@" ;;
        uninstall)  zvm_uninstall "$@" ;;
        use)        zvm_use "$@" ;;
        ls)         zvm_ls ;;
        ls-remote)  zvm_ls_remote ;;
        help|--help|-h) zvm_help ;;
        *)
            error "unknown command: $cmd"
            echo
            zvm_help
            return 1
            ;;
    esac
}

main "$@"
