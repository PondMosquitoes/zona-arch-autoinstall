# STALKER ZONA — Arch Linux

ZONA v1.37 SSS23 modpack via Mod Organizer 2 under PortProton.

---

## Dependencies

| Dependency | Purpose | Source |
|---|---|---|
| `python` | Python venv for gdrive-ripper and gamma-launcher | pacman |
| `git` | Clone gamma-launcher | pacman |
| `libunrar` | UnRAR support for Anomaly archive extraction | pacman |
| `curl` | Download MO2 and modded executables | pacman |
| `p7zip` | Extract `.7z` and `.zip` archives | pacman |
| `winetricks` | Install DirectX / .NET components into Wine prefix | pacman |
| `xorg-xrandr` | Native display resolution detection (perf.sh) | pacman |
| `gamemode` | CPU performance mode during gameplay (perf.sh) | pacman |
| `nvidia-utils` | GPU detection via `nvidia-smi` — NVIDIA only, optional | pacman |
| `nvidia-settings` | GPU power management — NVIDIA only, optional | pacman |
| `portproton` | Wine/Proton frontend for running Windows executables | AUR |
| `yay` / `paru` | AUR helper required to install portproton | manual |
| `gdrive-ripper` | Google Drive downloader for the ZONA modpack archive | pip (auto) |
| `gamma-launcher` | Automated Anomaly 1.5.3 installer | pip (auto) |

`gdrive-ripper` and `gamma-launcher` are installed automatically by `install.sh`. Everything else must be present first.

```bash
# pacman deps
sudo pacman -S --needed python git libunrar curl p7zip winetricks xorg-xrandr gamemode

# portproton (AUR — requires yay or paru)
yay -S --needed portproton
```

---

## Install

```bash
./autoinstall.sh
```

Three prompted steps: ZONA install → performance tuning → sudoers. Each is skippable. Re-run any time — completed steps are detected and skipped.

The ZONA download link changes with each release. Get it from `#install-zona` in the ZONA Discord. `links.txt` has the last known link if you don't have a Discord account.

### Google Drive failure modes

If the ZONA download fails, the script will ask which of the following occurred:

| Cause | Fix |
|---|---|
| **No cookies** | Open a browser, sign in to Google, then run `gdrive-ripper --get-cookies` in the activated venv |
| **Bad/expired cookies** | Sign out and back in to Google, re-run `gdrive-ripper --get-cookies` |
| **Link superseded** | Get the new link from `#install-zona` (or check `links.txt`) and paste it when prompted |

---

## Scripts

| Script | Purpose |
|---|---|
| `autoinstall.sh` | Start here — orchestrates all steps |
| `install.sh` | Downloads Anomaly + ZONA, sets up MO2, PortProton, winetricks |
| `perf.sh` | CPU/GPU tuning, DXVK config, A-Life patch, AVX binary selection |
| `perf-root.sh` | Privileged helper called by perf.sh — do not run directly |
| `settings-grab.sh` | Snapshot current game settings → `settings/` |
| `settings-inject.sh` | Restore `settings/` → game |

---

## Performance tweaks

`perf.sh` is **untested** — ZONA runs fine without it. Run it only if you have a specific reason to tune CPU governor, DXVK settings, or the A-Life simulation radius. The AVX binary selection runs unconditionally and is safe.
