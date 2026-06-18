# STALKER GAMMA on Linux — Methodology

**This document is the diagnostic and design skill for this project. Read it before proposing any change. Every section is a decision rule, not background reading.**

---

## Rule 0: Do not use the community as a source

Reddit, the GAMMA Discord, YouTube guides, the Anomaly wiki — written by people who got something working once, on their hardware, without understanding why. No verification, no staleness tracking.

**What this produces:**
- `d3d11.cachedDynamicResources` in "performance guides" despite crashing X-Ray on new game start
- Advice to *raise* `switch_distance` — actual result is CPU overrun. Lowering to 200 fixed it
- Launch options with `DXVK_ASYNC=1` before `exec` — bash tries to execute a binary named `DXVK_ASYNC=1`
- Gamescope `--steam` / `-e` (Steam Deck only) in desktop guides

**Use instead:** source code, DXVK changelog and issue tracker, `man` pages, your own numbers in Great Swamps. Community output is a direction pointer. "People mention this flag" is where investigation *starts*.

---

## Rule 1: One change at a time

Launch → load Great Swamps → read frame times for 60+ seconds → decide. Never batch changes. If something breaks you will not know what caused it.

Great Swamps is the benchmark: high NPC count, heavy A-Life switching, worst case for CPU and GPU both. Averages lie. Read the frame time graph — stutter is spikes, not averages.

---

## Rule 2: Memory hierarchy — fix in this order

X-Ray memory is layered. Each layer depends on the one below it. Tuning an upper layer while a lower layer is starved accomplishes nothing.

```
1. Engine heap       — X-Ray's internal allocator pool (system RAM)
2. VRAM budget       — DXVK device memory (GPU VRAM)
3. Shared overflow   — DXVK shared memory (system RAM spill when VRAM full)
4. Lua GC            — LuaJIT heap management (system RAM)
```

**Always work bottom-up. Never tune layer 2 before layer 1 is sized correctly.**

### Layer 1 — Engine heap (`-heap` in commandline.txt)

X-Ray pre-reserves a pool from system RAM and sub-allocates from it internally. Default is ~256 MB. When the pool is exhausted or fragmented, the engine calls the OS for every allocation — causing brief stalls that compound in long sessions.

**This should be the first thing set on any new install. It draws from system RAM, not VRAM. Sizing it correctly is the foundation everything else rests on.**

Current target: `-heap 1024` (1 GB). With 16 GB system RAM and ~9 GB in use during play, this is well within budget.

File: `Anomaly/commandline.txt`

### Layer 2 — VRAM budget (`dxgi.maxDeviceMemory` in dxvk.conf)

Caps how much GPU VRAM DXVK allocates. Default is uncapped — DXVK will use all available VRAM. When VRAM saturates, DXVK has no headroom for pipeline heap, shader allocation, or async compiler buffers. This causes `VK_ERROR_OUT_OF_DEVICE_MEMORY` crashes and mid-frame eviction stalls.

**The game becomes unplayable at VRAM saturation before it can ever reach layer 3. Fix this before worrying about shared overflow.**

RTX 4060 has 8188 MiB. Current target: `dxgi.maxDeviceMemory = 7000` (~85%). Leaves ~1188 MiB headroom.

### Layer 3 — Shared overflow (`dxgi.maxSharedMemory` in dxvk.conf)

DXVK spills into system RAM when VRAM exceeds `maxDeviceMemory`. Default cap is 4 GB. With 6+ GB free system RAM this can be raised, but **it only matters if the game is already stable at layers 1 and 2.** If VRAM is saturating and crashing, this setting is irrelevant — the game never reaches it cleanly.

Currently left at default. Re-evaluate after `-heap` and VRAM cap are confirmed stable.

### Layer 4 — Lua GC (`lua_gcstep`, `lua_parallel_gcstep`, `lua_parallel_gc_call_amount`)

LuaJIT 2 GC runs in the render thread during the CPU/GPU parallelism window (CPU submitted frame, GPU still rendering). Not a separate OS thread — it exploits the idle gap.

```cpp
do {
    Device.LuaGCCount++;
    if (Device.LuaGC() == 1) break;
} while (Device.isRendering && Device.LuaGCCount < psLua_ParallelGC_CallAmount);
```

`lua_parallel_gc_call_amount` is **hardcapped at 50** in `console_commands.cpp`. Current tuning (`lua_gcstep 400`, `lua_parallel_gcstep 112`, `lua_parallel_gc_call_amount 37`) is at the practical ceiling. FPS tapering in long sessions from GC not keeping pace with 486 mods is a floor — not addressable without a recompile to raise or remove the cap.

**Further tuning requires a recompile: clone xray-monolith source, change the cap constant in C++, compile on Windows, replace AnomalyDX11.exe.**

---

## Confirmed working configuration

### commandline.txt
```
-smap1536
-prefetch_sounds
-heap 1024
```
- `-smap1536` — shadow map size
- `-prefetch_sounds` — preloads audio on level load, eliminates mid-session streaming stalls
- `-heap 1024` — 1 GB engine allocator pool from system RAM

### dxvk.conf
```
dxvk.numCompilerThreads = 0
dxgi.maxFrameLatency = 1
dxvk.enableAsync = True
dxvk.enableGraphicsPipelineLibrary = True
dxgi.maxDeviceMemory = 7000
```
- `enableGraphicsPipelineLibrary` — NVIDIA `VK_EXT_graphics_pipeline_library`; primary PSO stutter fix, no visual artifact
- `enableAsync` — belt-and-suspenders alongside GPL
- `maxDeviceMemory = 7000` — prevents VRAM saturation OOM

### user.ltx patches (applied by perf.sh every launch)
- `r__threaded_path on` — offloads A* pathfinding to worker threads; safe with GAMMA scripts
- `r__detail_density 0.5` / `r__detail_radius 40` — cuts detail-object sort array size ~68%, reduces render thread L1/L2 thrash
- `lua_gcstep 400` / `lua_parallel_gcstep 112` / `lua_parallel_gc_call_amount 37` — GC at practical ceiling
- `vid_mode WxH` — set to chosen resolution

### alife.ltx
- `switch_distance = 200` — NPC online simulation radius. Default 450 causes CPU overrun in dense areas
- `auto_switch_distance_normal = 200` — must match switch_distance; `xr_patch.script` reads this at runtime and overrides switch_distance 10s after load. If left at 450 it silently undoes the change
- `auto_switch_distance_start = 1250` — intentional; world populates on load then pulls back after 10s (prevents pop-in)
- `switch_factor` — **do not touch.** 1.5 causes an unhandled exception. Leave whatever the file has

---

## Confirmed broken — do not re-add

| Setting | Why |
|---|---|
| `d3d11.cachedDynamicResources = vi` | Crashes X-Ray on new game start |
| Gamescope `--force-windows-fullscreen` | Crops mouse movement |
| Gamescope `--steam` / `-e` | Steam Deck only — hangs on desktop |
| Gamescope `--immediate-flips` | No-op in nested Wayland mode |
| Gamescope `-r N` | Frame rate cap, hurts performance |
| `DXVK_ASYNC=1` before `exec` | bash treats it as a binary name |
| `switch_factor` any value | Unhandled exception |
| `-dbg` in commandline.txt | Assertion checks + memory tracking every frame |

---

## Diagnosing crashes

### Game won't launch → Steam launch options
Env var before `exec`, spaces in `DXVK_FILTER_DEVICE_NAME`, gamescope `--steam` on desktop.

### Game launches, crashes on new game or loading screen → dxvk.conf or mod config
DXVK flags that touch buffer/frame handling crash during world init, not at DX device creation. Bad Lua config (e.g. `switch_factor = 1.5`) crashes mid-load.

### Game launches, crashes after some playtime → VRAM saturation or cold DXVK cache
Cold cache + GPL+async spike memory on first run after any dxvk.conf change. Don't diagnose as a config problem until it persists on run 2. If it persists: check VRAM headroom first (`dxgi.maxDeviceMemory`), then heap (`-heap`).

### First-launch VkMemory CTD
After any dxvk.conf change: cold cache + GPL+async burst → `VK_ERROR_OUT_OF_DEVICE_MEMORY`. Resolves after first session. Not a config problem.

---

## Stutter source status

| Source | Fix | Status |
|---|---|---|
| Engine heap fragmentation | `-heap 1024` | Pending test |
| VRAM saturation | `dxgi.maxDeviceMemory = 7000` | Confirmed fix |
| A-Life CPU overrun | `switch_distance 200` | Resolved |
| PSO compilation stalls | DXVK async + GPL | Resolved |
| `-dbg` overhead | Removed | Resolved |
| Audio streaming | `-prefetch_sounds` | Resolved |
| Lua GC pauses | Parallel GC + tuned step sizes | At ceiling |
| Shader cache cold start | First-session warmup | Acceptable |

---

## Steam launch option structure

```
bash -c "/path/to/perf.sh; exec gamemoderun DXVK_ASYNC=1 WINE_CPU_TOPOLOGY=C:T PROTON_ENABLE_NVAPI=1 DXVK_FILTER_DEVICE_NAME='GPU Name' DXVK_LOG_LEVEL=none %command%"
```

- Env vars for the game go **after `exec` and after `gamemoderun`**
- `DXVK_ASYNC=1` must come after `gamemoderun` — before `exec` it becomes a binary name
- `DXVK_FILTER_DEVICE_NAME` must be quoted with no stray spaces
- `perf.sh` runs via `;` before `exec` — it configures the environment, it is not the game process
- `PROTON_ENABLE_NVAPI=1` — NVIDIA only; enables NVAPI for DLSS/perf features
- Do not disable `PROTON_NO_FSYNC` — kernel has fsync patches; disabling it loses the benefit

---

## Sudoers for perf-root.sh

`perf-root.sh` runs inside a Steam launch string — no terminal for sudo to prompt into. Without a NOPASSWD rule it silently skips governor and power settings. sudo credential cache (~15 min) makes it appear to work after a fresh DE login but fail later.

```
$USER ALL=(root) NOPASSWD: /path/to/perf-root.sh
```

**Symptom of missing rule:** perf settings only apply once per DE login.

---

## Own your settings

GAMMA resets certain mod configs on update. X-Ray rewrites `user.ltx` on exit. `perf.sh` owns these files and writes them every run — the game can do whatever it wants between launches, it gets corrected before the next one.

**"Skip if already present" is wrong:** fresh installs start with GAMMA defaults (unplayable), any update silently reverts your settings, and you never know if the file contains what you think.

SSS mod config is the clearest case — GAMMA overwrites it on every update. Re-inject on every `perf.sh` run.

---

## Engine binary selection

Two pre-built MT binaries in `xray-monolith-staging/`:

| Binary | When |
|---|---|
| `mt_DX11AVX.exe` | CPU supports any AVX level |
| `mt_DX11.exe` | No AVX support |

`perf.sh` reads `/proc/cpuinfo` and deploys the correct one every launch. `swap_exe.sh` for manual overrides. Running a binary compiled above your CPU's SIMD level → illegal instruction crash on launch.

Fallback order if crashes after binary change: AVX-512 → AVX2 → AVX.

---

## Installer design

- `install.sh` is a pure installer — ends at DX11 verify + sudoers. Does NOT call `perf.sh` or `settings-inject.sh`
- `autoinstall.sh` orchestrates the full flow: install → perf → sudoers
- Every step prompts before running with an explanation. Enter = recommended. No is always valid
- Scripts are independent and idempotent — re-run any script to fix a specific problem without touching others

---

*Know what you changed. Know why it should help. Verify that it did. When something breaks: narrow the search space, test one change at a time, read actual numbers.*

---

## PortProton SETTINGS for ModOrganizer.exe (perf reference — do not touch until game is stable)

Captured 2026-06-15. DOTNET prefix, Proton_LG_10-28, SSS21 profile, 413 mods.

### MAIN tab

| Setting | Value |
|---|---|
| MANGOHUD | OFF |
| MANGOHUD USER CONF | OFF |
| VKBASALT | OFF |
| VKBASALT USER CONF | OFF |
| DGVOODOO2 | OFF |
| USE ESYNC | OFF |
| USE FSYNC | OFF |
| USE NTSYNC | OFF |
| USE RAY TRACING | OFF |
| USE NVAPI AND DLSS | OFF |
| USE OPTISCALER | OFF |
| USE LS FRAME GEN | OFF |
| WINE FULLSCREEN FSR | **ON** |
| HIDE NVIDIA GPU | OFF |
| VIRTUAL DESKTOP | OFF |
| USE TERMINAL | OFF |
| GUI DISABLED CS | OFF |
| USE GAMEMODE | OFF |
| USE INHIBIT SLEEP | OFF |
| USE D3D EXTRAS | OFF |
| FIX VIDEO IN GAME | OFF |
| REDUCE PULSE LATENCY | OFF |
| USE GSTREAMER | OFF |
| USE SHADER CACHE | OFF |
| USE WINE DXGI | OFF |
| USE EAC AND BE | **ON** |
| USE SYSTEM VK LAYERS | OFF |
| USE OBS VKCAPTURE | OFF |
| DISABLE COMPOSITING | OFF |
| USE RUNTIME | **ON** |
| DINPUT PROTOCOL | OFF |
| USE GALLIUM ZINK | OFF |
| USE WINED3D VULKAN | OFF |
| USE NATIVE WAYLAND | OFF |
| USE DXVK HDR | OFF |
| GAMESCOPE | OFF |

### ADVANCED tab

| Setting | Value |
|---|---|
| Windows emulation version | 10 |
| Autoinstall with winetricks | (empty) |
| Forced libraries | (empty) |
| Arguments for .exe | (empty) |
| Run second .exe after main | (None) |
| Second .exe delay (seconds) | 3 |
| Limit processor cores | Disabled |
| Force OpenGL version | Disabled |
| Force VKD3D feature level | Disabled |
| Force locale | Disabled |
| Window mode (Vulkan/OpenGL) | Disabled |
| Wine audio driver | Disabled |

Perf candidates to revisit when ready: USE ESYNC / FSYNC / NTSYNC, USE GAMEMODE, USE NVAPI AND DLSS.



## FOR CLAUDE

- Community sources (guides 2 be adapted, etc, etc.) are a vector to analyze towards a goal, NOT a ruleset 
- Get a fully wokring game, then do funny buisness (performance, exe swapping, etc, etc.)
- No flatpaks, source/native/precomp/custom only.
- Scripts should not die unless user kills ctrl+c's or q's them
- Anything read by a user should be consice, and look good so they can actually read it. (setup scripts = simple borders & dividers, nothing complex.)
