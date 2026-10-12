#!/bin/sh
set -eu
export LC_ALL=C
cd "$HOME/arm64_simd"
echo '=== Host ==='
date -u
uname -a
cat /etc/os-release
lscpu
free -h
echo '=== CPU operating settings (point-in-time samples) ==='
for setting in /sys/devices/system/cpu/online /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq; do
    if [ -r "$setting" ]; then
        echo "$setting"
        cat "$setting"
    fi
done
echo '=== GPU ==='
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi || true
else
    echo 'nvidia-smi unavailable'
fi
echo '=== Deployed assembly ==='
sha256sum ARM64-SIMD.dll
echo '=== Benchmarks ==='
run=1
while [ "$run" -le "$1" ]; do
    echo "=== Run $run/$1 ==="
    timeout 180 ./ARM64-SIMD --length="$2" --iterations="$3" --warmup=1
    run=$((run + 1))
done
