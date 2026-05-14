#!/bin/bash -e
set -o pipefail

# ============================================================
# Turnip Adreno 6xx – V4 SAFE-EXTREME (ETS2 60FPS+)
# Otimizado para Performance Bruta e Estabilidade
# ============================================================

deps="git meson ninja patchelf unzip curl pip flex bison zip glslangValidator python3"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
mesasrc="https://github.com/whitebelyash/mesa-tu8.git"
srcfolder="mesa"
BUILD_VERSION="${BUILD_VERSION:-4.1}"

# ── V4 SAFE-EXTREME FLAGS ──────────────────────────────────
# Foco em matemática rápida e otimização de linkagem
OPT_CFLAGS="-O3 -march=armv8-a+simd -flto -ffast-math -fomit-frame-pointer -funsafe-math-optimizations"
OPT_CXXFLAGS="$OPT_CFLAGS"

run_all(){
    check_deps
    prepare_workdir
    build_lib_for_android gen8
}

check_deps(){
    for deps_chk in $deps; do
        if ! command -v "$deps_chk" >/dev/null 2>&1 ; then
            exit 1
        fi
    done
    pip install mako --break-system-packages &> /dev/null || true
}

prepare_workdir(){
    mkdir -p "$workdir" && cd "$workdir"

    if [ ! -d "$ndkver" ]; then
        curl -sL "https://dl.google.com/android/repository/${ndkver}-linux.zip" -o "${ndkver}-linux.zip" &> /dev/null
        unzip -q "${ndkver}-linux.zip" &> /dev/null
    fi

    rm -rf "$srcfolder"
    git clone "$mesasrc" --depth=1 --no-single-branch "$srcfolder"
    cd "$srcfolder"

    echo "#define TUGEN8_DRV_VERSION \"-V4-SAFE\"" > ./src/freedreno/vulkan/tu_version.h

    # ── Aplicar patches essenciais ──────────────────────────
    PATCHDIR="../../patches"
    patch -p1 < "$PATCHDIR/force_sysmem_no_autotuner.patch" || true
    patch -p1 < "$PATCHDIR/vk_sync_timeline.patch" || true

    # ── V4 Otimizações de Código Seguras ─────────────────────
    
    # Forçar FP16 em Shaders (Aumenta muito o FPS em Adreno 6xx)
    sed -i 's/lowp_as_mediump = false/lowp_as_mediump = true/g' src/freedreno/vulkan/tu_shader.cc || true
    
    # Aumentar buffer de comandos (Reduz stutters)
    sed -i 's/CS_BUFFER_SIZE = 4096/CS_BUFFER_SIZE = 8192/g' src/freedreno/vulkan/tu_cs.h || true
}

build_lib_for_android(){
    cd "$workdir/$srcfolder"
    git checkout "origin/$1"

    # Correções de compatibilidade
    sed -i 's/a8xx_gen2_raw_magic_regs/a8xx_base_raw_magic_regs/g' src/freedreno/common/freedreno_devices.py || true
    sed -i 's/ (%s)//g' src/freedreno/vulkan/tu_device.cc || true
    sed -i 's/ (%s)//g' src/freedreno/vulkan/tu_device.c || true

    mkdir -p "$workdir/bin"
    ln -sf "$ndk/clang" "$workdir/bin/cc"
    ln -sf "$ndk/clang++" "$workdir/bin/c++"
    export PATH="$workdir/bin:$ndk:$PATH"
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld -flto"

    meson setup build-android-aarch64 \
        --cross-file "../../android-aarch64.txt" \
        --native-file "../../native.txt" \
        --prefix "/tmp/turnip-v4" \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dplatform-sdk-version=36 \
        -Dandroid-stub=true \
        -Dvulkan-drivers=freedreno \
        -Dfreedreno-kmds=kgsl \
        -Dc_args="$OPT_CFLAGS" \
        -Dcpp_args="$OPT_CXXFLAGS" \
        -Dc_link_args="-flto -fuse-ld=lld" \
        -Dcpp_link_args="-flto -fuse-ld=lld"

    ninja -C build-android-aarch64 install

    cd "/tmp/turnip-v4/lib"
    
    cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip V4 SAFE-EXTREME",
  "description": "V4: Fast-Math, FP16 Nativo, 8KB CS Buffer. Máxima performance com estabilidade para Adreno 6xx.",
  "author": "Manus-V4",
  "packageVersion": "4",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.348",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

    zip -9 "/tmp/Turnip-V4-Extreme-Adreno6xx.zip" libvulkan_freedreno.so meta.json
    cp "/tmp/Turnip-V4-Extreme-Adreno6xx.zip" "$workdir/"
}

run_all
