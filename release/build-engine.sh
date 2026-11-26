#!/usr/bin/env bash
# The neural rendering engine's release asset, target/assets/vana-client-nr-engine-linux-x86_64.so: engine/build.sh
# in the Steam Runtime 3 "sniper" SDK (glibc 2.31) with its g++ 14, libstdc++ linked in, so it loads on every distro
# the client runs on. The Vulkan headers and glslang are the pinned ones the engine was tested with (the SDK's are too
# old), fetched once into target/engine-deps; glslang's release needs a newer glibc than the SDK's, so the shaders are
# made here (NR_STEP=gen) and only the compile runs in the SDK. release/publish.sh signs it with the client assets.
set -euo pipefail
cd "$(dirname "$0")/.."
. release/cpus.sh
[ "$(uname -m)" = x86_64 ] || { echo "the engine is x86_64 only" >&2; exit 1; }
deps=target/engine-deps
mkdir -p "$deps"
if [ ! -d "$deps/Vulkan-Headers" ]; then
    git clone -q --depth 1 --branch v1.4.357 https://github.com/KhronosGroup/Vulkan-Headers.git "$deps/Vulkan-Headers"
fi
if [ ! -x "$deps/glslang/bin/glslang" ]; then
    curl -fsSL --retry 5 -o "$deps/glslang.tgz" \
        https://github.com/KhronosGroup/glslang/releases/download/16.5.0/glslang-16.5.0-linux-x86_64-release.tar.gz
    echo "b9b1f96acb898a62251b171f7695efcecfc206a530299054071919b06820f657  $deps/glslang.tgz" | sha256sum -c --quiet -
    mkdir -p "$deps/glslang"
    tar -C "$deps/glslang" -xzf "$deps/glslang.tgz"
fi
PATH="$PWD/$deps/glslang/bin:$PATH" NR_STEP=gen engine/build.sh target/engine-release > /dev/null
cpuset="${VANA_CPUSET-$(build_cpus)}"
cpus=()
[ -n "$cpuset" ] && cpus=(--cpuset-cpus "$cpuset")
docker run --rm "${cpus[@]}" --user "$(id -u):$(id -g)" -v "$PWD:/src" -w /src \
    -e HOME=/tmp -e CXX=g++-14 -e NR_STEP=compile -e VULKAN_INCLUDE=/src/$deps/Vulkan-Headers/include \
    registry.gitlab.steamos.cloud/steamrt/sniper/sdk:latest engine/build.sh target/engine-release
mkdir -p target/assets
cp target/engine-release/upscale-engine.so target/assets/vana-client-nr-engine-linux-x86_64.so
echo "target/assets/vana-client-nr-engine-linux-x86_64.so"
