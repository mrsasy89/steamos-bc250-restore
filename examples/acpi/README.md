# ACPI Tables — BC-250 / Cyan Skillfish

This folder contains the custom ACPI tables required to enable **P-States** and **C-States** on the AMD BC-250 / Cyan Skillfish CPU under SteamOS.

Without these tables, the CPU operates at a fixed frequency with no dynamic scaling, resulting in high power consumption, thermal throttling, and FPS drops in gaming.

---

## Why This Is Necessary

The BC-250 BIOS ships with **incomplete ACPI tables**: P-States and C-States are not exposed to the OS.

> ⚠️ **SteamOS uses `steamcl.efi` as its primary bootloader, which completely bypasses GRUB.**
> Injecting ACPI tables via a GRUB `custom.cfg` does **not** work. The only working method is via `mkinitcpio`.

---

## Files

| File | Description |
|---|---|
| `SSDT-PST.dsl` | ASL source — custom P-States for BC-250 |
| `SSDT-CST.dsl` | ASL source — custom C-States for BC-250 |

The `.dsl` files are the human-readable ASL sources.
You must **compile them to `.aml`** before using them.

---

## Prerequisites

Install the ACPI compiler (`iasl`):

```bash
# SteamOS / Arch-based
sudo steamos-readonly disable
sudo pacman -S acpica
sudo steamos-readonly enable
```

---

## Compile

```bash
cd examples/acpi/
iasl SSDT-PST.dsl   # → SSDT-PST.aml
iasl SSDT-CST.dsl   # → SSDT-CST.aml
```

---

## Install

```bash
# Create the override directory
sudo mkdir -p /etc/initcpio/acpi_override/

# Copy compiled tables
sudo cp SSDT-PST.aml SSDT-CST.aml /etc/initcpio/acpi_override/

# Add acpi_override as the FIRST hook in:
# /etc/mkinitcpio.conf.d/20-steamdeck.conf
#
# HOOKS=(acpi_override base udev ...)

# Rebuild initramfs
sudo mkinitcpio -p linux-neptune-618
```

> ℹ️ Files in `/etc/initcpio/` are preserved across SteamOS updates (unlike `/usr/` which is overwritten).

---

## Verify After Reboot

```bash
# Check available P-State frequencies
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
# Expected: 3200000 2550000 2325000 1960000 1820000 1600000 1271000 800000 ✅

# Confirm tables were loaded by the kernel
dmesg | grep "Table Upgrade"
# Expected:
# SSDT-CST [HACK P_CST3] ✅
# SSDT-PST [HACK PSTATES] ✅
```

---

## Tested Environment

| Component | Version |
|---|---|
| Hardware | AMD BC-250 / Cyan Skillfish |
| SteamOS | 3.9.0 |
| Kernel | linux-neptune-618 (6.18.33-valve1) |
| iasl (acpica) | ≥ 20230331 |

---

## Notes

- The `.dsl` sources in this folder are the reference implementation tested on SteamOS 3.9.0 with kernel `linux-neptune-618`.
- If you use a different kernel profile, replace `linux-neptune-618` in `mkinitcpio` commands accordingly.
- Always rebuild initramfs after modifying tables.
