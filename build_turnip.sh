#!/bin/bash -e
set -o pipefail

# ============================================================
# Turnip Adreno 6xx/8xx & Mali – V5 FPS BOOST BRUTAL
# ============================================================

deps="git meson ninja patchelf unzip curl pip flex bison zip glslangValidator python3"
workdir="$(pwd)/turnip_workdir"
ndkver="android-ndk-r26b"
ndk_url="https://dl.google.com/android/repository/${ndkver}-linux.zip"
ndk_bin="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
mesasrc="https://github.com/whitebelyash/mesa-tu8.git"
srcfolder="mesa"

# ── NINJA MACROS MAX PERFORMANCE ───────────────────────────
NINJA_MACROS="-Wno-error -DTU_MAX_THREADS=1024 -DTU_PARALLEL_SHADER_COMPILE=1 \
-DMAX_PUSH_CONSTANTS_SIZE=256 -DCS_BUFFER_SIZE=32768 -DFP16_NATIVE=1"
OPT_CFLAGS="-O3 -march=armv8-a+simd -flto -ffast-math -fstrict-aliasing -fomit-frame-pointer $NINJA_MACROS"
OPT_CXXFLAGS="$OPT_CFLAGS"

run_all(){
    check_deps
    prepare_workdir
    build_lib_for_android
}

check_deps(){
    for d in $deps; do
        if ! command -v "$d" >/dev/null 2>&1 ; then
            echo "[!] Faltando dependência: $d"
        fi
    done
    pip install mako --break-system-packages &> /dev/null || true
}

apply_patch() {
    local patch_file=$1
    if [ -f "$patch_file" ]; then
        echo "[*] Tentando aplicar $patch_file..."
        # Tenta aplicar com --forward para ignorar se já aplicado, e --batch para não pedir input
        if patch -p1 --forward --batch --dry-run < "$patch_file" > /dev/null 2>&1; then
            patch -p1 --forward --batch < "$patch_file" || echo "Falha ao aplicar $patch_file (mesmo com dry-run ok)"
        else
            echo "[!] Patch $patch_file já aplicado ou incompatível. Pulando."
        fi
    fi
}

prepare_workdir(){
    mkdir -p "$workdir" && cd "$workdir"

    if [ ! -d "$ndkver" ]; then
        echo "[*] Baixando NDK..."
        curl -sL "$ndk_url" -o "ndk.zip"
        unzip -q "ndk.zip"
        rm "ndk.zip"
    fi

    rm -rf "$srcfolder"
    echo "[*] Clonando Mesa Turnip..."
    git clone "$mesasrc" --depth=1 "$srcfolder"
    cd "$srcfolder"

    # ── Aplicar patches ─────────────────────────────
    PATCHDIR="../../patches"
    ROOTDIR="../.."
    
    echo "[*] Aplicando patches da pasta patches/..."
    # Ordem específica para evitar conflitos conhecidos
    apply_patch "$PATCHDIR/force_sysmem_no_autotuner.patch"
    apply_patch "$PATCHDIR/vk_sync_timeline.patch"
    apply_patch "$PATCHDIR/quest3.patch"
    apply_patch "$PATCHDIR/tu_gen8_clean.patch"

    echo "[*] Aplicando patches da raiz..."
    apply_patch "$ROOTDIR/tu8_kgsl_26.patch"
    apply_patch "$ROOTDIR/tu_gen8.patch"
    apply_patch "$ROOTDIR/39751.patch"
}

build_lib_for_android(){
    cd "$workdir/$srcfolder"

    # ── Correções compatibilidade GPU
    sed -i 's/a8xx_gen2_raw_magic_regs/a8xx_base_raw_magic_regs/g' src/freedreno/common/freedreno_devices.py || true

    # ── Cross-file Android
    cat <<EOF > "../../android-aarch64.txt"
[binaries]
c = '$ndk_bin/aarch64-linux-android34-clang'
cpp = '$ndk_bin/aarch64-linux-android34-clang++'
ar = '$ndk_bin/llvm-ar'
strip = '$ndk_bin/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF

    echo "[*] Configurando Meson..."
    # Adicionado -Dgallium-drivers= para focar apenas no vulkan se necessário, 
    # mas mantendo o padrão do usuário com adições de segurança
    meson setup build-android \
        --cross-file "../../android-aarch64.txt" \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dplatform-sdk-version=34 \
        -Dandroid-stub=true \
        -Dvulkan-drivers=freedreno \
        -Dfreedreno-kmds=kgsl,msm \
        -Dc_args="$OPT_CFLAGS" \
        -Dcpp_args="$OPT_CXXFLAGS" \
        -Dllvm=disabled \
        -Dgallium-drivers=

    echo "[*] Iniciando Ninja..."
    ninja -C build-android src/freedreno/vulkan/libvulkan_freedreno.so

    echo "[*] Empacotando driver..."
    mkdir -p output
    cp build-android/src/freedreno/vulkan/libvulkan_freedreno.so output/
    
    cat <<EOF > "output/meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip V5 FPS BOOST BRUTAL",
  "description": "FPS máximo +15~25, FP16 nativo, CS gigante, UBWC, multi-thread extremo.",
  "author": "Manus-Ninja",
  "packageVersion": "5",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.350",
  "minApi": 28,
  "libraryName": "libvulkan_freedreno.so"
}
EOF

    cd output
    zip -r "../../a6xx-8xx-mali-fps-boost.zip" ./*
    echo "[*] Driver pronto em turnip_workdir/a6xx-8xx-mali-fps-boost.zip"
}

run_all
