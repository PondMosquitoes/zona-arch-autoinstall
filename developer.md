# ZONA Developer Reference

## Script Overview

### `autoinstall.sh` — entry point
Wrapper/menu. Run this first. Detects whether ZONA is installed and routes accordingly.
- **Pre-flight:** `_portproton_gate` — checks `~/PortProton/data/scripts/start.sh` and `~/PortProton/data/prefixes/DOTNET` exist; launches `portproton` with instructions if not.
- **Fresh install path:** runs steps 1–3 (install.sh → perf.sh → sudoers), each gated with a y/n prompt.
- **Already-installed path:** drops into a numbered menu (1–7) giving quick access to all other scripts.
- **`_first_launch_gate`:** before running perf.sh, checks `Anomaly/appdata/user.ltx` exists (only created after first Anomaly launch); pauses with instructions if not.

---

### `install.sh` — full installer
Runs once (or on reinstall). Steps in order:

| Step | What it does |
|------|-------------|
| System packages | Installs `python git libunrar curl p7zip winetricks` via pacman |
| PortProton | Checks `portproton` is in PATH |
| gdrive-ripper | Installs pip package for Google Drive downloads |
| gamma-launcher | Clones + installs Anomaly downloader |
| **Anomaly** | Downloads via gamma-launcher (~60 GB); prompts for GDrive link if needed |
| **MO2** | Downloads + extracts Mod Organizer 2 into `ZONA/` |
| **ZONA modpack** | Downloads ZONA v1.37 archive via gdrive-ripper; extracts into `ZONA/mods/` |
| Settings | Copies `axr_options.ltx` into Anomaly gamedata |
| **DOTNET prefix** | Checks `~/PortProton/data/prefixes/DOTNET` exists; runs winetricks (`cmd d3dcompiler_43/47 d3dx10 d3dx11_43 d3dx9 d3dx9_43 mfc42 ogg openal quartz`) into it |
| **`AnomalyLauncher.exe.ppdb`** | Pre-writes PortProton per-game config with `PW_USE_WINE_DXGI=0` (critical — template default of `=1` causes D3D11 device creation failure) |
| First launch | Prompts user: right-click `AnomalyLauncher.exe` → Open with PortProton → GENERAL tab: 3D API=DXVK/VKD3D Newest, WINE=Proton_LG_10-28, PREFIX=DOTNET → LAUNCH |
| Shader cache | Deletes `Anomaly/appdata/shaders_cache/r4/` |
| MO2 setup | Prompts user: right-click `ZONA/ModOrganizer.exe` → Open with PortProton → same settings → LAUNCH → wizard: Portable instance, Game=`Anomaly/`, Instance=`ZONA/` |
| Verify | Prompts user to test DX11 via MO2 |

Has its own re-run menu (options 1–6) for updating/repairing without re-running everything.

---

### `perf.sh` — performance tuning
Run after first Anomaly launch (requires `Anomaly/appdata/user.ltx`).

- **Hardware detection:** CPU model/cores/threads, GPU vendor/name, VRAM, primary display resolution, AVX level (AVX / AVX2 / AVX-512).
- **Interactive prompts:** game resolution, A-Life radius patch (yes/no), custom `user.ltx` tweaks (yes/no).
- **CPU governor:** calls `sudo perf-root.sh` — sets all cores to `performance` governor (+ EPP if supported) and enables NVIDIA persistence mode.
- **DXVK config:** writes `Anomaly/bin/dxvk.conf` — sets `maxDeviceMemory` to 87.5% of detected VRAM, limits framerate via `maxFrameRate`.
- **`commandline.txt`:** writes Anomaly launch flags (`-nointro -noprefetch -nolog` etc.).
- **A-Life radius:** optionally patches `alife_online_distance` in `gamedata/configs/alife/` LTX files.
- **Engine binary:** detects AVX support → copies matching binary from `xray-monolith-staging/` into `Anomaly/bin/AnomalyDX11.exe`.
- **gamemode:** optionally installs + configures `gamemode` for CPU boost during play.
- **`user.ltx` patches:** sets threading, Lua GC, resolution, detail density/height/radius.

---

### `perf-root.sh` — privileged tweaks (called via sudo by perf.sh)
- Sets all CPU cores to `performance` scaling governor.
- Sets `energy_performance_preference=performance` if EPP is supported.
- Enables NVIDIA persistence mode (`nvidia-smi -pm 1`).

---

### `settings-grab.sh` — snapshot settings
Saves current in-game config to `settings/`. Rotates previous snapshot to `settings-backup/`.

Captures:
- `Anomaly/appdata/user.ltx`
- `ZONA/mods/*MCM values*/gamedata/configs/axr_options.ltx`
- `ZONA/profiles/*/modlist.txt` (all MO2 profiles)

---

### `settings-inject.sh` — restore settings
Restores from `settings/` back into the game. Inverse of `settings-grab.sh`.

---

### `swap_exe.sh` — swap engine binary
Copies a pre-built X-Ray Monolith binary from `xray-monolith-staging/` into `Anomaly/bin/AnomalyDX11.exe` and clears the shader cache.

Options:
- `mt_DX11AVX.exe` — AVX build (default)
- `mt_DX11.exe` — non-AVX fallback

---

## Key paths

| Path | Purpose |
|------|---------|
| `Anomaly/appdata/user.ltx` | Main game settings; patched by perf.sh; required before perf.sh runs |
| `Anomaly/bin/AnomalyDX11.exe` | Active engine binary (swapped by perf.sh / swap_exe.sh) |
| `Anomaly/bin/dxvk.conf` | DXVK overrides written by perf.sh |
| `Anomaly/AnomalyLauncher.exe.ppdb` | PortProton per-game config; pre-written by install.sh with `PW_USE_WINE_DXGI=0` |
| `xray-monolith-staging/` | Pre-built engine binaries (AVX/non-AVX) |
| `ZONA/profiles/` | MO2 profiles (modlists) |
| `settings/` | Snapshot from settings-grab.sh |
| `~/PortProton/data/prefixes/DOTNET` | Wine prefix used for all ZONA/Anomaly exes |
| `/etc/sudoers.d/stalker-perf` | Allows perf-root.sh to run without password prompt |

## PortProton per-game config (`AnomalyLauncher.exe.ppdb`)

```bash
PW_VULKAN_USE="6"      # DXVK + VKD3D (Newest)
PW_USE_WINE_DXGI=0     # Must be 0 — Wine DXGI + DXVK D3D11 = DXGI_ERROR_UNSUPPORTED
PW_WINE_USE="PROTON_LG_10-28"
PW_PREFIX_NAME="DOTNET"
```
