#!/usr/bin/env bash
# rmsss.sh — Create a new MO2 profile with SSS removed.
# Methodology: nuclear first pass — disable every mod whose name contains "SSS".
# The new profile is "Zona - no SSS" copied from the currently selected profile.
# This script never touches the source profile or ModOrganizer.ini.
set -euo pipefail

B='\033[1;34m' G='\033[1;32m' Y='\033[1;33m' R='\033[1;31m' N='\033[0m'
info() { printf "\n${B}[*]${N} %s\n" "$*" >&2; }
ok()   { printf "${G}[✓]${N} %s\n" "$*" >&2; }
warn() { printf "${Y}[!]${N} %s\n" "$*" >&2; }
die()  { printf "${R}[✗]${N} %s\n" "$*" >&2; exit 1; }

STALKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MO2_DIR="$STALKER/ZONA"
PROFILES_DIR="$MO2_DIR/profiles"
MO2_INI="$MO2_DIR/ModOrganizer.ini"
NEW_PROFILE="Zona - no SSS"

# ── Prerequisites ────────────────────────────────────────────────────────────

[[ -f "$MO2_DIR/ModOrganizer.exe" ]] || \
    die "ZONA not found at $MO2_DIR — run install.sh first."
[[ -f "$MO2_INI" ]] || \
    die "ModOrganizer.ini not found — launch MO2 at least once via PortProton first."
[[ -d "$PROFILES_DIR" ]] || \
    die "Profiles directory not found: $PROFILES_DIR"

# ── Detect source profile ─────────────────────────────────────────────────

_src_profile="$(grep '^selected_profile=' "$MO2_INI" \
    | sed 's/selected_profile=@ByteArray(\(.*\))/\1/' || true)"

if [[ -z "$_src_profile" ]]; then
    warn "Could not read selected_profile from ModOrganizer.ini."
    printf "  Available profiles:\n" >&2
    ls "$PROFILES_DIR" | sed 's/^/    /' >&2
    printf "\n${Y}  Enter the profile name to copy from:${N} " >&2
    read -r _src_profile || _src_profile=""
    [[ -n "$_src_profile" ]] || die "No profile specified."
fi

_src_dir="$PROFILES_DIR/$_src_profile"
[[ -d "$_src_dir" ]] || die "Source profile directory not found: $_src_dir"

info "Source profile: $_src_profile"

# ── Create new profile ────────────────────────────────────────────────────

_new_dir="$PROFILES_DIR/$NEW_PROFILE"

if [[ -d "$_new_dir" ]]; then
    warn "Profile '$NEW_PROFILE' already exists."
    printf "  Overwrite it? [y/N]: " >&2
    read -r _ow || _ow=""
    if [[ ! "${_ow:-N}" =~ ^[Yy]$ ]]; then
        warn "Aborted — no changes made."
        exit 0
    fi
    rm -rf "$_new_dir"
fi

cp -r "$_src_dir" "$_new_dir"
ok "Created profile '$NEW_PROFILE' from '$_src_profile'"

# ── Disable SSS mods in modlist.txt ──────────────────────────────────────

_modlist="$_new_dir/modlist.txt"
[[ -f "$_modlist" ]] || die "modlist.txt not found in new profile: $_modlist"

# Collect enabled SSS mods before editing (handles CRLF: strip trailing \r for display)
mapfile -t _to_disable < <(grep '^+.*SSS' "$_modlist" 2>/dev/null \
    | sed 's/\r//' || true)

if [[ ${#_to_disable[@]} -eq 0 ]]; then
    warn "No enabled SSS mods found in modlist.txt — nothing to disable."
    printf "  Profile '%s' was still created from '%s'.\n" "$NEW_PROFILE" "$_src_profile" >&2
    exit 0
fi

# Flip +<any SSS mod> → -<same>   (^+ is literal + in BRE; CRLF safe)
sed -i 's/^+\(.*SSS.*\)$/-\1/' "$_modlist"

ok "Disabled ${#_to_disable[@]} SSS mod(s):"
for _m in "${_to_disable[@]}"; do
    printf "    - %s\n" "${_m#+}" >&2
done

# ── Next steps ────────────────────────────────────────────────────────────

printf "\n"
info "Done. To use the new profile:"
printf "  1. Close MO2 if it is open\n"
printf "  2. Open MO2 via PortProton\n"
printf "  3. Top-left profile dropdown → select '%s'\n" "$NEW_PROFILE"
printf "  4. Right pane → select 'Anomaly (DX11)' → Run\n"
printf "  5. Test the game — report crashes or visual issues\n"
printf "\n"
warn "FPS cap / VSYNC: set these in-game or via dxvk.conf once the game is stable."
printf "\n"
