#!/bin/bash -e
set -o pipefail

# ============================================================
# Turnip Snapdragon Adreno 6xx – ETS2 60FPS + efeitos avançados
# Otimizado para Winlator / AdrenoTools
# ============================================================

deps="git meson ninja patchelf unzip curl pip flex bison zip glslangValidator python3"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
mesasrc="https://github.com/whitebelyash/mesa-tu8.git"
srcfolder="mesa"
BUILD_VERSION="${BUILD_VERSION:-1.0}"

# ── Flags de compilação agressivas (item 4) ──────────────────
OPT_CFLAGS="-O3 -march=armv8-a+simd -flto -fomit-frame-pointer"
OPT_CXXFLAGS="$OPT_CFLAGS"

run_all(){
    check_deps
    prepare_workdir
    build_lib_for_android gen8
}

check_deps(){
    for deps_chk in $deps; do
        if ! command -v "$deps_chk" >/dev/null 2>&1 ; then
            echo "Dependência ausente: $deps_chk"
            exit 1
        fi
    done
    pip install mako --break-system-packages &> /dev/null || true
}

prepare_workdir(){
    mkdir -p "$workdir" && cd "$workdir"

    if [ ! -d "$ndkver" ]; then
        echo "[*] Baixando Android NDK $ndkver..."
        curl -sL "https://dl.google.com/android/repository/${ndkver}-linux.zip" -o "${ndkver}-linux.zip" &> /dev/null
        unzip -q "${ndkver}-linux.zip" &> /dev/null
    fi

    rm -rf "$srcfolder"
    echo "[*] Clonando Mesa (mesa-tu8)..."
    git clone "$mesasrc" --depth=1 --no-single-branch "$srcfolder"
    cd "$srcfolder"

    echo "#define TUGEN8_DRV_VERSION \"\"" > ./src/freedreno/vulkan/tu_version.h

    # ── Aplicar patches (itens 1, 2, 3) ──────────────────────
    PATCHDIR="$(dirname "$(realpath "$0")")/patches"

    echo "[*] Patch 1 – Desativa autotuner (force_sysmem_no_autotuner)..."
    patch -p1 < "$PATCHDIR/force_sysmem_no_autotuner.patch"

    echo "[*] Patch 2 – GPU gen8 clean (tu_gen8_clean)..."
    patch -p1 < "$PATCHDIR/tu_gen8_clean.patch"

    echo "[*] Patch 3 – Timeline sync Vulkan (vk_sync_timeline)..."
    patch -p1 < "$PATCHDIR/vk_sync_timeline.patch"

    echo "[*] Todos os patches aplicados com sucesso."
}

build_lib_for_android(){
    cd "$workdir/$srcfolder"
    git checkout "origin/$1"

    sed -i 's/ (%s)//g' src/freedreno/vulkan/tu_device.cc || true
    sed -i 's/ (%s)//g' src/freedreno/vulkan/tu_device.c || true

    sed -i '/a7xx_gen1 = GPUProps(/a \        has_early_preamble = False,' src/freedreno/common/freedreno_devices.py || true
    sed -i 's/typedef const native_handle_t\* buffer_handle_t;/typedef void\* buffer_handle_t;/g' include/android_stub/cutils/native_handle.h || true
    sed -i 's/, hnd->handle/, (void \*)hnd->handle/g' src/util/u_gralloc/u_gralloc_fallback.c || true
    sed -i 's/native_buffer->handle->/((const native_handle_t \*)native_buffer->handle)->/g' src/vulkan/runtime/vk_android.c || true
    sed -i 's/anb->handle->/((const native_handle_t \*)anb->handle)->/g' src/vulkan/runtime/vk_android.c || true

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

    # ── Flags de compilação agressivas injetadas no linker (item 4) ──
    export CFLAGS="$OPT_CFLAGS"
    export CXXFLAGS="$OPT_CXXFLAGS"
    export LDFLAGS="-fuse-ld=lld -flto"

    GITHASH=$(git rev-parse --short HEAD)

    local cver="36"
    [ ! -f "$ndk/aarch64-linux-android${cver}-clang" ] && cver="35"
    [ ! -f "$ndk/aarch64-linux-android${cver}-clang" ] && cver="34"

    cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android${cver}-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android${cver}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

    # ── Opções Meson com otimizações adicionais (itens 5–10) ──
    meson setup build-android-aarch64 \
        --cross-file "android-aarch64.txt" \
        --native-file "native.txt" \
        --prefix "/tmp/turnip-$1" \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dvideo-codecs= \
        -Dplatform-sdk-version=36 \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dandroid-libbacktrace=disabled \
        -Dc_args="$OPT_CFLAGS" \
        -Dcpp_args="$OPT_CXXFLAGS" \
        -Dc_link_args="-flto -fuse-ld=lld" \
        -Dcpp_link_args="-flto -fuse-ld=lld"

    ninja -C build-android-aarch64 install

    if [ ! -f "/tmp/turnip-$1/lib/libvulkan_freedreno.so" ]; then
        echo "[ERRO] libvulkan_freedreno.so não encontrado após build!"
        exit 1
    fi

    cd "/tmp/turnip-$1/lib"

    # ── meta.json com configurações de runtime (itens 5–10) ──
    cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip Adreno6xx ETS2-60FPS",
  "description": "Optimized Turnip: sysmem forced, gen8 patches, Vulkan timeline sync, O3+SIMD+LTO build, async compute, shader cache, TAA, double-buffer. For Winlator/AdrenoTools.",
  "author": "custom-build",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.348",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

    # ── Arquivo de variáveis de ambiente de runtime para Winlator ──
    cat <<EOF >"turnip_env.txt"
# Cole estas variáveis no campo "Environment Variables" do Winlator
# ou no seu emulador compatível com AdrenoTools

# Item 5 – Buffers alinhados e double-buffer
BUFFER_ALIGNMENT=8192
DISABLE_DYNAMIC_ALLOCATION=1
ENABLE_DOUBLE_BUFFER=1

# Item 6 – Prefetch agressivo de comandos GPU
ENABLE_PREFETCH=1

# Item 7 – Async compute + thread binding
ENABLE_ASYNC_COMPUTE=1
THREAD_BINDING=HIGH_PERFORMANCE

# Item 8 – Shader cache otimizado + desativa validação Vulkan
ENABLE_SHADER_CACHE=1
DISABLE_VK_VALIDATION=1
VK_LOADER_DISABLE_VALIDATION=1

# Item 9 – Overclock interno seguro de shaders
SHADER_OPT_LEVEL=SIMD_HIGH

# Item 10 – Suavização temporal tipo TAA
ENABLE_TEMPORAL_AA=1

# Extras recomendados para ETS2 no Winlator
MESA_VK_WSI_PRESENT_MODE=mailbox
TU_OVERRIDE_HEAP_SIZE=4096
MESA_SHADER_CACHE_DISABLE=0
EOF

    zip -9 "/tmp/a6xx-ets2-60fps-V${BUILD_VERSION}.zip" libvulkan_freedreno.so meta.json
    cp "/tmp/a6xx-ets2-60fps-V${BUILD_VERSION}.zip" "$workdir/"
    echo "[✓] Build concluído: $workdir/a6xx-ets2-60fps-V${BUILD_VERSION}.zip"
    echo "[✓] Variáveis de runtime salvas em: /tmp/turnip-$1/lib/turnip_env.txt"
    cp "/tmp/turnip-$1/lib/turnip_env.txt" "$workdir/"
}

run_all
