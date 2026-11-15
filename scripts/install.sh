#!/bin/sh
set -eu

REPO="LuisRibeiroo/pspm"
ARCHIVE_NAME="pspm-macos-universal.tar.gz"
CHECKSUM_NAME="pspm-macos-universal.tar.gz.sha256"
INSTALL_DIR="$HOME/.pspm/bin"
BINARY_PATH="$INSTALL_DIR/pspm"

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
            printf 'Unknown option: %s\n' "$arg" >&2
            exit 1
            ;;
    esac
done

OS="$(uname -s)"
if [ "$OS" != "Darwin" ]; then
    printf 'Error: pspm currently supports macOS (Darwin) only (detected: %s).\n' "$OS" >&2
    exit 1
fi

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64)
        ;;
    *)
        printf 'Error: unsupported macOS architecture: %s (expected arm64 or x86_64).\n' "$ARCH" >&2
        exit 1
        ;;
esac

if ! command -v curl >/dev/null 2>&1; then
    printf 'Error: curl is required to install pspm.\n' >&2
    exit 1
fi

if ! command -v shasum >/dev/null 2>&1; then
    printf 'Error: shasum is required to verify the downloaded archive.\n' >&2
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

printf 'Downloading pspm (%s, %s) from %s...\n' "$OS" "$ARCH" "$BASE_URL"
curl -fsSL "${BASE_URL}/${ARCHIVE_NAME}" -o "$ARCHIVE_FILE"
curl -fsSL "${BASE_URL}/${CHECKSUM_NAME}" -o "$CHECKSUM_FILE"

EXPECTED_SHA="$(awk '{print $1}' "$CHECKSUM_FILE" | head -n 1)"
ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_FILE" | awk '{print $1}')"

if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    printf 'Error: SHA-256 checksum verification failed!\n' >&2
    printf '  Expected: %s\n' "${EXPECTED_SHA:-<empty>}" >&2
    printf '  Actual:   %s\n' "$ACTUAL_SHA" >&2
    exit 1
fi

printf 'Checksum verified (%s).\n' "$ACTUAL_SHA"

tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR"
if [ ! -f "${TMP_DIR}/pspm" ]; then
    printf 'Error: extracted archive did not contain pspm binary.\n' >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "${TMP_DIR}/pspm" "$BINARY_PATH"
chmod 755 "$BINARY_PATH"

printf 'Installed pspm to %s\n\n' "$BINARY_PATH"

if [ "$NO_MODIFY_PATH" -eq 1 ]; then
    "$BINARY_PATH" setup --no-modify-path
else
    "$BINARY_PATH" setup
fi
