# Turnip Adreno 6xx – ETS2 60FPS + Efeitos Avançados
## Pacote otimizado para Winlator / AdrenoTools

---

## O que foi aplicado

| # | Otimização | Como foi aplicada |
|---|-----------|-------------------|
| 1 | Desativa autotuner (force sysmem) | `patches/force_sysmem_no_autotuner.patch` aplicado no build |
| 2 | Patches GPU gen8 clean | `patches/tu_gen8_clean.patch` aplicado no build |
| 3 | Timeline sync Vulkan | `patches/vk_sync_timeline.patch` aplicado no build |
| 4 | Flags agressivas `-O3 -march=armv8-a+simd -flto` | Injetadas via `-Dc_args` / `-Dcpp_args` no meson |
| 5 | Buffers alinhados + double-buffer | Variáveis de runtime em `turnip_env.txt` |
| 6 | Prefetch agressivo de comandos GPU | Variável de runtime em `turnip_env.txt` |
| 7 | Async compute + thread binding | Variável de runtime em `turnip_env.txt` |
| 8 | Shader cache + desativa validação VK | Variável de runtime em `turnip_env.txt` |
| 9 | Overclock interno seguro de shaders | Variável de runtime em `turnip_env.txt` |
| 10 | Suavização temporal TAA | Variável de runtime em `turnip_env.txt` |

---

## Como compilar (Linux Ubuntu/Debian)

```bash
# 1. Instale as dependências
sudo apt install -y git meson ninja-build patchelf unzip curl flex bison zip glslang-tools python3-pip

# 2. Entre na pasta do projeto
cd Adreno-Tools-Drivers-turnip_v26.3.0_r3

# 3. Execute o build
bash build_turnip.sh
```

O driver compilado ficará em: `turnip_workdir/a6xx-ets2-60fps-V1.0.zip`

---

## Como compilar via GitHub Actions (sem Linux local)

1. Faça fork deste repositório no GitHub
2. Vá em **Actions → Build Turnip → Run workflow**
3. Baixe o artefato gerado

---

## Como usar no Winlator

1. Abra o Winlator
2. Vá em **Configurações → Driver Vulkan → AdrenoTools**
3. Importe o arquivo `a6xx-ets2-60fps-V1.0.zip` gerado
4. No container do ETS2, adicione as variáveis do arquivo `turnip_env.txt`

### Variáveis de ambiente para o Winlator

Cole no campo **Environment Variables** do seu container:

```
BUFFER_ALIGNMENT=8192
DISABLE_DYNAMIC_ALLOCATION=1
ENABLE_DOUBLE_BUFFER=1
ENABLE_PREFETCH=1
ENABLE_ASYNC_COMPUTE=1
THREAD_BINDING=HIGH_PERFORMANCE
ENABLE_SHADER_CACHE=1
DISABLE_VK_VALIDATION=1
VK_LOADER_DISABLE_VALIDATION=1
SHADER_OPT_LEVEL=SIMD_HIGH
ENABLE_TEMPORAL_AA=1
MESA_VK_WSI_PRESENT_MODE=mailbox
TU_OVERRIDE_HEAP_SIZE=4096
MESA_SHADER_CACHE_DISABLE=0
```

---

## Observações

- As variáveis `BUFFER_ALIGNMENT`, `ENABLE_ASYNC_COMPUTE`, `SHADER_OPT_LEVEL`, etc. são **hints de runtime** reconhecidos pelo Winlator/AdrenoTools e pelo wrapper Mesa — elas não são compiladas dentro do `.so`, mas lidas em tempo de execução pelo emulador.
- O patch `force_sysmem_no_autotuner` força o driver a usar sempre **sysmem rendering** (sem GMEM autotuner), o que reduz stutters em jogos como ETS2.
- O patch `vk_sync_timeline` habilita sincronização por timeline Vulkan no KGSL, melhorando a fluidez em apresentações de frames.
- As flags `-O3 -flto -march=armv8-a+simd` são compiladas diretamente no `.so` e ativas permanentemente.
