#!/usr/bin/env bash
# settings-grab.sh — snapshot current STALKER ZONA settings into settings/
#
# Rotation: only two slots are kept.
#   settings/         — current (most recent grab)
#   settings-backup/  — previous grab
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$STALKER/settings"
BACKUP="$STALKER/settings-backup"

if [[ -d "$SETTINGS" ]]; then
    info "Rotating: settings/ → settings-backup/..."
    rm -rf "$BACKUP"
    mv "$SETTINGS" "$BACKUP"
    ok "Previous settings saved → settings-backup/"
fi

mkdir -p "$SETTINGS/mcm" "$SETTINGS/profiles"

# ── Game settings ─────────────────────────────────────────────────────────────
info "Grabbing user.ltx..."
if [[ -f "$STALKER/Anomaly/appdata/user.ltx" ]]; then
    cp "$STALKER/Anomaly/appdata/user.ltx" "$SETTINGS/user.ltx"
    ok "user.ltx → settings/user.ltx"
else
    warn "user.ltx not found — launch the game once first"
fi

info "Grabbing MCM settings..."
MCM_SRC=""
for _c in "$STALKER/ZONA/mods/"*"MCM values"*/gamedata/configs/axr_options.ltx; do
    [[ -f "$_c" ]] && MCM_SRC="$_c" && break
done
if [[ -n "$MCM_SRC" ]]; then
    cp "$MCM_SRC" "$SETTINGS/mcm/axr_options.ltx"
    ok "axr_options.ltx → settings/mcm/axr_options.ltx"
else
    warn "MCM axr_options.ltx not found under ZONA/mods/ — skipping"
fi

# ── PortProton / launch config ────────────────────────────────────────────────
info "Grabbing ModOrganizer.exe.ppdb..."
if [[ -f "$STALKER/ZONA/ModOrganizer.exe.ppdb" ]]; then
    cp "$STALKER/ZONA/ModOrganizer.exe.ppdb" "$SETTINGS/ModOrganizer.exe.ppdb"
    ok "ModOrganizer.exe.ppdb → settings/ModOrganizer.exe.ppdb"
else
    warn "ModOrganizer.exe.ppdb not found — skipping"
fi

info "Grabbing commandline.txt..."
if [[ -f "$STALKER/Anomaly/commandline.txt" ]]; then
    cp "$STALKER/Anomaly/commandline.txt" "$SETTINGS/commandline.txt"
    ok "commandline.txt → settings/commandline.txt"
else
    warn "commandline.txt not found — skipping"
fi

info "Grabbing dxvk.conf..."
if [[ -f "$STALKER/Anomaly/dxvk.conf" ]]; then
    cp "$STALKER/Anomaly/dxvk.conf" "$SETTINGS/dxvk.conf"
    ok "dxvk.conf → settings/dxvk.conf"
else
    warn "dxvk.conf not found — skipping"
fi

# ── MO2 modlists ──────────────────────────────────────────────────────────────
info "Grabbing MO2 modlists..."
for _pdir in "$STALKER/ZONA/profiles"/*/; do
    [[ -d "$_pdir" ]] || continue
    _pname="$(basename "$_pdir")"
    if [[ -f "$_pdir/modlist.txt" ]]; then
        mkdir -p "$SETTINGS/profiles/$_pname"
        cp "$_pdir/modlist.txt" "$SETTINGS/profiles/$_pname/modlist.txt"
        ok "[$_pname] modlist.txt → settings/profiles/$_pname/"
    else
        warn "[$_pname] no modlist.txt — skipping"
    fi
done

printf "\n"
ok "Snapshot complete → $SETTINGS"
[[ -d "$BACKUP" ]] && printf "  Previous settings preserved → settings-backup/\n"
printf "\n"
