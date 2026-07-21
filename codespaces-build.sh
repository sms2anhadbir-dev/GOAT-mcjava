#!/usr/bin/env bash
# Builds Amethyst-iOS into an UNSIGNED (fakesigned via ldid) .ipa on
# GitHub Codespaces (Linux, no macOS, no Apple Developer account needed).
# The resulting ipa is meant for self-signing sideload tools (AltStore,
# Sideloadly, TrollStore) - it is not codesigned with a real cert.
#
# Usage (from repo root, inside a Codespace):
#   chmod +x codespaces-build.sh
#   ./codespaces-build.sh setup   # one-time toolchain/SDK download
#   source env.sh                 # every new shell
#   ./codespaces-build.sh build   # actually builds the ipa
#
# Output: artifacts/org.angelauramc.amethyst-<version>-ios.ipa (and a .slimmed variant)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_DIR="$HOME/ios-toolchain"
TOOLCHAIN_BIN="$TOOLCHAIN_DIR/iphone/bin"
SDK_DIR="$HOME/sdks"
SDK_NAME="iPhoneOS14.5.sdk"

do_setup() {
  echo "== Installing apt dependencies =="
  sudo apt-get update
  sudo apt-get install -y cmake lld wget unzip zip openjdk-8-jdk-headless git curl jq xz-utils

  echo "== Downloading L1ghtmann iOS cross-toolchain (clang + ldid + lld for Mach-O) =="
  mkdir -p "$TOOLCHAIN_DIR"
  if [ ! -x "$TOOLCHAIN_BIN/clang" ]; then
    ASSET_URL=$(curl -s https://api.github.com/repos/L1ghtmann/llvm-project/releases \
      | jq -r '[.[] | .assets[] | select(.name=="iOSToolchain-x86_64.tar.xz")][0].browser_download_url')
    if [ -z "$ASSET_URL" ] || [ "$ASSET_URL" = "null" ]; then
      echo "Could not find iOSToolchain-x86_64.tar.xz release asset. Check https://github.com/L1ghtmann/llvm-project/releases manually." >&2
      exit 1
    fi
    curl -L "$ASSET_URL" -o /tmp/iOSToolchain.tar.xz
    tar -xf /tmp/iOSToolchain.tar.xz -C "$TOOLCHAIN_DIR"
    rm /tmp/iOSToolchain.tar.xz
  fi

  echo "== Downloading iPhoneOS14.5 SDK =="
  mkdir -p "$SDK_DIR"
  if [ ! -d "$SDK_DIR/$SDK_NAME" ]; then
    SDK_URL=$(curl -s https://api.github.com/repos/theos/sdks/releases \
      | jq -r '[.[] | .assets[] | select(.name=="'"$SDK_NAME"'.tar.xz")][0].browser_download_url')
    if [ -z "$SDK_URL" ] || [ "$SDK_URL" = "null" ]; then
      echo "Could not find $SDK_NAME.tar.xz release asset. Check https://github.com/theos/sdks/releases manually." >&2
      exit 1
    fi
    curl -L "$SDK_URL" -o /tmp/sdk.tar.xz
    tar -xf /tmp/sdk.tar.xz -C "$SDK_DIR"
    rm /tmp/sdk.tar.xz
  fi

  echo "== Fetching git submodules =="
  cd "$ROOT"
  git submodule update --init --recursive

  # Two problems with the linker, both worked around by shims on PATH:
  #  1. The Makefile's Linux dependency check runs bare `lld` (no args) and
  #     expects exit 0, but LLVM's `lld` dispatcher always exits 1 without a
  #     flavor (ld.lld/ld64.lld/etc) - true regardless of install.
  #  2. `-fuse-ld=lld` makes clang search PATH for `ld.lld`/`ld64.lld`. The
  #     apt-installed generic `/usr/bin/lld` dispatcher only works when
  #     invoked *through* one of those symlinked names, which it isn't when
  #     found via a plain PATH search - it just prints "invoke ld.lld
  #     instead" and fails either way. The toolchain's own `iphone/bin/ld`
  #     is the real, working Mach-O linker; point all three names at it.
  mkdir -p "$HOME/bin"
  for name in lld ld.lld ld64.lld; do
    cat > "$HOME/bin/$name" <<SHIM
#!/usr/bin/env bash
if [ \$# -eq 0 ]; then
  exit 0
fi
exec "$TOOLCHAIN_BIN/ld" "\$@"
SHIM
    chmod +x "$HOME/bin/$name"
  done

  cat > "$ROOT/env.sh" <<EOF
export PATH="$HOME/bin:$TOOLCHAIN_BIN:\$PATH"
export CC="$TOOLCHAIN_BIN/clang"
export CXX="$TOOLCHAIN_BIN/clang++"
export SDKPATH="$SDK_DIR/$SDK_NAME"
export BOOTJDK=/usr/lib/jvm/java-8-openjdk-amd64/bin
export RUNNER=1
EOF
  echo "== Setup done. Run: source env.sh =="
}

do_build() {
  cd "$ROOT"
  : "${SDKPATH:?SDKPATH not set - did you 'source env.sh'?}"
  : "${CC:?CC not set - did you 'source env.sh'?}"
  # No TEAMID/SIGNING_TEAMID/PROVISIONING -> Makefile skips real codesigning
  # and falls back to ldid fakesigning (see `payload` target).
  make -j"$(nproc)" all PLATFORM=2 SLIMMED=1
  echo "== Build complete. Look in artifacts/ for the .ipa =="
  ls -la "$ROOT/artifacts"/*.ipa
}

case "${1:-}" in
  setup) do_setup ;;
  build) do_build ;;
  *) echo "Usage: $0 {setup|build}"; exit 1 ;;
esac
