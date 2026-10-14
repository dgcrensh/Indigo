#!/bin/bash
# Installs a Linux Swift toolchain in Claude Code cloud sessions so the core package tests and the format check
# (`scripts/check.sh --core`) can run there. The app target needs macOS and Xcode; CI covers it.
#
# The version matches CI's Xcode 16.2 (Swift 6.0.3), which also ships `swift format`.
# The toolchain comes from download.swift.org when that host is reachable, otherwise from the official `swift`
# Docker image's toolchain layer on mirror.gcr.io, checked against its sha256 digest.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

SWIFT_VERSION=6.0.3
PREFIX=/opt/swift-$SWIFT_VERSION
SWIFT_BIN=$PREFIX/usr/bin

persist_path() {
    if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
        echo "export PATH=\"$SWIFT_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
    fi
}

if [ -x "$SWIFT_BIN/swift" ] && "$SWIFT_BIN/swift" --version > /dev/null 2>&1; then
    persist_path
    exit 0
fi

case "$(dpkg --print-architecture)" in
    amd64) arch=amd64; url_suffix= ;;
    arm64) arch=arm64; url_suffix=-aarch64 ;;
    *)
        echo "Unsupported architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
esac

# curl and jq for the download below, then runtime and build dependencies: the same list the official swift:6.0.3-noble image installs.
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
apt-get -qq install -y --no-install-recommends \
    curl jq binutils git unzip gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
    libsqlite3-0 libstdc++-13-dev libxml2-dev libncurses-dev libz3-dev pkg-config tzdata zlib1g-dev > /dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tarball=$work/swift.tar.gz

release="swift-$SWIFT_VERSION-RELEASE"
swift_org_url="https://download.swift.org/swift-$SWIFT_VERSION-release/ubuntu2404$url_suffix/$release/$release-ubuntu24.04$url_suffix.tar.gz"

if curl -fsSL --retry 3 "$swift_org_url" -o "$tarball" 2> /dev/null; then
    strip=1 # Tarball root is <release>/usr/...
else
    echo "download.swift.org unreachable; using the swift:$SWIFT_VERSION-noble image from mirror.gcr.io"
    registry=https://mirror.gcr.io/v2/library/swift
    index=$(curl -fsSL --retry 3 -H "Accept: application/vnd.oci.image.index.v1+json" \
        "$registry/manifests/$SWIFT_VERSION-noble")
    manifest_digest=$(echo "$index" | jq -r --arg arch "$arch" \
        '.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch) | .digest')
    manifest=$(curl -fsSL --retry 3 -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        "$registry/manifests/$manifest_digest")
    # The toolchain is the image's largest layer: the release tarball unpacked into /usr.
    layer_digest=$(echo "$manifest" | jq -r '.layers | max_by(.size) | .digest')
    curl -fsSL --retry 3 "$registry/blobs/$layer_digest" -o "$tarball"
    echo "${layer_digest#sha256:}  $tarball" | sha256sum --check --quiet
    strip=0 # Layer root is usr/...
fi

mkdir -p "$PREFIX.partial"
tar -xzf "$tarball" -C "$PREFIX.partial" --strip-components=$strip --wildcards '*usr/*'
chmod -R o+r "$PREFIX.partial/usr/lib/swift"
rm -rf "$PREFIX"
mv "$PREFIX.partial" "$PREFIX"

"$SWIFT_BIN/swift" --version
persist_path
