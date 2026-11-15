#!/bin/sh
set -eu

REPO="LuisRibeiroo/pspm"
ARCHIVE_NAME="pspm-macos-universal.tar.gz"
CHECKSUM_NAME="pspm-macos-universal.tar.gz.sha256"
INSTALL_DIR="$HOME/.pspm/bin"
BINARY_PATH="$INSTALL_DIR/pspm"

# ANSI styling helpers (disabled automatically when non-TTY or NO_COLOR is set)
USE_COLOR=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
    USE_COLOR=1
fi
if [ -n "${FORCE_COLOR:-}" ] && [ "${FORCE_COLOR:-0}" != "0" ] && [ -z "${NO_COLOR:-}" ]; then
    USE_COLOR=1
fi

if [ "$USE_COLOR" -eq 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_ITALIC='\033[3m'
    C_RED='\033[1;31m'
    C_GREEN='\033[1;32m'
    C_YELLOW='\033[1;33m'
    C_CYAN='\033[1;36m'
    C_PATH='\033[36m'
    C_GRAY='\033[90m'
else
    C_RESET=''
    C_BOLD=''
    C_ITALIC=''
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_CYAN=''
    C_PATH=''
    C_GRAY=''
fi

step_running() {
    printf '  %b▸%b %b%s%b\n' "$C_CYAN" "$C_RESET" "$C_CYAN" "$1" "$C_RESET"
}

step_success() {
    if [ -n "${2:-}" ]; then
        printf '  %b✓%b %b%s%b %b%s%b\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET" "$C_PATH" "$2" "$C_RESET"
    else
        printf '  %b✓%b %b%s%b\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
    fi
}

step_error() {
    printf '  %b✗%b %b%s%b\n' "$C_RED" "$C_RESET" "$C_RED" "$1" "$C_RESET" >&2
}

step_tip() {
    printf '  %b› %b%s%b\n' "$C_GRAY" "$C_ITALIC" "$1" "$C_RESET"
}

NO_MODIFY_PATH=0
if [ "${PSPM_NO_MODIFY_PATH:-0}" = "1" ] || [ "${PSPM_NO_MODIFY_PATH:-}" = "true" ]; then
    NO_MODIFY_PATH=1
fi

for arg in "$@"; do
    case "$arg" in
        --no-modify-path)
            NO_MODIFY_PATH=1
            ;;
        -h|--help)
            cat <<'EOF'
Install pspm (Performant Swift Package Manager) on macOS.

Usage:
  curl -fsSL https://raw.githubusercontent.com/LuisRibeiroo/pspm/main/scripts/install.sh | sh
  curl -fsSL https://raw.githubusercontent.com/LuisRibeiroo/pspm/main/scripts/install.sh | sh -s -- --no-modify-path

Environment variables:
  PSPM_VERSION         Specific release tag to install (e.g., v0.1.0). Defaults to latest.
  PSPM_NO_MODIFY_PATH  Set to 1 to skip modifying shell RC files.
EOF
            exit 0
            ;;
        *)
            step_error "Unknown option: $arg"
            exit 1
            ;;
    esac
done

printf '%bpspm installer%b\n' "$C_CYAN" "$C_RESET"

OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    step_error "pspm currently supports macOS (Darwin) only (detected: $OS)."
    exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64)
        ;;
    *)
        step_error "Unsupported macOS architecture: $ARCH (expected arm64 or x86_64)."
        exit 1
        ;;
esac
step_success "Platform detected" "${OS} (${ARCH})"

if ! command -v curl >/dev/null 2>&1; then
    step_error "curl is required to install pspm."
    exit 1
fi

if ! command -v shasum >/dev/null 2>&1; then
    step_error "shasum is required to verify the downloaded archive."
    exit 1
fi

if [ -n "${PSPM_VERSION:-}" ] && [ "${PSPM_VERSION}" != "latest" ]; then
    TAG="v${PSPM_VERSION#v}"
    BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"
else
    BASE_URL="https://github.com/${REPO}/releases/latest/download"
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_FILE="${TMP_DIR}/${ARCHIVE_NAME}"
CHECKSUM_FILE="${TMP_DIR}/${CHECKSUM_NAME}"

step_running "Downloading pspm from ${BASE_URL}..."
curl -fsSL "${BASE_URL}/${ARCHIVE_NAME}" -o "$ARCHIVE_FILE"
curl -fsSL "${BASE_URL}/${CHECKSUM_NAME}" -o "$CHECKSUM_FILE"
step_success "Downloaded archive" "$ARCHIVE_NAME"

step_running "Verifying SHA-256 checksum..."
EXPECTED_SHA="$(awk '{print $1}' "$CHECKSUM_FILE" | head -n 1)"
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_FILE" | awk '{print $1}')"

if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    step_error "SHA-256 checksum verification failed!"
    printf '    Expected: %s\n' "${EXPECTED_SHA:-<empty>}" >&2
    printf '    Actual:   %s\n' "$ACTUAL_SHA" >&2
    exit 1
fi
step_success "Checksum verified" "$ACTUAL_SHA"

step_running "Installing binary to ${BINARY_PATH}..."
tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"
if [ ! -f "${TMP_DIR}/pspm" ]; then
    step_error "Extracted archive did not contain pspm binary."
    exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "${TMP_DIR}/pspm" "$BINARY_PATH"
chmod 755 "$BINARY_PATH"
step_success "Installed binary" "$BINARY_PATH"
printf '\n'

if [ "$NO_MODIFY_PATH" -eq 1 ]; then
    "$BINARY_PATH" setup --no-modify-path
else
    "$BINARY_PATH" setup
fi
