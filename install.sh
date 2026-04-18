#!/usr/bin/env bash
set -euo pipefail

REPO="xinyang-go/zvm"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"
INSTALL_DIR="${1:-$HOME/.zvm}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

info()  { printf "${CYAN}[zvm]${RESET} %s\n" "$*"; }
error() { printf "${RED}[zvm]${RESET} %s\n" "$*" >&2; }

detect_shell_rc() {
    local shell_name
    shell_name="$(basename "${SHELL:-bash}")"
    case "$shell_name" in
        zsh)  echo "$HOME/.zshrc" ;;
        bash) echo "$HOME/.bashrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

configure_path() {
    local rc_file
    rc_file="$(detect_shell_rc)"

    local zig_entry="$INSTALL_DIR/zig"
    local zvm_entry="$INSTALL_DIR"

    case "$(basename "${SHELL:-bash}")" in
        fish)
            if ! grep -q "$zvm_entry" "$rc_file" 2>/dev/null; then
                mkdir -p "$(dirname "$rc_file")"
                echo "" >> "$rc_file"
                echo "set -gx PATH $zvm_entry \$PATH" >> "$rc_file"
                if ! grep -q "$zig_entry" "$rc_file" 2>/dev/null; then
                    echo "if test -L \"$zig_entry\"" >> "$rc_file"
                    echo "    set -gx PATH $zig_entry \$PATH" >> "$rc_file"
                    echo "end" >> "$rc_file"
                fi
                info "added PATH to $rc_file"
            fi
            ;;
        *)
            if ! grep -q "$zvm_entry" "$rc_file" 2>/dev/null; then
                echo "" >> "$rc_file"
                echo "export PATH=\"$zvm_entry:\$PATH\"" >> "$rc_file"
                echo "[ -L \"$zig_entry\" ] && export PATH=\"$zig_entry:\$PATH\"" >> "$rc_file"
                info "added PATH to $rc_file"
            fi
            ;;
    esac
}

main() {
    if [[ "$INSTALL_DIR" == -* ]]; then
        error "usage: $0 [install_dir]"
        error "  default install dir: $HOME/.zvm"
        exit 1
    fi

    info "installing zvm to $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"

    local tmp
    tmp="$(mktemp)"

    info "downloading zvm.sh..."
    if ! curl -fsSL "$RAW_BASE/zvm.sh" -o "$tmp"; then
        error "failed to download zvm.sh from GitHub"
        rm -f "$tmp"
        exit 1
    fi

    mv "$tmp" "$INSTALL_DIR/zvm"
    chmod +x "$INSTALL_DIR/zvm"

    configure_path

    printf "\n${GREEN}[zvm]${RESET} installed successfully to %s/zvm\n" "$INSTALL_DIR"
    printf "${GREEN}[zvm]${RESET} restart your shell or run: source %s\n" "$(detect_shell_rc)"
}

main "$@"
