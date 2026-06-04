# CPU Aggressive Performance Mode

Systemd service for **maximum permanent performance** on the AMD BC-250 (Cyan Skillfish APU).

> ⚠️ **Service runs as root** — always use `sudo systemctl`.

## Installation

```bash
# Download directly from repo
sudo curl -o /etc/systemd/system/cpu-performance.service \
  https://raw.githubusercontent.com/mrsasy89/steamos-bc250-restore/main/examples/cpu-performance/cpu-performance.service

sudo systemctl daemon-reload
sudo systemctl enable --now cpu-performance.service

# Verify
systemctl status cpu-performance.service
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# → performance ✅
```

## amdgpu lockup_timeout (GPU ring crash fix)

On SteamOS / kernel Neptune, `lockup_timeout` is **read-only at runtime** —
the sysfs file `/sys/module/amdgpu/parameters/lockup_timeout` returns
`Permission denied` even with sudo.

The only way to change it is via **kernel module parameter at boot**:

```bash
# Step 1: create modprobe config
echo "options amdgpu lockup_timeout=2000" | sudo tee /etc/modprobe.d/amdgpu-bc250.conf

# Step 2: rebuild initramfs (requires writable /boot)
sudo steamos-readonly disable
sudo mkinitcpio -p linux-neptune-618
sudo steamos-readonly enable

# Step 3: reboot
sudo reboot

# Step 4: verify after reboot
cat /sys/module/amdgpu/parameters/lockup_timeout
# → 2000 ✅ (was 5000 on stock SteamOS Neptune)
```

> ⚠️ Always run `sudo steamos-readonly enable` after rebuilding initramfs.
> The filesystem must be read-only for SteamOS updates to work correctly.

## What it does

| Optimization | Detail | Effect |
|---|---|---|
| `scaling_governor=performance` | All cores fixed at max | Predictable latency |
| `scaling_min_freq = max_freq` | No downscaling | Stable FPS |
| AMD Core Performance Boost | Keeps boost active | Max single-thread burst |
| C2/C3 disabled | Confirmed states on BC-250 (350-400µs latency) | No wakeup penalty |
| `sched_autogroup_enabled=0` | Disables auto task grouping | Lower interactive latency |
| `sched_rt_runtime_us=980000` | Max RT window | Less scheduler throttling |
| `sched_util_clamp_min=1024` | Forces full utilization hint | No frequency scaling on low load |
| IRQ pinning on core 0 | Cores 1-11 free for gaming | Less interrupt overhead |
| Transparent HugePages=always | 2MB pages | Fewer TLB misses |
| `vm.swappiness=10` | Prefers RAM over swap | Less I/O latency |
| `vm.compaction_proactiveness=0` | Disables proactive compaction | Eliminates stutter |
| `kernel.nmi_watchdog=0` | Disables NMI watchdog | Fewer spurious interrupts |
| `lockup_timeout=2000` | Via modprobe.d (see above) | Faster GPU ring recovery |

## Notes

- C-states disabled: **C2** (index 2, 350µs) and **C3** (index 3, 400µs) — confirmed on BC-250 via `cpupower idle-info`
- Only sysctl parameters **confirmed present** on kernel Neptune/SteamOS are used
- Service auto-restores defaults on stop: `sudo systemctl stop cpu-performance.service`
- `lockup_timeout` is **not** managed by this service — it requires modprobe.d + initramfs rebuild (see above)

## Quick restore

```bash
sudo systemctl stop cpu-performance.service
# → automatically returns to schedutil + system defaults
```
