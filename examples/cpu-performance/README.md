# CPU Aggressive Performance Mode

Systemd service for **maximum permanent performance** on the Legion Go (AMD BC-250 / Cyan Skillfish APU).

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

## What it does

| Optimization | Detail | Effect |
|---|---|---|
| `scaling_governor=performance` | All 12 cores fixed at max | Predictable latency |
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

## Notes

- C-states disabled: **C2** (index 2, 350µs) and **C3** (index 3, 400µs) — confirmed on BC-250 via `cpupower idle-info`
- Only sysctl parameters **confirmed present** on kernel Neptune/SteamOS are used
- Service auto-restores defaults on stop: `sudo systemctl stop cpu-performance.service`

## Quick restore

```bash
sudo systemctl stop cpu-performance.service
# → automatically returns to schedutil + system defaults
```
