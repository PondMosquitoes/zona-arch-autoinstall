#!/usr/bin/env bash
# perf.sh — STALKER ZONA performance tuning (Arch Linux)
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Detect hardware ────────────────────────────────────────────────────────────
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)
CPU_THREADS=$(nproc)
CPU_CORES=$(lscpu | awk '/^Core\(s\) per socket:/ {print $4}')
CPU_THREADS_PER_CORE=$(lscpu | awk '/^Thread\(s\) per core:/ {print $4}')
HAS_EPP=0
[[ -f /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference ]] && HAS_EPP=1

GPU_VENDOR="other"
GPU_NAME=""
VRAM_MIB=0
if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null 2>&1; then
    GPU_VENDOR="nvidia"
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | xargs)
    VRAM_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
fi
[[ -z "$GPU_NAME" ]] && \
    GPU_NAME=$(lspci | grep -i 'VGA compatible' | head -1 | sed 's/.*: //' | xargs)
if [[ "${VRAM_MIB:-0}" -eq 0 ]]; then
    for _f in /sys/class/drm/card*/device/mem_info_vram_total; do
        [[ -f "$_f" ]] && VRAM_MIB=$(( $(cat "$_f") / 1024 / 1024 )) && break
    done
fi
if [[ "${VRAM_MIB:-0}" -gt 0 ]]; then
    _vram_target=$(( VRAM_MIB * 7 / 8 ))
    VRAM_CAP=$(( (_vram_target + 306) / 612 * 612 ))
else
    VRAM_CAP=4096
    warn "VRAM detection failed — defaulting maxDeviceMemory to 4096 MiB"
fi

NATIVE_RES=$(xrandr --query 2>/dev/null | awk '/connected primary/ { match($0, /[0-9]+x[0-9]+/, arr); print arr[0]; exit }')
NATIVE_W=$(printf '%s' "$NATIVE_RES" | cut -dx -f1)
NATIVE_H=$(printf '%s' "$NATIVE_RES" | cut -dx -f2)
if [[ -z "$NATIVE_W" || -z "$NATIVE_H" ]]; then
    NATIVE_W=1920; NATIVE_H=1080
    warn "Native resolution detection failed — defaulting to 1920x1080"
fi

CPU_FLAGS=$(grep -m1 '^flags' /proc/cpuinfo)
HAS_AVX512=0; HAS_AVX2=0; HAS_AVX=0
grep -qw 'avx512f' <<< "$CPU_FLAGS" && HAS_AVX512=1 || true
grep -qw 'avx2'    <<< "$CPU_FLAGS" && HAS_AVX2=1   || true
grep -qw 'avx'     <<< "$CPU_FLAGS" && HAS_AVX=1    || true
AVX_DETECTED="none"
[[ $HAS_AVX    -eq 1 ]] && AVX_DETECTED="AVX"
[[ $HAS_AVX2   -eq 1 ]] && AVX_DETECTED="AVX2"
[[ $HAS_AVX512 -eq 1 ]] && AVX_DETECTED="AVX-512"

info "Detected CPU:     $CPU_MODEL ($CPU_CORES cores, $CPU_THREADS_PER_CORE threads/core)"
info "Detected GPU:     $GPU_NAME"
info "Detected VRAM:    ${VRAM_MIB} MiB"
info "Detected display: ${NATIVE_W}x${NATIVE_H} (primary)"
info "Detected SIMD:    $AVX_DETECTED (highest supported)"

# ── Interactive configuration ──────────────────────────────────────────────────
INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1


PERF_CONFIG="$STALKER/.perf_config"
[[ -f "$PERF_CONFIG" ]] && source "$PERF_CONFIG"

_res_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "Game resolution:\n"
    printf "  1) 1280x720\n"
    printf "  2) 1920x1080\n"
    printf "  3) 2560x1440\n"
    printf "  4) Native — %sx%s (detected primary display)\n" "$NATIVE_W" "$NATIVE_H"
    printf "  5) Custom\n"
    sleep 1
    read -rp "Choice [1-5, default 4]: " _res_choice
fi
case "${_res_choice:-4}" in
    1) GAME_W=1280;        GAME_H=720 ;;
    2) GAME_W=1920;        GAME_H=1080 ;;
    3) GAME_W=2560;        GAME_H=1440 ;;
    5)
        sleep 1
        read -rp "Width:  " GAME_W
        sleep 1
        read -rp "Height: " GAME_H
        ;;
    *) GAME_W="${GAME_W:-$NATIVE_W}"; GAME_H="${GAME_H:-$NATIVE_H}" ;;
esac
[[ $INTERACTIVE -eq 1 ]] && printf 'GAME_W=%s\nGAME_H=%s\n' "$GAME_W" "$GAME_H" > "$PERF_CONFIG"

FRAME_CAP=0
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    printf "Frame cap:\n"
    printf "  1) 60fps\n"
    printf "  2) 72fps\n"
    printf "  3) 90fps\n"
    printf "  4) 120fps\n"
    printf "  5) Custom\n"
    printf "  6) Unlimited\n"
    sleep 1
    read -rp "Choice [1-6, default 6]: " _cap_choice
    case "${_cap_choice:-6}" in
        1) FRAME_CAP=60 ;;
        2) FRAME_CAP=72 ;;
        3) FRAME_CAP=90 ;;
        4) FRAME_CAP=120 ;;
        5) sleep 1; read -rp "FPS: " FRAME_CAP ;;
        *) FRAME_CAP=0 ;;
    esac
fi

_vram_custom=0
if [[ $INTERACTIVE -eq 1 ]]; then
    _vram_rec=$(( VRAM_MIB * 4 / 5 ))
    printf "\n"
    printf "dxgi.maxDeviceMemory — VRAM budget for DXVK (detected: %s MiB)\n" "$VRAM_MIB"
    printf "  Recommended: ~80%% of VRAM ≈ %s MiB\n" "$_vram_rec"
    sleep 1
    read -rp "  Custom amount in MiB [press Enter to skip]: " _vram_input
    if [[ -n "${_vram_input:-}" && "${_vram_input}" =~ ^[0-9]+$ ]]; then
        _vram_custom=$_vram_input
    fi
fi

_heap_custom=0
if [[ $INTERACTIVE -eq 1 ]]; then
    _heap_cur=$(grep '^-heap' "$STALKER/Anomaly/commandline.txt" 2>/dev/null | awk '{print $2}' || printf "not set")
    printf "\n"
    printf -- "-heap — X-Ray heap allocator ceiling (current: %s MiB)\n" "$_heap_cur"
    printf "  Recommended: over 1024 MiB\n"
    sleep 1
    read -rp "  Custom amount in MiB [press Enter to skip]: " _heap_input
    if [[ -n "${_heap_input:-}" && "${_heap_input}" =~ ^[0-9]+$ ]]; then
        _heap_custom=$_heap_input
    fi
fi

# ── CPU + NVIDIA persistence ───────────────────────────────────────────────────
info "CPU + NVIDIA persistence: applying privileged tweaks..."
sudo "$STALKER/perf-root.sh"
EPP_NOTE=$( [[ $HAS_EPP -eq 1 ]] && printf " + performance EPP" || printf "" )
ok "CPU ($CPU_THREADS threads): performance governor${EPP_NOTE}"

if [[ "$GPU_VENDOR" == "nvidia" ]]; then
    ok "NVIDIA: persistence mode ON"
    info "NVIDIA: setting prefer-max-performance..."
    DISPLAY="${DISPLAY:-:0}" nvidia-settings -a '[gpu:0]/GpuPowerMizerMode=1' > /dev/null 2>&1 \
        && ok "NVIDIA: GpuPowerMizerMode → 1 (prefer max performance)" \
        || warn "nvidia-settings failed — DISPLAY not set; power mizer unchanged."
else
    warn "Non-NVIDIA GPU ($GPU_NAME) — skipping NVIDIA-specific tuning."
fi

# ── DXVK config ────────────────────────────────────────────────────────────────
DXVK_CONF="$STALKER/Anomaly/dxvk.conf"
info "Writing $DXVK_CONF..."
cat > "$DXVK_CONF" << 'EOF'
dxvk.numCompilerThreads = 0
dxgi.maxFrameLatency = 1
dxvk.enableAsync = True
dxvk.enableGraphicsPipelineLibrary = True
EOF
if [[ $_vram_custom -gt 0 ]]; then
    printf 'dxgi.maxDeviceMemory = %s\n' "$_vram_custom" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${_vram_custom} MiB (custom)"
else
    printf 'dxgi.maxDeviceMemory = %s\n' "$VRAM_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${VRAM_CAP} MiB (auto 7/8)"
fi
if [[ $FRAME_CAP -gt 0 ]]; then
    printf 'dxgi.maxFrameRate = %s\n' "$FRAME_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf written (frame cap: ${FRAME_CAP}fps)"
else
    ok "dxvk.conf written (uncapped)"
fi

# ── commandline.txt ────────────────────────────────────────────────────────────
CMDLINE="$STALKER/Anomaly/commandline.txt"
if [[ -f "$CMDLINE" ]]; then
    if grep -q '^-dbg$' "$CMDLINE"; then
        sed -i '/^-dbg$/d' "$CMDLINE"
        ok "commandline.txt: removed -dbg"
    else
        ok "commandline.txt: -dbg not present"
    fi
    _heap_val=$(( _heap_custom > 0 ? _heap_custom : 1024 ))
    if grep -q '^-heap' "$CMDLINE"; then
        sed -i "s/^-heap.*/-heap $_heap_val/" "$CMDLINE"
    else
        printf -- '-heap %s\n' "$_heap_val" >> "$CMDLINE"
    fi
    ok "commandline.txt: -heap ${_heap_val} MiB"
fi

# ── A-Life online simulation radius ───────────────────────────────────────────
# switch_distance default is 450m; 200m cuts ~80% of simulated area while
# preserving all practical combat ranges. auto_switch_distance_normal must also
# be 200 — ZONA's Lua adjuster overrides switch_distance at runtime after load;
# leaving it at 450 silently undoes the change after ~10 seconds.
_alife_choice=""
if [[ $INTERACTIVE -eq 1 ]]; then
    printf "\n"
    sleep 1
    read -rp "Apply A-Life patch? (switch_distance 450→200, prevents CPU overrun) [Y/n]: " _alife_choice
fi

# Search ZONA mods for alife.ltx, fall back to Anomaly gamedata
ALIFE_LTX=""
for _candidate in "$STALKER/ZONA/mods/"*/gamedata/configs/alife.ltx; do
    [[ -f "$_candidate" ]] && ALIFE_LTX="$_candidate" && break
done
[[ -z "$ALIFE_LTX" && -f "$STALKER/Anomaly/gamedata/configs/alife.ltx" ]] && \
    ALIFE_LTX="$STALKER/Anomaly/gamedata/configs/alife.ltx"

if [[ "${_alife_choice:-Y}" =~ ^[Yy]$ ]]; then
    if [[ -n "$ALIFE_LTX" ]]; then
        info "Patching alife.ltx..."
        sed -i '/^\s*switch_distance\s*=/s/= [0-9]*/= 200/' "$ALIFE_LTX"
        sed -i '/auto_switch_distance_normal/s/= [0-9]*/= 200/' "$ALIFE_LTX"
        ok "alife.ltx: switch_distance → 200m | auto_switch_distance_normal → 200m"
    else
        warn "alife.ltx not found under ZONA/mods/ or Anomaly/gamedata/ — skipping A-Life patch"
    fi
else
    ok "A-Life patch skipped."
fi

# ── Active engine binary — AVX selection ─────────────────────────────────────
# Both AnomalyDX11.exe (standard) and AnomalyDX11AVX.exe (AVX) were placed by
# the modded exes install step. MO2's "Anomaly (DX11)" points to AnomalyDX11.exe.
# Deploy the AVX build over it if the CPU supports AVX.
_active_bin="$STALKER/Anomaly/bin/AnomalyDX11.exe"
_avx_bin="$STALKER/Anomaly/bin/AnomalyDX11AVX.exe"
if [[ $HAS_AVX -eq 1 ]] && [[ -f "$_avx_bin" ]]; then
    cp "$_avx_bin" "$_active_bin"
    rm -rf "$STALKER/Anomaly/appdata/shaders_cache/r4/"
    ok "AnomalyDX11.exe → AVX build (shader cache cleared)"
elif [[ -f "$_active_bin" ]]; then
    ok "AnomalyDX11.exe: standard build (AVX not supported)"
else
    warn "AnomalyDX11.exe not found — modded exes may not be installed"
fi

# ── Optional: gamemode ────────────────────────────────────────────────────────
if ! command -v gamemoderun &>/dev/null; then
    if [[ -t 0 ]]; then
        info "Installing gamemode..."
        sudo pacman -S --needed --noconfirm gamemode || warn "gamemode install failed — remove gamemoderun from launch options if the game won't start."
    else
        warn "gamemode not installed — run perf.sh manually once to install it."
    fi
fi

printf "\n"
printf '\033[1mIf MO2 crashes, click Run again — up to 3 times. Stable once it loads once.\033[0m\n'
printf "\n"

# ── Custom settings prompt (interactive only) ──────────────────────────────────
if [[ -t 0 ]] && [[ -x "$STALKER/settings-inject.sh" ]] && [[ -d "$STALKER/settings" ]]; then
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf '\033[1m  Inject Custom Settings?\033[0m\n'
    printf '\033[1m\033[0m\n'
    printf '\033[1m  Pre-configured settings shipped with this repo —\033[0m\n'
    printf '\033[1m  graphics, MCM, and mod loadout tuned so ZONA is\033[0m\n'
    printf '\033[1m  actually playable out of the box.\033[0m\n'
    printf '\033[1m──────────────────────────────────────────────────────\033[0m\n'
    printf "\n"
    sleep 1
    read -rp "Inject? [Y/n]: " _inject_choice
    if [[ "${_inject_choice:-Y}" =~ ^[Yy]$ ]]; then
        bash "$STALKER/settings-inject.sh"
    else
        ok "Skipped — run ./settings-inject.sh manually any time."
    fi
    printf "\n"
fi

# ── X-Ray threading + resolution (user.ltx) ───────────────────────────────────
USER_LTX="$STALKER/Anomaly/appdata/user.ltx"
if [[ -f "$USER_LTX" ]]; then
    info "Patching user.ltx..."
    if grep -q 'r__threaded_path' "$USER_LTX"; then
        sed -i 's/^r__threaded_path.*/r__threaded_path on/' "$USER_LTX"
    else
        printf 'r__threaded_path on\n' >> "$USER_LTX"
    fi
    ok "user.ltx: r__threaded_path on"
    sed -i '/^lua_gcstep/d' "$USER_LTX"
    printf 'lua_gcstep 35\n' >> "$USER_LTX"
    sed -i '/^lua_parallel_gcstep/d' "$USER_LTX"
    printf 'lua_parallel_gcstep 75\n' >> "$USER_LTX"
    sed -i '/^lua_parallel_gc_call_amount/d' "$USER_LTX"
    printf 'lua_parallel_gc_call_amount 37\n' >> "$USER_LTX"
    ok "user.ltx: lua_gcstep 35 | lua_parallel_gcstep 75 | lua_parallel_gc_call_amount 37"
    if grep -q 'vid_mode' "$USER_LTX"; then
        sed -i "s/^vid_mode.*/vid_mode ${GAME_W}x${GAME_H}/" "$USER_LTX"
    else
        printf 'vid_mode %sx%s\n' "$GAME_W" "$GAME_H" >> "$USER_LTX"
    fi
    ok "user.ltx: vid_mode → ${GAME_W}x${GAME_H}"
    if grep -q '^r__detail_density' "$USER_LTX"; then
        sed -i 's/^r__detail_density.*/r__detail_density 0.5/' "$USER_LTX"
    else
        printf 'r__detail_density 0.5\n' >> "$USER_LTX"
    fi
    if grep -q '^r__detail_height' "$USER_LTX"; then
        sed -i 's/^r__detail_height.*/r__detail_height 0.5/' "$USER_LTX"
    else
        printf 'r__detail_height 0.5\n' >> "$USER_LTX"
    fi
    if grep -q '^r__detail_radius' "$USER_LTX"; then
        sed -i 's/^r__detail_radius.*/r__detail_radius 40/' "$USER_LTX"
    else
        printf 'r__detail_radius 40\n' >> "$USER_LTX"
    fi
    ok "user.ltx: r__detail_density 0.5 | r__detail_height 0.5 | r__detail_radius 40"
else
    warn "user.ltx not found at $USER_LTX — launch the game once first, then re-run."
fi
