# steamos-bc250-restore

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Post-update restoration and **full performance optimization** stack for **SteamOS** on **AMD BC-250 / Cyan Skillfish APU**.

After every SteamOS update, services like `bc250-acpi-fix`, `bc250-smu-oc` and `cyan-skillfish-governor-smu` may be removed or stop working. This repo contains the restore scripts, all tested configuration profiles, and the complete documentation of the optimization stack.

> ⚠️ **Hardware warning:** The BC-250 is a custom AMD SoC. Incorrect overclock or voltage settings can **permanently brick the hardware**. Always follow the step-by-step guide and never exceed the documented voltage limits.

---

## Tested Results

| Metric | Value |
|---|---|
| CPU frequency | **4000 MHz** (stock ~3493 MHz) |
| CPU voltage | **1256 mV @ scale -27** |
| GPU frequency | **1800–2000 MHz** (floor 1800 MHz) |
| Temperature under load | **< 70°C** |
| Active cores | 6 physical (12 threads) |
| C-states disabled | C2 (350µs) + C3 (400µs) |
| Stability | ✅ Confirmed stable in-game |

---

## Repository Structure

```
steamos-bc250-restore/
├── restore-bc250-steamos.sh          # Full restore after SteamOS update
├── post-update-check.sh              # Quick service status check
├── examples/
│   ├── acpi/                          # ACPI P-States & C-States override
│   │   ├── README.md
│   │   ├── SSDT-PST.dsl               # GPU P-States source
│   │   └── SSDT-CST.dsl               # GPU C-States source
│   ├── cpu-performance/               # CPU aggressive performance service
│   │   ├── README.md
│   │   └── cpu-performance.service
│   ├── cyan-skillfish/                # GPU governor profiles
│   │   ├── README.md
│   │   └── config.toml.aggressive     # Tested aggressive profile v2
│   ├── config.toml.example            # cyan-skillfish default reference
│   └── overclock.conf.example         # bc250_smu_oc reference
└── LICENSE
```

---

## Full Optimization Stack

Apply in this exact order.

### Step 1 — bc250-acpi-fix

Fixes the ACPI tables required for correct hardware initialization.

```bash
cd ~
git clone https://github.com/bc250-collective/bc250-acpi-fix
cd bc250-acpi-fix
# Follow the upstream README
```

Verify after reboot:
```bash
dmesg | grep "Table Upgrade"
# → SSDT-CST [HACK P_CST3] ✅
# → SSDT-PST [HACK PSTATES] ✅

cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# → 3200000 2550000 2325000 1960000 1820000 1600000 1271000 800000 ✅
```

---

### Step 2 — cpu-performance.service

Systemd service (runs as **root**) that locks all 12 cores at maximum frequency and disables high-latency idle states.

```bash
sudo curl -o /etc/systemd/system/cpu-performance.service \
  https://raw.githubusercontent.com/mrsasy89/steamos-bc250-restore/main/examples/cpu-performance/cpu-performance.service

sudo systemctl daemon-reload
sudo systemctl enable --now cpu-performance.service
```

What it does:

| Optimization | Detail |
|---|---|
| `scaling_governor=performance` | All cores fixed at max, no downscaling |
| `scaling_min_freq = max_freq` | Prevents any frequency drop |
| AMD Core Performance Boost | Kept active |
| C2 + C3 disabled | Eliminates 350–400µs wakeup penalty (confirmed states on BC-250) |
| `sched_autogroup_enabled=0` | Lower interactive latency |
| `sched_rt_runtime_us=980000` | Less scheduler throttling |
| `sched_util_clamp_min=1024` | Forces full utilization hint |
| IRQ pinning on core 0 | Cores 1–11 free for gaming |
| THP=always | Fewer TLB misses |
| `vm.swappiness=10` | Prefers RAM over swap |
| `vm.compaction_proactiveness=0` | Eliminates memory compaction stutter |
| `kernel.nmi_watchdog=0` | Fewer spurious interrupts |

Verify:
```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# → performance ✅
```

---

### Step 3 — bc250-smu-oc (CPU Overclock)

> ⚠️ **Critical:** Never exceed **1325 mV**. Tested safe limit is **1300 mV**. Going above without proper undervolting has permanently bricked hardware.

Installed via `pipx`. The binary is at `~/.local/bin/bc250-detect`.

**Important:** `sudo` does not include `~/.local/bin` in PATH. Always use the full path:

```bash
# Step 1: auto-detect your stable OC limit
sudo /home/deck/.local/bin/bc250-detect --frequency 4000 --vid 1275 --keep

# Expected output on this hardware:
# Detected Active Cores: 012X456X
# Final Result: 4000 MHz @ 1256 mV using scale -27

# Step 2: install as permanent system service
sudo /home/deck/.local/bin/bc250-apply --install ~/overclock.conf
sudo systemctl enable --now bc250-smu-oc.service
```

Resulting `/etc/bc250-smu-oc.conf`:
```ini
[overclock]
frequency = 4000
scale = -27
max_temperature = 90
```

Verify:
```bash
grep MHz /proc/cpuinfo | head -4
# → all cores near 4000 MHz ✅
```

---

### Step 4 — cyan-skillfish-governor-smu (GPU Governor)

Controls the GPU directly via SMU. Runs as a **root system service**.

> ⚠️ Always use `sudo systemctl` — **NOT** `systemctl --user`.

> ⚠️ Do **not** write to `power_dpm_force_performance_level` or `pp_dpm_sclk` while this service is active. It bypasses the standard DPM sysfs interface entirely.

Install the aggressive profile v2:
```bash
# Find the active config path
sudo systemctl cat cyan-skillfish-governor-smu | grep -i config

# Apply the tested profile
sudo cp examples/cyan-skillfish/config.toml.aggressive /etc/cyan-skillfish-governor/config.toml

sudo systemctl restart cyan-skillfish-governor-smu
sudo systemctl status cyan-skillfish-governor-smu
```

Key settings in the aggressive profile:

| Parameter | Value | Reason |
|---|---|---|
| `min` frequency | **1800 MHz** | Prevents FPS dips during load transitions |
| `max` frequency | 2000 MHz | Hardware maximum |
| `down-events` | 60 | Resists downclocking (default: 20) |
| `burst` ramp | 25 | Reaches 2000 MHz faster (default: 15) |
| `upper` load target | 0.75 | Scales up earlier (default: 0.90) |
| `lower` load target | 0.55 | Holds frequency longer (default: 0.75) |
| `throttling` temp | 83°C | Hard thermal limit |

GPU hardware info (confirmed via sysfs):
```
PCI_ID=1002:13FE  (AMD BC-250 / Cyan Skillfish)
SCLK range: 1000–2000 MHz
VDDC range: 700–1129 mV
Default VDDC: 799 mV @ 1000 MHz
```

---

## Active Services — Final Status

| Service | Status | Notes |
|---|---|---|
| `bc250-smu-oc.service` | ✅ enabled + active | CPU 4000 MHz @ 1256 mV |
| `cyan-skillfish-governor-smu.service` | ✅ enabled + active | GPU 1800–2000 MHz |
| `cpu-performance.service` | ✅ enabled + active | All cores locked at max |
| `bc250-acpi-fix` (initramfs) | ✅ loaded at boot | SSDT-PST + SSDT-CST |

---

## Post-Update Restore

After every SteamOS update:

```bash
git clone https://github.com/mrsasy89/steamos-bc250-restore.git
cd steamos-bc250-restore
chmod +x restore-bc250-steamos.sh post-update-check.sh

# Quick check
./post-update-check.sh

# Full restore if needed
./restore-bc250-steamos.sh
```

> Files in `/etc/` are preserved across SteamOS updates. Files in `/usr/` may be overwritten — the restore script always recreates them.

---

## Next Steps (Planned)

- [ ] **40 CU unlock** — currently 36 CU active (4 disabled at firmware level)
- [ ] Further SMU OC exploration after 40 CU baseline

---

## SteamOS Notes

- Root filesystem is read-only by default: `sudo steamos-readonly disable` before running scripts if needed.
- D-Bus policy file goes in `/usr/share/dbus-1/system.d/` (verified on SteamOS).
- ACPI tables in `/etc/initcpio/acpi_override/` are preserved across updates.
- SteamOS uses `steamcl.efi` as bootloader — GRUB-based ACPI injection does **not** work.

---

## References

- [amd-bc250-docs](https://github.com/elektricM/amd-bc250-docs)
- [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor)
- [cyan-skillfish-governor-smu (AUR)](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)
- [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc/)
- [bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
- [BC-250 video reference](https://youtu.be/AUk0Dw5aOqM?si=QW2zY-8FVncbTA3f)
- [steamos-repair-device-custom](https://github.com/InnoVision-Games/steamos-repair-device-custom)

---

## Contributing

PRs are welcome. Please open issues to report problems on specific SteamOS versions or different hardware configurations.

---

## License

[MIT](LICENSE) © 2026 mrsasy89
