#!/usr/bin/env bash
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' R='\033[1;31m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }
die()  { printf "${R}[✗]${N} %s\n" "$*" >&2; exit 1; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_installed() {
    [[ -f "$STALKER/Anomaly/AnomalyLauncher.exe" ]] && \
    [[ -f "$STALKER/ZONA/ModOrganizer.exe" ]]
}

_sudoers_ok() {
    [[ -f /etc/sudoers.d/stalker-perf ]]
}

_first_launch_gate() {
    local user_ltx="$STALKER/Anomaly/appdata/user.ltx"
    [[ -f "$user_ltx" ]] && return 0

    warn "perf.sh tunes Anomaly/appdata/user.ltx, which doesn't exist yet."
    printf "  Launch Anomaly once before continuing:\n"
    printf "  right-click AnomalyLauncher.exe → Open with PortProton, click Play,\n"
    printf "  reach the main menu or start a new game, then close it.\n\n"
    read -rp "[Press Enter once you've done this, or 's' to skip perf.sh] " _gate
    [[ "${_gate:-}" =~ ^[Ss]$ ]] && return 1

    if [[ -f "$user_ltx" ]]; then
        ok "user.ltx found."
        return 0
    else
        warn "user.ltx still not found — skipping perf.sh. Re-run this menu after launching Anomaly."
        return 1
    fi
}

_portproton_gate() {
    local pp_root="$HOME/PortProton"
    local dotnet_prefix="$pp_root/data/prefixes/DOTNET"
    local need_setup=0 need_prefix=0

    [[ -f "$pp_root/data/scripts/start.sh" ]] || need_setup=1
    [[ -d "$dotnet_prefix" ]] || need_prefix=1

    if (( need_setup || need_prefix )); then
        if (( need_setup )); then
            warn "PortProton hasn't been set up yet."
            printf "  Launching PortProton's first-time setup now. A dialog will ask for\n"
            printf "  an install path — choose the \033[1mdefault\033[0m (%s), NOT 'Other Path...'.\n" "$pp_root"
            printf "  install.sh and perf.sh both assume PortProton lives there.\n\n"
        else
            warn "The 'DOTNET' wine prefix doesn't exist yet (required for Anomaly/ZONA)."
        fi
        if (( need_prefix )); then
            printf "  Once the PortProton window opens (tabs: AUTOINSTALLS | WINE SETTINGS |\n"
            printf "  PORTPROTON SETTINGS | INSTALLED):\n"
            printf "    1. Click \033[1mWINE SETTINGS\033[0m.\n"
            printf "    2. Create a new prefix named exactly \033[1mDOTNET\033[0m (this name is\n"
            printf "       hardcoded by install.sh and perf.sh).\n"
            printf "    3. Select it as the active prefix.\n"
            printf "    4. Then close PortProton.\n\n"
        fi
        read -rp "[Press Enter to launch PortProton]" _
        portproton || warn "portproton exited with an error."

        if [[ ! -f "$pp_root/data/scripts/start.sh" ]]; then
            die "PortProton still not found at $pp_root — re-run autoinstall.sh once setup is complete."
        fi
        (( need_setup )) && ok "PortProton initialized at $pp_root"

        if [[ ! -d "$dotnet_prefix" ]]; then
            die "DOTNET prefix still not found at $dotnet_prefix — re-run autoinstall.sh once it's created."
        fi
        (( need_prefix )) && ok "DOTNET prefix found at $dotnet_prefix"
    fi
}

_setup_sudoers() {
    if _sudoers_ok; then ok "sudoers: already configured"; return; fi
    info "Configuring sudoers for passwordless perf-root.sh..."
    printf '%s\n' "$USER ALL=(root) NOPASSWD: $STALKER/perf-root.sh" \
        | sudo tee /etc/sudoers.d/stalker-perf > /dev/null
    sudo chmod 440 /etc/sudoers.d/stalker-perf
    ok "sudoers: /etc/sudoers.d/stalker-perf written"
}

_banner() {
    printf "\n\033[1m══════════════════════════════════════════\033[0m\n"
    printf "\033[1m  STALKER ZONA — Setup\033[0m\n"
    printf "\033[1m══════════════════════════════════════════\033[0m\n\n"
}

_full_install() {
    printf "\n\033[1mStep 1/3 — ZONA Install\033[0m\n"
    printf "  Downloads Anomaly + ZONA (~100 GB). Installs system packages,\n"
    printf "  sets up PortProton, MO2, and injects Wine/D3D runtimes.\n"
    printf "  This is the long step — leave it running.\n\n"
    read -rp "Run install.sh? [Y/n]: " _p1
    if [[ "${_p1:-Y}" =~ ^[Yy]$ ]]; then
        bash "$STALKER/install.sh"
    else
        warn "Skipped — run ./install.sh manually to install ZONA."
    fi

    printf "\n\033[1mStep 2/3 — Performance Configuration (untested)\033[0m\n"
    printf "  Applies CPU/GPU tuning, configures DXVK, optionally patches A-Life\n"
    printf "  simulation radius, and deploys the correct engine binary for your CPU.\n"
    printf "  ZONA runs fine without this — skip unless you have a specific reason.\n\n"
    read -rp "Run perf.sh? [Y/n]: " _p2
    if [[ "${_p2:-Y}" =~ ^[Yy]$ ]]; then
        _first_launch_gate && bash "$STALKER/perf.sh"
    else
        warn "Skipped — run ./perf.sh manually before playing, or use stock ZONA."
    fi

    printf "\n\033[1mStep 3/3 — Sudoers Setup\033[0m\n"
    printf "  Allows perf.sh to set the CPU performance governor and NVIDIA\n"
    printf "  persistence mode without prompting for a password on every launch.\n\n"
    read -rp "Configure sudoers? [Y/n]: " _p3
    if [[ "${_p3:-Y}" =~ ^[Yy]$ ]]; then
        _setup_sudoers
    else
        warn "Skipped — sudo password required each launch for perf-root.sh."
    fi

    printf "\n"
    ok "All done."
    printf "  → Launch ZONA: right-click ZONA/ModOrganizer.exe → Open with PortProton\n\n"

    read -rp "Open menu? [Y/n]: " _m
    [[ "${_m:-Y}" =~ ^[Yy]$ ]] && _menu
}

_menu() {
    while true; do
        printf "\n\033[1m──────────────────────────────────────────\033[0m\n"
        true
        _sudoers_ok || warn "sudoers not configured — option 6 recommended."
        printf "  1) Update / reinstall ZONA\n"
        printf "  2) Performance steps (untested — skip if ZONA runs fine)\n"
        printf "  3) Inject saved settings\n"
        printf "  4) Grab current settings snapshot\n"
        printf "  5) Set up sudoers\n"
        printf "  6) Exit\n\n"
        read -rp "Choice [1-6]: " _c
        printf "\n"
        case "${_c:-6}" in
            1) bash "$STALKER/install.sh" ;;
            2) _first_launch_gate && bash "$STALKER/perf.sh" ;;
            3) bash "$STALKER/settings-inject.sh" || warn "settings-inject.sh exited with an error." ;;
            4) bash "$STALKER/settings-grab.sh"   || warn "settings-grab.sh exited with an error." ;;
            5) _setup_sudoers ;;
            6) exit 0 ;;
            *) warn "Invalid choice." ;;
        esac
        printf "\n"
        read -rp "Press Enter to return to menu..." _
    done
}

_banner
_portproton_gate
if _installed; then
    _menu
else
    printf "No ZONA install detected. Each step will ask before running.\n\n"
    _full_install
fi
