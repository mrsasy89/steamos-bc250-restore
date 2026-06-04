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

## Available profiles

| File | When to use |
|---|---|
| `config.toml.aggressive` | Default — daily use, min 1800 MHz floor |
| `config.toml.gaming` | RE Engine / Vulkan-heavy games — GPU fixed at 2000 MHz, no ramping |

## Installation

```bash
# Find the active config path
sudo systemctl cat cyan-skillfish-governor-smu | grep -i config

# Apply aggressive profile (default)
sudo cp config.toml.aggressive /etc/cyan-skillfish-governor-smu/config.toml

# Apply gaming profile (RE Engine, Vulkan heavy)
sudo cp config.toml.gaming /etc/cyan-skillfish-governor-smu/config.toml

sudo systemctl restart cyan-skillfish-governor-smu
```

## Profile comparison

| Parameter | aggressive v2 | gaming |
|---|---|---|
| `min` frequency | 1800 MHz | **2000 MHz** — fixed, no ramping |
| `max` frequency | 2000 MHz | 2000 MHz |
| `down-events` | 60 | **999** — never downclocks |
| `burst` ramp | 25 | 25 |
| `upper` load target | 0.75 | 0.75 |
| `lower` load target | 0.55 | 0.55 |
| Use case | General gaming | RE Engine, Vulkan-heavy titles |

## GPU ring timeout fix

RE Engine and other Vulkan-aggressive titles can trigger a GPU ring timeout (`gfx_0.0.0 timeout`)
causing a green screen + gamescope restart. Two mitigations are applied:

1. **`config.toml.gaming`** — GPU fixed at 2000 MHz eliminates frequency transitions during burst draw calls
2. **`lockup_timeout = 2000ms`** — set in `cpu-performance.service`, reduces recovery time from 10s to 2s

```bash
# Verify lockup_timeout is active
cat /sys/module/amdgpu/parameters/lockup_timeout
# → 2000 ✅
```

## Full BC-250 optimization stack

| # | Component | Status | Notes |
|---|---|---|---|
| 1 | `bc250-acpi-fix` | ✅ Applied | ACPI table fix |
| 2 | `cpu-performance.service` | ✅ Active | governor + C-states + scheduler + lockup_timeout |
| 3 | `cyan-skillfish-governor-smu` | ✅ Active | GPU via SMU |
| 4 | `bc250-smu-oc` | ✅ Active | CPU OC: 4000MHz @ 1256mV (scale -27) |
| 5 | 40 CU unlock | ⏳ Next step | — |

## References

- [amd-bc250-docs](https://github.com/elektricM/amd-bc250-docs)
- [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor)
- [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc/)
- [bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
