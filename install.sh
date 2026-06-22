#!/usr/bin/env bash
# install.sh — STALKER ZONA installer for Arch Linux (PortProton)
set -uo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
MO2_VERSION="2.5.2"
DOTNET_PREFIX_NAME="DOTNET"
PP_ROOT="$HOME/PortProton"
# Stable GitHub release — if the version changes, update this line (see links.txt)
MODDED_EXES_URL="https://github.com/themrdemonized/xray-monolith/releases/download/2026.3.29/STALKER-Anomaly-modded-exes_2026.3.29.zip"

# ── Output helpers ─────────────────────────────────────────────────────────────
B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' R='\033[1;31m' N='\033[0m'
info()  { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()    { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn()  { printf "${Y}[!]${N} %s\n" "$*" >&2; }
die()   { printf "${R}[✗]${N} %s\n" "$*" >&2; exit 1; }
enter() { printf "${Y}[press Enter when done]${N} " >&2; read -r _ || true; }

# Parse a Google Drive file ID from either a full share URL or a bare ID.
_parse_gdrive_id() {
    local input="$1"
    if [[ "$input" =~ /d/([A-Za-z0-9_-]{10,}) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$input"
    fi
}

# ── Working directory ──────────────────────────────────────────────────────────
STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf "Stalker directory [%s]: " "$STALKER"; read -r _tmp || true
STALKER="${_tmp:-$STALKER}"
[[ -d "$STALKER" ]] || die "Not a directory: $STALKER"
cd "$STALKER"

mkdir -p "$STALKER/pip-cache" "$STALKER/cache" "$STALKER/Anomaly" "$STALKER/ZONA"

# ── Step completion tracking ───────────────────────────────────────────────────
STEPS_DIR="$STALKER/.install_steps"
mkdir -p "$STEPS_DIR"

_done()  { [[ -f "$STEPS_DIR/$1" ]]; }
_mark()  { touch "$STEPS_DIR/$1"; }
_clear() { rm -f "$STEPS_DIR/$1"; }

# ── File presence checks ───────────────────────────────────────────────────────
# Used to detect already-installed state without relying solely on step markers.

_anomaly_ok() {
    [[ -f "$STALKER/Anomaly/AnomalyLauncher.exe" ]] && \
    [[ -f "$STALKER/Anomaly/db/levels/levels.db0" ]]
}

_zona_ok() {
    _anomaly_ok && [[ -f "$STALKER/ZONA/ModOrganizer.exe" ]]
}

_modded_exes_ok() {
    [[ -f "$STALKER/Anomaly/db/mods/00_modded_exes_gamedata.db0" ]]
}

_portproton_prefix_dir() {
    printf '%s/data/prefixes/%s' "$PP_ROOT" "$DOTNET_PREFIX_NAME"
}

# Asks the user whether PortProton is already installed and where.
# Sets PP_ROOT to the confirmed path; exits with error if path not found.
_detect_portproton() {
    printf "\n"
    printf "${Y}Have you already set up PortProton? [y/N]:${N} " >&2
    read -r _pp_ans || _pp_ans=""
    [[ "${_pp_ans:-N}" =~ ^[Yy]$ ]] && _PP_SETUP_DONE=1 || _PP_SETUP_DONE=0
}

# ── System packages ────────────────────────────────────────────────────────────
# Abort early if multilib is not enabled — required for 32-bit Wine libraries.
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    die "multilib not enabled — uncomment [multilib] in /etc/pacman.conf, then: sudo pacman -Sy"
fi

PKGS=(python git libunrar curl p7zip winetricks xorg-xrandr gamemode)
MISSING=()
for p in "${PKGS[@]}"; do pacman -Q "$p" &>/dev/null || MISSING+=("$p"); done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    info "Installing packages: ${MISSING[*]}"
    if ! sudo pacman -S --needed --noconfirm "${MISSING[@]}"; then
        warn "Some packages failed to install. Install them manually and re-run:"
        printf "  sudo pacman -S --needed %s\n" "${MISSING[*]}" >&2
        enter
    fi
fi

# ── PortProton ─────────────────────────────────────────────────────────────────
# Required for running Windows executables (Anomaly, MO2) under Wine/Proton.
if command -v portproton &>/dev/null; then
    ok "PortProton: already installed"
else
    info "Installing PortProton..."
    _pp_ok=0
    if command -v yay &>/dev/null; then
        yay -S --needed --noconfirm portproton && _pp_ok=1
    elif command -v paru &>/dev/null; then
        paru -S --needed --noconfirm portproton && _pp_ok=1
    fi
    if [[ $_pp_ok -eq 0 ]]; then
        warn "PortProton install failed or no AUR helper found."
        printf "  Install manually: yay -S portproton  then re-run.\n" >&2
        enter
        command -v portproton &>/dev/null || die "PortProton still not found — cannot continue."
    fi
    ok "PortProton installed."
fi

# ── Python venv ────────────────────────────────────────────────────────────────
# Isolated venv keeps gdrive-ripper and gamma-launcher off the system Python.
[[ -f zona/bin/activate ]] || python -m venv zona
source "$STALKER/zona/bin/activate"
TMPDIR="$STALKER/pip-cache" pip install -q --upgrade pip setuptools

# ── gdrive-ripper ─────────────────────────────────────────────────────────────
# Used to download the ZONA modpack from Google Drive.
# If unavailable, the ZONA download step will require a pre-placed archive.
if ! command -v gdrive-ripper &>/dev/null; then
    GDRIVE_RIPPER_SRC="$HOME/Applications/GitHub/gdrive-ripper"
    if [[ -d "$GDRIVE_RIPPER_SRC" ]]; then
        TMPDIR="$STALKER/pip-cache" pip install -q "$GDRIVE_RIPPER_SRC" || \
            warn "gdrive-ripper install failed — ZONA download step will need a manual archive."
    else
        warn "gdrive-ripper not found — ZONA download will need a manual archive."
        printf "  Last known ZONA link is in: %s/links.txt\n" "$STALKER" >&2
    fi
fi
command -v gdrive-ripper &>/dev/null && ok "gdrive-ripper ready" || true

# ── gamma-launcher ─────────────────────────────────────────────────────────────
# Handles the Anomaly 1.5.3 download from the official ModDB release.
# Cloned from a stable public GitHub repo — does not require Discord.
if ! command -v gamma-launcher &>/dev/null; then
    [[ -d gamma-launcher/.git ]] || \
        git clone https://github.com/Mord3rca/gamma-launcher.git || \
        warn "gamma-launcher clone failed — Anomaly install will need a manual archive."
    if [[ -d gamma-launcher ]]; then
        (cd gamma-launcher && TMPDIR="$STALKER/pip-cache" pip install -q .) || \
            warn "gamma-launcher install failed."
    fi
fi
command -v gamma-launcher &>/dev/null && \
    ok "gamma-launcher $(gamma-launcher --version 2>&1 | head -1)" || true

# ── Re-run menu ────────────────────────────────────────────────────────────────
# Shown when ZONA is already fully installed. Offers update, backup, and reset.
_FORCE_INSTALL=0
_WINETRICKS_ONLY=0

_clear_shader_cache() {
    local _removed=0
    if [[ -d "$STALKER/Anomaly/appdata/shaders_cache" ]]; then
        rm -rf "$STALKER/Anomaly/appdata/shaders_cache/"
        ok "Cleared: Anomaly/appdata/shaders_cache/"
        _removed=1
    fi
    while IFS= read -r _f; do
        rm -f "$_f"
        ok "Cleared: $(realpath --relative-to="$STALKER" "$_f")"
        _removed=1
    done < <(find "$STALKER/Anomaly" -maxdepth 3 -name "*.dxvk-cache" 2>/dev/null)
    (( _removed )) || warn "No shader cache files found — nothing to clear."
}

# Copies ZONA-supplied user.ltx and axr_options.ltx into the Anomaly tree.
# Pass 1 to force-overwrite existing files; omit or pass 0 to skip if present.
_place_settings() {
    local _force="${1:-0}"
    local user_ltx axr_ltx
    user_ltx=$(find "$STALKER/ZONA" -name "user.ltx" 2>/dev/null | head -1 || true)
    if [[ -n "$user_ltx" ]]; then
        if [[ "$_force" -eq 1 || ! -f "$STALKER/Anomaly/appdata/user.ltx" ]]; then
            mkdir -p "$STALKER/Anomaly/appdata"
            cp -f "$user_ltx" "$STALKER/Anomaly/appdata/user.ltx"
            ok "user.ltx → Anomaly/appdata/user.ltx"
        else
            ok "user.ltx: already exists (skipping)"
        fi
    else
        warn "user.ltx not found in ZONA — place it manually at: Anomaly/appdata/user.ltx"
    fi

    axr_ltx=$(find "$STALKER/ZONA" -name "axr_options.ltx" 2>/dev/null | head -1 || true)
    if [[ -n "$axr_ltx" ]]; then
        if [[ "$_force" -eq 1 || ! -f "$STALKER/Anomaly/gamedata/configs/axr_options.ltx" ]]; then
            mkdir -p "$STALKER/Anomaly/gamedata/configs"
            cp -f "$axr_ltx" "$STALKER/Anomaly/gamedata/configs/axr_options.ltx"
            ok "axr_options.ltx → Anomaly/gamedata/configs/axr_options.ltx"
        else
            ok "axr_options.ltx: already exists (skipping)"
        fi
    else
        warn "axr_options.ltx not found in ZONA — place it manually at: Anomaly/gamedata/configs/axr_options.ltx"
    fi
}

if _zona_ok; then
    printf "\n"
    info "ZONA is installed. What would you like to do?"
    printf "\n"
    printf "  1) Update / re-install ZONA\n"
    printf "  2) Redo PortProton / winetricks setup\n"
    printf "  3) Performance tweaks (recommended after option 2)\n"
    printf "  4) Backup settings\n"
    printf "  5) Restore settings\n"
    printf "  6) Reset install progress (re-run all steps)\n"
    printf "  7) Clear shader cache\n"
    printf "  8) Exit\n"
    printf "\n"
    printf "${R}   WARNING: NEVER click SETTINGS → Find settings (ppdb) in PortProton.\n"
    printf "           It overwrites the ppdb and ruins everything. It also does\n"
    printf "           some other things that somehow ruin everything in a truly amazing way.${N}\n"
    printf "\n"
    if [[ -n "${ZONA_STEP:-}" ]]; then
        _choice="$ZONA_STEP"
    else
        printf "${Y}  Choice [1-8]:${N} "; read -r _choice || _choice=8
    fi

    _BACKUP_DIR="$STALKER/.settings_backups"

    _backup_settings() {
        local ts; ts=$(date '+%Y-%m-%d_%H-%M-%S')
        local dest="$_BACKUP_DIR/$ts"
        mkdir -p "$dest/appdata" "$dest/profiles"
        cp "$STALKER/Anomaly/appdata/"*.ltx "$dest/appdata/" 2>/dev/null || true
        [[ -f "$STALKER/Anomaly/appdata/imgui.ini" ]] && \
            cp "$STALKER/Anomaly/appdata/imgui.ini" "$dest/appdata/" || true
        for profile_dir in "$STALKER/ZONA/profiles/"/*/; do
            local pname; pname=$(basename "$profile_dir")
            mkdir -p "$dest/profiles/$pname"
            cp "$profile_dir"*.{txt,ini} "$dest/profiles/$pname/" 2>/dev/null || true
        done
        ok "Settings backed up → $dest"
    }

    _perf_tweaks() {
        local T='  '
        info "Changing PortProton settings:"
        printf "\n"
        printf "${T}1. Open ModOrganizer.exe with PortProton\n"
        printf "${T}2. Go to SETTINGS → Base Settings and apply the following:\n"
        printf "\n"
        printf "${T}┌──────────────────────┬─────┬──────────────────────┬─────┬──────────────────────┬─────┐\n"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "SETTING" "VAL" "SETTING" "VAL" "SETTING" "VAL"
        printf "${T}├──────────────────────┼─────┼──────────────────────┼─────┼──────────────────────┼─────┤\n"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "MANGOHUD"           "OFF" "WINE FULLSCREEN FSR" "ON"  "USE WINE DXGI"        "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "MANGOHUD USER CONF" "OFF" "HIDE NVIDIA GPU"     "OFF" "USE EAC AND BE"       "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "VKBASALT"           "OFF" "VIRTUAL DESKTOP"     "OFF" "USE SYSTEM VK LAYERS" "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "VKBASALT USER CONF" "OFF" "USE TERMINAL"        "OFF" "USE OBS VKCAPTURE"    "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "DGVOODOO2"          "OFF" "GUI DISABLED CS"     "OFF" "DISABLE COMPOSITING"  "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE ESYNC"          "OFF" "USE GAMEMODE"        "ON"  "USE RUNTIME"          "ON"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE FSYNC"          "OFF" "USE INHIBIT SLEEP"   "OFF" "DINPUT PROTOCOL"      "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE NTSYNC"         "ON"  "USE D3D EXTRAS"      "OFF" "USE GALLIUM ZINK"     "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE RAY TRACING"    "OFF" "FIX VIDEO IN GAME"   "OFF" "USE WINED3D VULKAN"   "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE NVAPI AND DLSS" "OFF" "REDUCE PULSE LATENCY" "OFF" "USE NATIVE WAYLAND"  "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE OPTISCALER"     "OFF" "USE GSTREAMER"       "OFF" "USE DXVK HDR"         "OFF"
        printf "${T}│ %-20s │ %-3s │ %-20s │ %-3s │ %-20s │ %-3s │\n" \
            "USE LS FRAME GEN"   "OFF" "USE SHADER CACHE"    "OFF" "GAMESCOPE"            "OFF"
        printf "${T}└──────────────────────┴─────┴──────────────────────┴─────┴──────────────────────┴─────┘\n"
        printf "\n"
        printf "${T}These are a starting point. If the game crashes 3+ times,\n"
        printf "${T}set USE NTSYNC → OFF and USE FSYNC → ON, then retry.\n"
        printf "\n"
    }

    _restore_settings() {
        if [[ ! -d "$_BACKUP_DIR" ]] || [[ -z "$(ls -A "$_BACKUP_DIR" 2>/dev/null)" ]]; then
            warn "No backups found in $_BACKUP_DIR"; return
        fi
        local backups=()
        while IFS= read -r d; do backups+=("$(basename "$d")"); done \
            < <(find "$_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
        printf "\n  Available backups (newest first):\n"
        local i=1
        for b in "${backups[@]}"; do printf "    %d) %s\n" "$i" "$b"; (( i++ )); done
        printf "\n"
        printf "${Y}  Choose backup [1-%d] or 0 to cancel:${N} " "${#backups[@]}"
        read -r _pick || _pick=0
        [[ "$_pick" == "0" ]] && return
        if ! [[ "$_pick" =~ ^[0-9]+$ ]] || (( _pick < 1 || _pick > ${#backups[@]} )); then
            warn "Invalid choice."; return
        fi
        local src="$_BACKUP_DIR/${backups[$(( _pick - 1 ))]}"
        cp "$src/appdata/"*.ltx "$STALKER/Anomaly/appdata/" 2>/dev/null || true
        [[ -f "$src/appdata/imgui.ini" ]] && \
            cp "$src/appdata/imgui.ini" "$STALKER/Anomaly/appdata/" || true
        for profile_src in "$src/profiles/"/*/; do
            local pname; pname=$(basename "$profile_src")
            local pdest="$STALKER/ZONA/profiles/$pname"
            [[ -d "$pdest" ]] && cp "$profile_src"*.{txt,ini} "$pdest/" 2>/dev/null || true
        done
        ok "Settings restored from ${backups[$(( _pick - 1 ))]}."
    }

    case "$_choice" in
        1)
            printf "\n"
            printf "  1) Full re-install (skips steps already completed)\n"
            printf "  2) Reset settings only (overwrites user.ltx and axr_options.ltx)\n"
            printf "\n"
            printf "${Y}  Choice [1-2]:${N} "; read -r _sub || _sub=""
            case "${_sub:-1}" in
                1) ;;
                2) _place_settings 1; exit 0 ;;
                *) warn "Invalid choice." ;;
            esac
            ;;
        2) _WINETRICKS_ONLY=1 ;;
        3) _perf_tweaks
           printf "  Press Enter when done to run performance tuning... "
           read -r _
           bash "$STALKER/perf.sh"
           exit 0 ;;
        4) _backup_settings; exit 0 ;;
        5) _restore_settings; exit 0 ;;
        6) rm -rf "$STEPS_DIR"; mkdir -p "$STEPS_DIR"; ok "Progress reset." ;;
        7)
            printf "\n"
            printf "${Y}Clear shader cache? [y/N]:${N} " >&2
            read -r _cc || _cc=""
            if [[ "${_cc:-N}" =~ ^[Yy]$ ]]; then
                _clear_shader_cache
            else
                warn "Shader cache clear cancelled."
            fi
            exit 0
            ;;
        8) exit 0 ;;
        *) warn "Invalid choice." ;;
    esac
fi

# ── Step 1: Anomaly 1.5.3 ─────────────────────────────────────────────────────
# gamma-launcher fetches Anomaly from the official ModDB release page.
# This is a stable link that does not require a Discord account.
if _done anomaly && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "Anomaly: already installed (skipping)"
elif _anomaly_ok && [[ $_FORCE_INSTALL -eq 0 ]]; then
    _mark anomaly
    ok "Anomaly: already installed (skipping)"
else
    info "Installing Anomaly 1.5.3..."
    warn "Large download — disable sleep/screen lock before walking away."
    if command -v gamma-launcher &>/dev/null; then
        until TMPDIR="$STALKER/pip-cache" \
              gamma-launcher anomaly-install \
                  --anomaly         "$STALKER/Anomaly" \
                  --cache-directory "$STALKER/cache"; do
            warn "Anomaly install failed."
            printf "  If this keeps failing, download Anomaly 1.5.3 manually from ModDB\n" >&2
            printf "  and extract it to: %s/Anomaly\n" "$STALKER" >&2
            printf "${Y}[Enter to retry, Ctrl+C to abort]${N} " >&2; read -r _ || true
        done
        _mark anomaly
        ok "Anomaly installed."
    else
        warn "gamma-launcher not available — install Anomaly manually."
        printf "  Download Anomaly 1.5.3 from ModDB and extract to: %s/Anomaly\n" "$STALKER" >&2
        enter
        _anomaly_ok && { _mark anomaly; ok "Anomaly detected."; } || \
            warn "Anomaly still not detected at expected path — continuing anyway."
    fi
fi

# ── Step 2: Mod Organizer 2 ───────────────────────────────────────────────────
# Downloaded from the official MO2 GitHub release — versioned, stable URL.
if _done mo2 && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "MO2: already installed (skipping)"
elif [[ -f "$STALKER/ZONA/ModOrganizer.exe" ]] && [[ $_FORCE_INSTALL -eq 0 ]]; then
    _mark mo2
    ok "MO2: already installed (skipping)"
else
    info "Downloading Mod Organizer 2 v${MO2_VERSION}..."
    MO2_URL="https://github.com/ModOrganizer2/modorganizer/releases/download/v${MO2_VERSION}/Mod.Organizer-${MO2_VERSION}.7z"
    MO2_CACHE="$STALKER/cache/ModOrganizer-${MO2_VERSION}.7z"

    if [[ ! -f "$MO2_CACHE" ]]; then
        if ! curl -L --fail --progress-bar -o "$MO2_CACHE" "$MO2_URL"; then
            warn "MO2 download failed."
            printf "  Download manually from:\n  %s\n" "$MO2_URL" >&2
            printf "  Save to: %s\n" "$MO2_CACHE" >&2
            enter
        fi
    else
        ok "MO2: using cached archive"
    fi

    if [[ -f "$MO2_CACHE" ]]; then
        info "Extracting MO2 → ZONA/..."
        if ! 7z x -o"$STALKER/ZONA" -y "$MO2_CACHE" > /dev/null; then
            warn "MO2 extraction failed — archive may be corrupt."
            rm -f "$MO2_CACHE"
            printf "  Re-run to retry.\n" >&2
        else
            _mark mo2
            ok "MO2 installed → ZONA/ModOrganizer.exe"
        fi
    else
        warn "MO2 archive not found — skipping. Re-run after placing it at: $MO2_CACHE"
    fi
fi

# ── Step 3: ZONA modpack download ─────────────────────────────────────────────
# The ZONA link changes with each release and is posted in the #install-zona
# Discord channel. Paste the Google Drive share link when prompted.
# No Discord account? The last known link is in: $STALKER/links.txt
if [[ $_WINETRICKS_ONLY -eq 1 ]]; then
    true  # option 2 (Redo PortProton/winetricks) — skip ZONA download
elif _done zona_dl && [[ -s "$STALKER/cache/zona.7z" ]] && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "ZONA archive: already downloaded (skipping)"
else
    if command -v gdrive-ripper &>/dev/null; then
        printf "\n"
        warn "The ZONA link is posted in the #install-zona Discord channel."
        printf "  No Discord account? Check the last known link in: %s/links.txt\n\n" "$STALKER" >&2
        printf "${Y}Paste the ZONA Google Drive link (or press Enter to skip):${N} " >&2
        read -r _zona_input || _zona_input=""
        ZONA_GDRIVE_ID="$(_parse_gdrive_id "${_zona_input:-}")"

        if [[ -z "$ZONA_GDRIVE_ID" ]]; then
            warn "No link provided — skipping ZONA download. Re-run to retry."
        else
            ok "GDrive ID: $ZONA_GDRIVE_ID"
            info "Downloading ZONA modpack..."
            while true; do
                rm -f "$STALKER/cache/zona.7z"
                if gdrive-ripper --id "$ZONA_GDRIVE_ID" -o "$STALKER/cache/zona.7z" && \
                   [[ -s "$STALKER/cache/zona.7z" ]]; then
                    _mark zona_dl
                    ok "ZONA downloaded."
                    break
                fi
                rm -f "$STALKER/cache/zona.7z"
                warn "ZONA download failed. What went wrong?"
                printf "\n"
                printf "  1) No cookies — not signed in to Google\n"
                printf "  2) Bad/expired cookies — signed out while cookies were active\n"
                printf "  3) Link superseded — there is a newer ZONA release\n"
                printf "\n"
                printf "${Y}  Choice [1-3, or Enter to abort]:${N} "; read -r _fail || _fail=""
                [[ -z "$_fail" ]] && { warn "Download aborted — re-run to retry."; break; }
                case "$_fail" in
                    1|2)
                        printf "\n"
                        printf "  1. Open a browser and sign in to Google\n"
                        printf "  2. In a new terminal, run:\n"
                        printf "       source %s/zona/bin/activate\n" "$STALKER"
                        printf "       gdrive-ripper --get-cookies\n"
                        printf "  3. Return here and press Enter to retry\n"
                        printf "\n"
                        enter
                        ;;
                    3)
                        printf "\n"
                        printf "  Get the updated link from #install-zona in the ZONA Discord.\n"
                        printf "  (No Discord? Check links.txt for the last known link.)\n"
                        printf "\n"
                        printf "${Y}  Paste new Google Drive link:${N} "; read -r _new_input || _new_input=""
                        _new_id="$(_parse_gdrive_id "${_new_input:-}")"
                        if [[ -n "$_new_id" ]]; then
                            ZONA_GDRIVE_ID="$_new_id"
                            ok "Updated GDrive ID: $ZONA_GDRIVE_ID"
                        else
                            warn "No link provided — retrying with previous ID."
                        fi
                        ;;
                    *)
                        warn "Invalid choice — retrying."
                        ;;
                esac
            done
        fi
    else
        warn "gdrive-ripper not available — ZONA download skipped."
        printf "  Place the ZONA archive at: %s/cache/zona.7z\n" "$STALKER" >&2
        printf "  Last known link: %s/links.txt\n" "$STALKER" >&2
        printf "  Then re-run this script.\n" >&2
    fi
fi

# ── Step 3.5: PortProton DOTNET prefix ────────────────────────────────────────
# The DOTNET prefix must exist before winetricks runs and before either
# AnomalyLauncher.exe or MO2 can be launched through PortProton.
# Prompted here regardless of whether the ZONA download was skipped.
_PP_SETUP_DONE=0
_detect_portproton

if [[ $_PP_SETUP_DONE -eq 0 ]]; then
    info "PortProton DOTNET prefix setup — do this now before continuing."
    printf "\n"
    printf "  1. Open PortProton\n"
    printf "  2. Go to Wine Settings\n"
    printf "  3. Select '%s' from the Prefix dropdown (create if missing)\n" "$DOTNET_PREFIX_NAME"
    printf "  4. Click Winetricks — install: dotnet48\n"
    printf "  5. Close PortProton\n"
    printf "\n"
    enter
    printf "\n"
fi

if [[ $_PP_SETUP_DONE -eq 1 ]]; then
    printf "  Confirm the PortProton installation path\n"
else
    printf "  Enter the path you used for PortProton\n"
fi
printf "  (press Enter for default: %s):\n" "$PP_ROOT"
printf "${Y}  Path:${N} " >&2
read -r _pp_path || _pp_path=""
# Blank enter or explicit default path → winetricks and AnomalyLauncher ppdb already done
_PP_DEFAULT_PATH=0
[[ -z "$_pp_path" || "$_pp_path" == "~/PortProton" || "$_pp_path" == "$HOME/PortProton" ]] \
    && _PP_DEFAULT_PATH=1
_pp_path="${_pp_path:-$PP_ROOT}"
_pp_path="${_pp_path/#\~/$HOME}"
if [[ -d "$_pp_path" ]]; then
    PP_ROOT="$_pp_path"
    ok "PortProton path: $PP_ROOT"
else
    die "PortProton not found at '$_pp_path' — re-run and enter the correct installation path."
fi

DOTNET_PREFIX="$(_portproton_prefix_dir)"
if [[ ! -d "$DOTNET_PREFIX" ]]; then
    warn "DOTNET prefix still not found — winetricks step will be skipped."
else
    ok "DOTNET prefix: already exists"
fi

# ── Step 4: ZONA extract ──────────────────────────────────────────────────────
if _done zona_extract && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "ZONA: already extracted (skipping)"
elif [[ -f "$STALKER/ZONA/ModOrganizer.exe" ]] && [[ $_FORCE_INSTALL -eq 0 ]]; then
    _mark zona_extract
    ok "ZONA: already extracted (skipping)"
elif [[ -s "$STALKER/cache/zona.7z" ]]; then
    info "Extracting ZONA modpack → ZONA/..."
    if ! 7z x -o"$STALKER/ZONA" -y "$STALKER/cache/zona.7z" > /dev/null; then
        warn "ZONA extraction failed — archive may be corrupt."
        _clear zona_dl
        printf "  Delete %s/cache/zona.7z and re-run to re-download.\n" "$STALKER" >&2
    else
        _mark zona_extract
        ok "ZONA extracted."
    fi
else
    warn "ZONA archive not found — skipping extraction. Re-run after downloading."
fi

# ── Step 5: Modded executables ────────────────────────────────────────────────
# Demonized's xray-monolith build adds DLTX support and other engine fixes.
# URL is hardcoded in Configuration above — check links.txt if it ever needs updating.
if _done modded_exes && [[ $_FORCE_INSTALL -eq 0 ]]; then
    ok "Modded exes: already installed (skipping)"
elif _modded_exes_ok && [[ $_FORCE_INSTALL -eq 0 ]]; then
    _mark modded_exes
    ok "Modded exes: already installed (skipping)"
else
    _modded_cache="$STALKER/cache/$(basename "$MODDED_EXES_URL")"

    if [[ ! -f "$_modded_cache" ]]; then
        info "Downloading modded executables..."
        if ! curl -L --fail --progress-bar -o "$_modded_cache" "$MODDED_EXES_URL"; then
            warn "Modded exes download failed."
            printf "  Download manually from:\n  %s\n" "$MODDED_EXES_URL" >&2
            printf "  Save to: %s\n" "$_modded_cache" >&2
            enter
        fi
    else
        ok "Modded exes: using cached archive"
    fi

    if [[ -f "$_modded_cache" ]]; then
        info "Extracting modded executables → Anomaly/..."
        mkdir -p "$STALKER/Anomaly/db/mods"
        if ! 7z x -o"$STALKER/Anomaly" -y "$_modded_cache" > /dev/null; then
            warn "Modded exes extraction failed — archive may be corrupt."
            rm -f "$_modded_cache"
            printf "  Re-run to retry.\n" >&2
        else
            _mark modded_exes
            ok "Modded executables installed."
        fi
    else
        warn "Modded exes archive not found — skipping. Re-run after placing it at: $_modded_cache"
    fi
fi

# ── Step 6: Settings files ────────────────────────────────────────────────────
# _place_settings is defined above (before the re-run menu) so it can be called
# from both the menu (option 1→2 reset) and here during the install flow.
if _done zona_extract || [[ -f "$STALKER/ZONA/ModOrganizer.exe" ]]; then
    _place_settings
fi

# ── Step 6.5: PortProton install guard ────────────────────────────────────────
# Second check in case portproton wasn't in PATH at script start.
if ! command -v portproton &>/dev/null; then
    warn "PortProton not found — required for the steps ahead."
    if command -v yay &>/dev/null || command -v paru &>/dev/null; then
        until command -v portproton &>/dev/null; do
            if command -v yay &>/dev/null; then yay -S --needed portproton
            else paru -S --needed portproton; fi
            command -v portproton &>/dev/null && break
            warn "Install failed — try again or install PortProton manually."
            printf "${Y}[Enter to retry, Ctrl+C to abort]${N} " >&2; read -r _ || true
        done
        ok "PortProton installed."
    else
        die "No AUR helper found — install PortProton manually (yay -S portproton), then re-run."
    fi
fi

# ── Step 7: Winetricks ────────────────────────────────────────────────────────
# Installs DirectX and .NET runtime components into the DOTNET prefix.
# Prefix must already exist — created in step 3.5 above.
# Skipped when user confirmed PortProton is already set up at the default path.
if [[ $_PP_SETUP_DONE -eq 1 && $_PP_DEFAULT_PATH -eq 1 ]]; then
    ok "Winetricks: skipping (already set up)"
elif [[ -d "$DOTNET_PREFIX" ]]; then
    WINE_BIN=""
    for _wine_search in \
        "$PP_ROOT/data/dist/"*/files/bin/wine \
        "$PP_ROOT/data/dist/"*/bin/wine \
        "$(command -v wine 2>/dev/null || true)"; do
        [[ -x "$_wine_search" ]] && { WINE_BIN="$_wine_search"; break; }
    done

    if [[ -n "$WINE_BIN" ]]; then
        info "Installing winetricks components into ${DOTNET_PREFIX_NAME} prefix..."
        warn "SHA hash warnings for vcrun2022 are expected — non-fatal."
        WINE="$WINE_BIN" WINEPREFIX="$DOTNET_PREFIX" winetricks -q \
            cmd d3dcompiler_43 d3dcompiler_47 d3dx10 d3dx11_43 \
            d3dx9 d3dx9_43 dotnet48 mfc42 ogg openal quartz 2>&1 | \
            grep -v '^$' || warn "Some winetricks components may have failed — non-fatal."
        ok "Winetricks done."
    else
        warn "Wine binary not found — install winetricks components manually."
        printf "  In PortProton → Prefix: %s → Winetricks, install:\n" "$DOTNET_PREFIX_NAME" >&2
        printf "  cmd d3dcompiler_43 d3dcompiler_47 d3dx10 d3dx11_43\n" >&2
        printf "  d3dx9 d3dx9_43 dotnet48 mfc42 ogg openal quartz\n" >&2
        enter
    fi
else
    warn "DOTNET prefix still not found — run winetricks manually after creating it."
fi

# ── Step 8: AnomalyLauncher.exe.ppdb ─────────────────────────────────────────
# PortProton's built-in AnomalyLauncher template ships with PW_USE_WINE_DXGI=1,
# which pairs Wine's dxgi.dll with DXVK's d3d11.dll — that combination fails at
# D3D11 device creation (DXGI_ERROR_UNSUPPORTED). A .ppdb next to the exe takes
# priority over the template, so this pre-write ensures DXVK uses its own dxgi.
# Skipped when user confirmed PortProton is already set up at the default path.
if [[ $_PP_SETUP_DONE -eq 1 && $_PP_DEFAULT_PATH -eq 1 ]]; then
    ok "AnomalyLauncher.exe.ppdb: skipping (already set up)"
else
    _ppdb="$STALKER/Anomaly/AnomalyLauncher.exe.ppdb"
    cat > "$_ppdb" << 'PPDB'
#!/usr/bin/env bash
export PW_VULKAN_USE="6"
export PW_USE_WINE_DXGI=0
export PW_WINE_USE="PROTON_LG_10-28"
export PW_PREFIX_NAME="DOTNET"
PPDB
    if [[ ! -f "$_ppdb" ]]; then
        warn "Failed to write AnomalyLauncher.exe.ppdb — create it manually:"
        printf "  Path: %s\n" "$_ppdb" >&2
        printf "  Content:\n" >&2
        printf "    export PW_VULKAN_USE=\"6\"\n" >&2
        printf "    export PW_USE_WINE_DXGI=0\n" >&2
        printf "    export PW_WINE_USE=\"PROTON_LG_10-28\"\n" >&2
        printf "    export PW_PREFIX_NAME=\"DOTNET\"\n" >&2
        enter
    else
        ok "AnomalyLauncher.exe.ppdb written."
    fi
fi

# ── Step 9: First launch — AnomalyLauncher.exe ────────────────────────────────
# The first launch initialises Wine registry entries and shader pre-compilation.
# Must complete before MO2 is set up.
info "First launch: AnomalyLauncher.exe"
printf "\n"
printf "  1. Right-click: %s/Anomaly/AnomalyLauncher.exe\n" "$STALKER"
printf "     → Open with PortProton\n"
printf "  2. GENERAL tab — set the three dropdowns:\n"
printf "       3D API:  DXVK, VKD3D (Newest)\n"
printf "       WINE:    Proton_LG_10-28  (or WineLG11-1 if not available)\n"
printf "       PREFIX:  %s\n" "$DOTNET_PREFIX_NAME"
printf "  3. Click LAUNCH → Press Play → New Game → wait for map to load → close\n"
printf "\n"
printf "  If the game crashes on the first attempt, click Run again (up to 3 times).\n"
printf "\n"
enter

# ── Step 10: Shader cache ─────────────────────────────────────────────────────
# Stale shaders from the vanilla first launch must be cleared before running
# with mods — the modded exes will regenerate them on the next launch.
info "Clearing shader cache..."
if ! rm -rf "$STALKER/Anomaly/appdata/shaders_cache/r4/"; then
    warn "Failed to clear shader cache — delete it manually:"
    printf "  %s/Anomaly/appdata/shaders_cache/r4/\n" "$STALKER" >&2
else
    ok "Shader cache cleared."
fi

# ── Step 10.5: ModOrganizer.exe.ppdb ─────────────────────────────────────────
# Same issue as AnomalyLauncher: PortProton's template ppdb for ModOrganizer
# may set PW_USE_WINE_DXGI=1 or wrong prefix/wine values. Pre-write takes
# priority over the template so the correct settings are always used.
_mo2_ppdb="$STALKER/ZONA/ModOrganizer.exe.ppdb"
cat > "$_mo2_ppdb" << 'PPDB'
#!/usr/bin/env bash
export PW_VULKAN_USE="6"
export PW_USE_WINE_DXGI=0
export PW_WINE_USE="PROTON_LG_10-28"
export PW_PREFIX_NAME="DOTNET"
PPDB
if [[ ! -f "$_mo2_ppdb" ]]; then
    warn "Failed to write ModOrganizer.exe.ppdb — create it manually:"
    printf "  Path: %s\n" "$_mo2_ppdb" >&2
    printf "  Content:\n" >&2
    printf "    export PW_VULKAN_USE=\"6\"\n" >&2
    printf "    export PW_USE_WINE_DXGI=0\n" >&2
    printf "    export PW_WINE_USE=\"PROTON_LG_10-28\"\n" >&2
    printf "    export PW_PREFIX_NAME=\"DOTNET\"\n" >&2
    enter
else
    ok "ModOrganizer.exe.ppdb written."
fi

# ── Step 11: MO2 first launch and setup ───────────────────────────────────────
# MO2 must be opened once through PortProton to initialise its Wine environment
# and complete the portable-instance setup wizard.
info "MO2 setup"
printf "\n"
printf "  1. Right-click: %s/ZONA/ModOrganizer.exe\n" "$STALKER"
printf "     → Open with PortProton\n"
printf "  2. GENERAL tab — same settings as AnomalyLauncher.exe:\n"
printf "       3D API:  DXVK, VKD3D (Newest)\n"
printf "       WINE:    Proton_LG_10-28  (or WineLG11-1)\n"
printf "       PREFIX:  %s\n" "$DOTNET_PREFIX_NAME"
printf "  3. Click LAUNCH — when the setup wizard appears:\n"
printf "       Instance type: Portable\n"
printf "       Game path:     %s/Anomaly\n" "$STALKER"
printf "       Instance path: %s/ZONA\n" "$STALKER"
printf "  4. Accept defaults → decline tutorial → close MO2\n"
printf "\n"
enter
ok "MO2 configured."

# ── Step 12: Verify ───────────────────────────────────────────────────────────
# Launch the game through MO2 with the ZONA profile to confirm end-to-end.
info "Verify ZONA launch (DX11)"
printf "\n"
printf "  1. Open MO2 via PortProton\n"
printf "  2. Top-left profile dropdown → select 'ZONA V1.37 SSS23'\n"
printf "  3. Right pane → select 'Anomaly (DX11)' → Run\n"
printf "  4. New Game → wait for the map to load → close\n"
printf "\n"
enter
ok "STALKER ZONA — verified."

# ── Done ──────────────────────────────────────────────────────────────────────
touch "$STALKER/.install_done"
printf "\n"
ok "Setup complete."
printf "\n"
printf "  To play:  Right-click ZONA/ModOrganizer.exe → Open with PortProton\n"
printf "            Right pane → select renderer → Run\n"
printf "  Re-run:   %s/install.sh\n" "$STALKER"
printf "\n"
