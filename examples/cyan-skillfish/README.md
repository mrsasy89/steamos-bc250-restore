# cyan-skillfish-governor-smu — Configuration Profiles

Configuration for [cyan-skillfish-governor-smu](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu),
the GPU governor via SMU for the BC-250 (Cyan Skillfish APU).

> ⚠️ **Do NOT use** `power_dpm_force_performance_level` or `pp_dpm_sclk` while
> the governor is active — it controls the GPU directly via SMU and standard
> DPM sysfs files are ignored or cause conflicts.

> ⚠️ **Service runs as root** — always use `sudo systemctl` (NOT `systemctl --user`):
> ```bash
> sudo systemctl restart cyan-skillfish-governor-smu
> sudo systemctl status cyan-skillfish-governor-smu
> ```

## Available files

| File | Description |
|---|---|
| `config.toml.aggressive` | Aggressive profile v2 — fast ramp, delayed downclock, min 1800MHz floor |

## Installation

```bash
# Find the active config path
sudo systemctl cat cyan-skillfish-governor-smu | grep -i config

# Copy the aggressive profile
sudo cp config.toml.aggressive /etc/cyan-skillfish-governor/config.toml
# or wherever the service expects it

# Restart the governor
sudo systemctl restart cyan-skillfish-governor-smu
sudo systemctl status cyan-skillfish-governor-smu
```

## Changes from default (v2)

| Parameter | Default | Aggressive v2 | Effect |
|---|---|---|---|
| `burst` ramp rate | 15 | **25** | Reaches peak frequency faster |
| `normal` ramp rate | 2 | **4** | More reactive upscaling |
| `burst-samples` | 10 | **5** | Detects burst load in half the time |
| `down-events` | 20 | **60** | Resists downclocking much longer |
| `upper` load target | 0.90 | **0.75** | Scales up earlier |
| `lower` load target | 0.75 | **0.55** | Tolerates lower load before downclocking |
| `min` frequency | 1000 MHz | **1800 MHz** | Never drops below 1800MHz — eliminates FPS dips |

## Full BC-250 optimization stack

| # | Component | Status | Notes |
|---|---|---|---|
| 1 | `bc250-acpi-fix` | ✅ Applied | ACPI table fix |
| 2 | `cpu-performance.service` | ✅ Active | governor + C-states + scheduler |
| 3 | `cyan-skillfish-governor-smu` | ✅ Active | GPU via SMU, this config |
| 4 | `bc250-smu-oc` | ✅ Active | CPU OC: 4000MHz @ 1256mV (scale -27) |
| 5 | 40 CU unlock | ⏳ Next step | — |

## References

- [amd-bc250-docs](https://github.com/elektricM/amd-bc250-docs)
- [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor)
- [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc/)
- [bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
