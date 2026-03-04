#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MONITORING_URL="${MONITORING_URL:-https://rustdesk-monitoring-mvp.onrender.com}"
PAYLOAD_DIR="packaging/monitoring-deb-payload"
BUILD_PROFILE="${RUSTDESK_BUILD_PROFILE:-debug}"
REBUILD_RUSTDESK_BIN="${REBUILD_RUSTDESK_BIN:-1}"
RUSTDESK_BUILD_FEATURES="${RUSTDESK_BUILD_FEATURES:-linux-pkg-config}"
if [[ -n "${RUSTDESK_BIN_PATH:-}" ]]; then
  BIN_PATH="${RUSTDESK_BIN_PATH}"
else
  BIN_PATH="target/${BUILD_PROFILE}/rustdesk"
fi
SCITER_PATH="${SCITER_LIB_PATH:-target/${BUILD_PROFILE}/libsciter-gtk.so}"
LIBYUV_PATH_DEFAULT="$HOME/.local/opt/rustdesk-deps/usr/lib/x86_64-linux-gnu/libyuv.so.0"
LIBYUV_PATH="${LIBYUV_PATH:-$LIBYUV_PATH_DEFAULT}"

if [[ "$REBUILD_RUSTDESK_BIN" == "1" ]]; then
  echo "updating embedded UI resources..."
  python3 res/inline-sciter.py

  cargo_args=(build --bin rustdesk)
  if [[ "$BUILD_PROFILE" == "release" ]]; then
    cargo_args+=(--release)
  fi
  if [[ -n "$RUSTDESK_BUILD_FEATURES" ]]; then
    cargo_args+=(--features "$RUSTDESK_BUILD_FEATURES")
  fi

  echo "building rustdesk (${BUILD_PROFILE})..."
  cargo "${cargo_args[@]}"
fi

if [[ ! -f "$BIN_PATH" ]]; then
  echo "error: rustdesk binary not found at '$BIN_PATH'"
  echo "hint: export RUSTDESK_BIN_PATH=target/release/rustdesk (or build debug first)"
  exit 1
fi

if [[ ! -f "$SCITER_PATH" ]]; then
  echo "error: libsciter-gtk.so not found at '$SCITER_PATH'"
  echo "hint: export SCITER_LIB_PATH=/path/to/libsciter-gtk.so"
  exit 1
fi

if [[ ! -f "$LIBYUV_PATH" ]]; then
  echo "error: libyuv.so.0 not found at '$LIBYUV_PATH'"
  echo "hint: export LIBYUV_PATH=/path/to/libyuv.so.0"
  exit 1
fi

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"

cp "$BIN_PATH" "$PAYLOAD_DIR/rustdesk-bin"
cp "$SCITER_PATH" "$PAYLOAD_DIR/libsciter-gtk.so"
cp -L "$LIBYUV_PATH" "$PAYLOAD_DIR/libyuv.so.0"

cat > "$PAYLOAD_DIR/rustdesk" <<EOF
#!/bin/sh
set -eu

APPDIR="/usr/share/rustdesk"
export LD_LIBRARY_PATH="\$APPDIR\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"

if [ -z "\${RUSTDESK_MONITORING_URL:-}" ]; then
  export RUSTDESK_MONITORING_URL="${MONITORING_URL}"
fi

exec "\$APPDIR/rustdesk-bin" "\$@"
EOF

chmod +x "$PAYLOAD_DIR/rustdesk"
chmod +x "$PAYLOAD_DIR/rustdesk-bin"

python3 build.py --package "$PAYLOAD_DIR"

echo "done: generated package(s):"
ls -1 rustdesk-*.deb
echo "default monitoring url: $MONITORING_URL"
