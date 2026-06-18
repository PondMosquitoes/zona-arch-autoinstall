#!/usr/bin/env bash
# perf-root.sh — privileged STALKER performance tweaks (called via sudo from perf.sh)
set -euo pipefail

HAS_EPP=0
[[ -f /sys/devices/system/cpu/cpufreq/policy0/energy_performance_preference ]] && HAS_EPP=1

for p in /sys/devices/system/cpu/cpufreq/policy*/; do
    printf performance > "$p/scaling_governor"
    [[ $HAS_EPP -eq 1 ]] && printf performance > "$p/energy_performance_preference"
done

if command -v nvidia-smi &>/dev/null && nvidia-smi -L &>/dev/null 2>&1; then
    nvidia-smi -pm 1 > /dev/null
fi
