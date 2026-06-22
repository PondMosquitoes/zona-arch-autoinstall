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
    warn "settings/ not found — run settings-grab.sh first."
    exit 1
fi

# ── Resolve dynamic destinations ──────────────────────────────────────────────
MCM_DEST=""
for _c in "$STALKER/ZONA/mods/"*"MCM values"*/gamedata/configs/axr_options.ltx; do
    [[ -f "$_c" ]] && MCM_DEST="$_c" && break
done
if [[ -z "$MCM_DEST" ]]; then
    for _cd in "$STALKER/ZONA/mods/"*"MCM values"*/; do
        [[ -d "$_cd" ]] && MCM_DEST="${_cd}gamedata/configs/axr_options.ltx" && break
    done
fi

# ── Build item list (only files present in settings/) ─────────────────────────
_LABELS=()
_SRCS=()
_DESTS=()
_TYPES=()

_maybe_add() {
    [[ -f "$2" ]] || return 0
    _LABELS+=("$1"); _SRCS+=("$2"); _DESTS+=("$3"); _TYPES+=("file")
}

_maybe_add "user.ltx"              "$SETTINGS/user.ltx"              "$STALKER/Anomaly/appdata/user.ltx"
_maybe_add "axr_options.ltx (MCM)" "$SETTINGS/mcm/axr_options.ltx"   "${MCM_DEST:-}"
_maybe_add "ModOrganizer.exe.ppdb" "$SETTINGS/ModOrganizer.exe.ppdb"  "$STALKER/ZONA/ModOrganizer.exe.ppdb"
_maybe_add "commandline.txt"       "$SETTINGS/commandline.txt"        "$STALKER/Anomaly/commandline.txt"
_maybe_add "dxvk.conf"             "$SETTINGS/dxvk.conf"              "$STALKER/Anomaly/dxvk.conf"

if compgen -G "$SETTINGS/profiles/*/modlist.txt" > /dev/null 2>&1; then
    _LABELS+=("MO2 modlists (all profiles)")
    _SRCS+=(""); _DESTS+=(""); _TYPES+=("modlists")
fi

if [[ ${#_LABELS[@]} -eq 0 ]]; then
    warn "No settings files found in settings/ — run settings-grab.sh first."
    exit 1
fi

# ── Menu ──────────────────────────────────────────────────────────────────────
info "Select files to inject:"
printf "\n"
printf "   1) Inject ALL\n"
for (( _i=0; _i<${#_LABELS[@]}; _i++ )); do
    printf "  %2d) %s\n" "$(( _i + 2 ))" "${_LABELS[$_i]}"
done
printf "\n"
printf "  Enter numbers separated by commas (e.g. 1 for all, or 3,5 for specific):\n"
printf "${Y}  Choice:${N} " >&2
read -r _raw || _raw="1"

# ── Parse selection ───────────────────────────────────────────────────────────
_SEL=()
IFS=',' read -ra _parts <<< "${_raw// /}"
for _p in "${_parts[@]}"; do
    [[ "$_p" =~ ^[0-9]+$ ]] || continue
    if [[ "$_p" -eq 1 ]]; then
        _SEL=()
        for (( _j=0; _j<${#_LABELS[@]}; _j++ )); do _SEL+=("$_j"); done
        break
    else
        _idx=$(( _p - 2 ))
        if (( _idx >= 0 && _idx < ${#_LABELS[@]} )); then
            _SEL+=("$_idx")
        else
            warn "No item $_p — skipping"
        fi
    fi
done

# Deduplicate preserving order
_SEL=($(printf '%s\n' "${_SEL[@]+"${_SEL[@]}"}" | sort -un))

if [[ ${#_SEL[@]} -eq 0 ]]; then
    warn "Nothing selected."
    exit 0
fi

# ── Inject ────────────────────────────────────────────────────────────────────
printf "\n"
for _idx in "${_SEL[@]}"; do
    _label="${_LABELS[$_idx]}"
    _src="${_SRCS[$_idx]}"
    _dest="${_DESTS[$_idx]}"
    _type="${_TYPES[$_idx]}"

    if [[ "$_type" == "modlists" ]]; then
        for _pdir in "$SETTINGS/profiles"/*/; do
            [[ -d "$_pdir" ]] || continue
            _pname="$(basename "$_pdir")"
            _pdest="$STALKER/ZONA/profiles/$_pname"
            if [[ ! -d "$_pdest" ]]; then
                warn "[$_pname] profile not found in MO2 — skipping"
                continue
            fi
            if [[ -f "$_pdir/modlist.txt" ]]; then
                cp "$_pdir/modlist.txt" "$_pdest/modlist.txt"
                ok "[$_pname] modlist.txt → ZONA/profiles/$_pname/"
            fi
        done
    elif [[ -z "$_dest" ]]; then
        warn "$_label: destination not found — skipping"
    else
        mkdir -p "$(dirname "$_dest")"
        cp "$_src" "$_dest"
        ok "$_label injected"
    fi
done

printf "\n"
ok "Injection complete."
printf "\n"
