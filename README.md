# steamos-bc250-restore

Post-update restoration script for **SteamOS** on AMD BC-250 / Cyan Skillfish.

After every SteamOS update, the `bc250-smu-oc` and `cyan-skillfish-governor-smu` services may be removed or stop working. These scripts restore the entire configuration.

---

## Contents

| File | Description |
|---|---|
| `restore-bc250-steamos.sh` | Full restore: verify, reinstall, and recreate the D-Bus policy |
| `post-update-check.sh` | Quick service status check without reinstalling |
| `examples/overclock.conf.example` | Sample overclock profile for bc250_smu_oc |
| `examples/config.toml.example` | Example config for cyan-skillfish-governor-smu |

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git
cd steamos-bc250-restore

# Make the scripts executable
chmod +x restore-bc250-steamos.sh post-update-check.sh

# Check service status
./post-update-check.sh

# Full restore (only if services are missing)
./restore-bc250-steamos.sh
```

---

## Prerequisites

- SteamOS on AMD BC-250 / Cyan Skillfish
- `git`, `python3`, `cargo` (Rust) installed
- Internet connection to download the latest versions

---

## ⚠️ Recommended stable profile

This repo **does not automatically apply** overclock or undervolt values.
Incorrect settings can damage the hardware.

**Tested and stable profile:**
- `bc250_smu_oc`: **3700 MHz @ 1125 mV** (see `examples/overclock.conf.example`)
- `cyan-skillfish-governor-smu`: GPU range **1000..=2000** (see `examples/config.toml.example`)

After each reset, manually copy your profiles:

```bash
# bc250_smu_oc
cp examples/overclock.conf.example ~/overclock.conf
# Edit the values if necessary, then:
bc250-apply --install ~/overclock.conf

# cyan-skillfish-governor-smu
sudo cp examples/config.toml.example /etc/cyan-skillfish-governor-smu/config.toml
sudo systemctl restart cyan-skillfish-governor-smu.service
```

---

## GPU — bc250_smu_oc + cyan-skillfish-governor-smu

The BC-250 is not officially supported by the stock `amdgpu` driver: GPU locked, no SMU control, crashes in gaming mode.

### What is restored

#### `bc250_smu_oc`
- Clone/update the upstream repo `bc250-collective/bc250_smu_oc`
- Install with `pipx` (fallback: `pip --break-system-packages`)
- Prompts you to reimport the stable overclock profile

#### `cyan-skillfish-governor-smu`
- Clone/update the `smu` branch of `filippor/cyan-skillfish-governor`
- Compile with `cargo build --release`
- Install the binary in `/usr/local/bin/`
- Regenerate the systemd `.service` file
- **Regenerate the D-Bus policy in `/usr/share/dbus-1/system.d/`** (fix for the `AccessDenied` error)
- Prompts you to reimport your stable `config.toml`

> ℹ️ After every SteamOS update, the D-Bus policy at `/usr/share/dbus-1/system.d/com.cyan.SkillFishGovernor.conf`
> may be wiped by the read-only filesystem reset. The restore script always recreates it automatically.

---

## CPU — ACPI P-States & C-States (mkinitcpio override)

### Problem
The BC-250 / Cyan Skillfish BIOS ships with incomplete ACPI tables: no P-States and no C-States are exposed to the OS.
This results in a fixed CPU frequency, no dynamic scaling, high power consumption, thermal throttling, and FPS drops.

> ⚠️ **Important:** SteamOS uses `steamcl.efi` as its primary bootloader, which **completely bypasses GRUB**.
> Injecting ACPI tables via a GRUB `custom.cfg` does **not** work on SteamOS.

### Solution — mkinitcpio `acpi_override` hook

| File | Description |
|---|---|
| `SSDT-PST.aml` | Custom P-States for BC-250 |
| `SSDT-CST.aml` | Custom C-States for BC-250 |

```bash
# Copy compiled ACPI tables
sudo cp ~/bc250-acpi-fix/*.aml /etc/initcpio/acpi_override/

# Edit /etc/mkinitcpio.conf.d/20-steamdeck.conf
# Add acpi_override as the FIRST entry in the HOOKS array:
# HOOKS=(acpi_override ...)

# Rebuild initramfs
sudo mkinitcpio -p linux-neptune-618
```

### Verification after reboot

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# Expected: 3200000 2550000 2325000 1960000 1820000 1600000 1271000 800000 ✅

dmesg | grep "Table Upgrade"
# Expected:
# SSDT-CST [HACK P_CST3] ✅
# SSDT-PST [HACK PSTATES] ✅
```

---

## CPU Governor — persistent `schedutil`

SteamOS does not persist the CPU governor across reboots and ignores `/etc/default/cpupower`.

### Solution — oneshot systemd service

Create `/etc/systemd/system/cpu-governor.service`:

```ini
[Unit]
Description=Set CPU governor to schedutil
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo schedutil > $cpu; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now cpu-governor.service
```

> `schedutil` is the optimal governor when ACPI P-States are active: it scales CPU frequency
> based on the Linux scheduler load, making it ideal for gaming workloads.

### Verification

```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -u
# Expected: schedutil (12/12 cores) ✅
```

---

## Active Services Status

| Service | Status |
|---|---|
| `bc250-smu-oc.service` | ✅ enabled |
| `cyan-skillfish-governor-smu.service` | ✅ enabled + running |
| `cpu-governor.service` | ✅ enabled + active (exited) |
| ACPI override (initramfs) | ✅ loaded at boot |

---

## Notes

- On SteamOS, the root filesystem is read-only by default: use `sudo steamos-readonly disable` before running the script if necessary.
- The D-Bus policy file goes in `/usr/share/dbus-1/system.d/` (verified to work on SteamOS).
- Files in `/etc/` are preserved by SteamOS updates; those in `/usr/` may be overwritten: the script always recreates the policy.
- ACPI tables in `/etc/initcpio/acpi_override/` are preserved across updates since they live under `/etc/`.

---

## Contributions

PRs are welcome. Please open issues to report problems on specific SteamOS versions or different hardware.
