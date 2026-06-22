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

info "Detected CPU:     $CPU_MODEL ($CPU_CORES cores, $CPU_THREADS_PER_CORE threads/core)"
info "Detected GPU:     $GPU_NAME"
info "Detected VRAM:    ${VRAM_MIB} MiB"
info "Detected display: ${NATIVE_W}x${NATIVE_H} (primary)"

# ── Interactive configuration ──────────────────────────────────────────────────
INTERACTIVE=0
[[ -t 0 ]] && INTERACTIVE=1


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
# TODO: verify perf-root.sh correctly applies governor + NVIDIA persistence on a clean install
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
# Read existing values before overwriting so blank prompts preserve them
_existing_vram=$(grep -E '^dxgi\.maxDeviceMemory' "$DXVK_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' \r' || true)
_existing_framerate=$(grep -E '^dxgi\.maxFrameRate' "$DXVK_CONF" 2>/dev/null | cut -d= -f2 | tr -d ' \r' || true)

info "Writing $DXVK_CONF..."
cat > "$DXVK_CONF" << 'EOF'
dxvk.numCompilerThreads = 0
dxvk.enableGraphicsPipelineLibrary = True
EOF

if [[ $_vram_custom -gt 0 ]]; then
    printf 'dxgi.maxDeviceMemory = %s\n' "$_vram_custom" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${_vram_custom} MiB"
elif [[ -n "$_existing_vram" ]]; then
    printf 'dxgi.maxDeviceMemory = %s\n' "$_existing_vram" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${_existing_vram} MiB (unchanged)"
else
    printf 'dxgi.maxDeviceMemory = %s\n' "$VRAM_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf: maxDeviceMemory → ${VRAM_CAP} MiB (auto 7/8)"
fi

if [[ $FRAME_CAP -gt 0 ]]; then
    printf 'dxgi.maxFrameRate = %s\n' "$FRAME_CAP" >> "$DXVK_CONF"
    ok "dxvk.conf: maxFrameRate → ${FRAME_CAP}fps"
elif [[ -n "$_existing_framerate" ]]; then
    printf 'dxgi.maxFrameRate = %s\n' "$_existing_framerate" >> "$DXVK_CONF"
    ok "dxvk.conf: maxFrameRate → ${_existing_framerate}fps (unchanged)"
else
    ok "dxvk.conf written (uncapped)"
fi

# ── commandline.txt ────────────────────────────────────────────────────────────
CMDLINE="$STALKER/Anomaly/commandline.txt"
if [[ -f "$CMDLINE" ]]; then
    sed -i 's/\r$//' "$CMDLINE"
    sed -i '/^-dbg$/d' "$CMDLINE"
    if [[ $_heap_custom -gt 0 ]]; then
        sed -i '/^-heap/d' "$CMDLINE"
        printf -- '-heap %s\n' "$_heap_custom" >> "$CMDLINE"
        ok "commandline.txt: -heap ${_heap_custom} MiB"
    else
        _heap_cur=$(grep '^-heap' "$CMDLINE" 2>/dev/null | awk '{print $2}' || true)
        ok "commandline.txt: -heap unchanged (${_heap_cur:-not set} MiB)"
    fi
    if ! grep -q '^-nolog$' "$CMDLINE"; then
        printf -- '-nolog\n' >> "$CMDLINE"
        ok "commandline.txt: -nolog added"
    fi
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

# ── X-Ray threading (user.ltx) — disabled pending testing ────────────────────
# lua_gcstep 35 is the confirmed value. Re-enable once settings are verified on ZONA.
# if false; then
# USER_LTX="$STALKER/Anomaly/appdata/user.ltx"
# if [[ -f "$USER_LTX" ]]; then
#     info "Patching user.ltx..."
#     if grep -q 'r__threaded_path' "$USER_LTX"; then
#         sed -i 's/^r__threaded_path.*/r__threaded_path on/' "$USER_LTX"
#     else
#         printf 'r__threaded_path on\n' >> "$USER_LTX"
#     fi
#     ok "user.ltx: r__threaded_path on"
#     sed -i '/^lua_gcstep/d' "$USER_LTX"
#     printf 'lua_gcstep 35\n' >> "$USER_LTX"
#     sed -i '/^lua_parallel_gcstep/d' "$USER_LTX"
#     printf 'lua_parallel_gcstep 75\n' >> "$USER_LTX"
#     sed -i '/^lua_parallel_gc_call_amount/d' "$USER_LTX"
#     printf 'lua_parallel_gc_call_amount 37\n' >> "$USER_LTX"
#     ok "user.ltx: lua_gcstep 35 | lua_parallel_gcstep 75 | lua_parallel_gc_call_amount 37"
#     if grep -q '^r__detail_density' "$USER_LTX"; then
#         sed -i 's/^r__detail_density.*/r__detail_density 0.5/' "$USER_LTX"
#     else
#         printf 'r__detail_density 0.5\n' >> "$USER_LTX"
#     fi
#     if grep -q '^r__detail_height' "$USER_LTX"; then
#         sed -i 's/^r__detail_height.*/r__detail_height 0.5/' "$USER_LTX"
#     else
#         printf 'r__detail_height 0.5\n' >> "$USER_LTX"
#     fi
#     if grep -q '^r__detail_radius' "$USER_LTX"; then
#         sed -i 's/^r__detail_radius.*/r__detail_radius 40/' "$USER_LTX"
#     else
#         printf 'r__detail_radius 40\n' >> "$USER_LTX"
#     fi
#     ok "user.ltx: r__detail_density 0.5 | r__detail_height 0.5 | r__detail_radius 40"
# else
#     warn "user.ltx not found at $USER_LTX"
# fi
# fi

ok "Performance tuning complete."
