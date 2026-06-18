#!/usr/bin/env bash
# settings-inject.sh — restore STALKER ZONA settings from settings/
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$STALKER/settings"

if [[ ! -d "$SETTINGS" ]]; then
    printf "settings/ not found — run settings-grab.sh first.\n" >&2
    exit 1
fi

info "Injecting user.ltx..."
if [[ -f "$SETTINGS/user.ltx" ]]; then
    cp "$SETTINGS/user.ltx" "$STALKER/Anomaly/appdata/user.ltx"
    ok "settings/user.ltx → Anomaly/appdata/user.ltx"
else
    warn "settings/user.ltx not found — skipping"
fi

info "Injecting MCM settings..."
MCM_DEST=""
for candidate in "$STALKER/ZONA/mods/"*"MCM values"*/gamedata/configs/axr_options.ltx; do
    [[ -f "$candidate" ]] && MCM_DEST="$candidate" && break
done
if [[ -z "$MCM_DEST" ]]; then
    for candidate_dir in "$STALKER/ZONA/mods/"*"MCM values"*/; do
        [[ -d "$candidate_dir" ]] && MCM_DEST="${candidate_dir}gamedata/configs/axr_options.ltx" && break
    done
fi
if [[ -n "$MCM_DEST" ]] && [[ -f "$SETTINGS/mcm/axr_options.ltx" ]]; then
    mkdir -p "$(dirname "$MCM_DEST")"
    cp "$SETTINGS/mcm/axr_options.ltx" "$MCM_DEST"
    ok "settings/mcm/axr_options.ltx → MCM mod"
elif [[ ! -f "$SETTINGS/mcm/axr_options.ltx" ]]; then
    warn "settings/mcm/axr_options.ltx not found — skipping"
else
    warn "MCM values mod not found under ZONA/mods/ — skipping"
fi

info "Injecting MO2 modlists..."
for profile_settings in "$SETTINGS/profiles"/*/; do
    [[ -d "$profile_settings" ]] || continue
    profile_name="$(basename "$profile_settings")"
    dest_dir="$STALKER/ZONA/profiles/$profile_name"
    if [[ ! -d "$dest_dir" ]]; then
        warn "[$profile_name] profile doesn't exist in MO2 — skipping"
        continue
    fi
    if [[ -f "$profile_settings/modlist.txt" ]]; then
        cp "$profile_settings/modlist.txt" "$dest_dir/modlist.txt"
        ok "[$profile_name] modlist.txt restored"
    fi
done

printf "\n"
ok "Injection complete"
printf "\n"
