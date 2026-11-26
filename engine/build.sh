#!/usr/bin/env bash
# Builds the neural rendering engine into target/engine/ (or $1): upscale-engine.so, one file with its shaders and
# engine.ini.default packed in (written into nr/ beside it on first use), plus the harness and model_check tools.
# Needs g++ (C++20), zlib, the Vulkan loader and headers 1.4.357 or later (VULKAN_INCLUDE: another include folder),
# glslang and python3. CXX: the compiler. VANA_NR_VERSION: the version it reports (default vana-client/<the crate's version>).
# NR_STEP=gen makes only the shaders, the pack and the model tables (in <out>/gen), NR_STEP=compile only the binaries.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
nr=$here/vendor/dlssnr-rdna3
out=$(mkdir -p -- "${1:-$here/../target/engine}" && cd -- "${1:-$here/../target/engine}" && pwd)
cxx=${CXX:-g++}
step=${NR_STEP:-all}
crate=$(sed -n 's/^version = "\(.*\)"/\1/p' "$here/../crates/vana-client/Cargo.toml" | head -1)
version=${VANA_NR_VERSION:-vana-client/$crate}

cd -- "$nr"
source linux/build/arch/rdna3.sh
if [ "$step" != compile ]; then
glslang=$(command -v glslang || command -v glslangValidator) || { echo "glslang is required" >&2; exit 1; }
export NR_GLSLANG=$glslang
stage=$out/stage
rm -rf -- "$stage"
mkdir -p -- "$stage/dlssnr-amd" "$out/gen"
python3 linux/build/build_network.py rdna3 --out "$stage/dlssnr-amd/shaders" > /dev/null
for s in prep compose; do "$glslang" -V --target-env vulkan1.3 -o "$stage/$s.spv" "$here/src/$s.comp" > /dev/null; done
cp -f -- "$here/engine.ini" "$stage/engine.ini.default"
python3 "$here/src/pack_files.py" "$stage" "$out/gen/nr.pack" > /dev/null
python3 "$here/tools/gen_model_tables.py" linux/package/model-tools "$out/gen" > /dev/null
fi
[ "$step" = gen ] && { echo "$out/gen"; exit 0; }

inc=(-Ilinux/src/core -I"$here/src" -I"$out/gen" ${VULKAN_INCLUDE:+-I$VULKAN_INCLUDE})
"$cxx" -std=c++20 -O2 -w -fPIC -shared -fvisibility=hidden -static-libstdc++ -static-libgcc "${inc[@]}" "${NR_PRODUCT_DEFINES[@]}" \
    -DVANA_NR_VERSION="\"$version\"" -DNR_PACK="\"$out/gen/nr.pack\"" \
    "$here/src/engine.cpp" "$here/src/model.cpp" "$here/src/files.S" linux/src/core/nr_runtime.cpp linux/src/core/nr_native_plan.cpp \
    -o "$out/upscale-engine.so" -Wl,--no-undefined -lvulkan -lz -lpthread -ldl
"$cxx" -std=c++20 -O1 -w "${inc[@]}" "${NR_PRODUCT_DEFINES[@]}" "$here/tools/harness.cpp" -o "$out/harness" -lvulkan -ldl
"$cxx" -std=c++20 -O2 -w "${inc[@]}" "$here/tools/model_check.cpp" "$here/src/model.cpp" -o "$out/model_check" -lz
echo "$out/upscale-engine.so ($version)"
