# SteamOS BC-250 Restore

Post-update SteamOS restore script for **ASRock BC-250 / Cyan Skillfish**.

It allows less experienced users to enable and maintain fixes and overclocking on a freshly formatted BC-250 or after every SteamOS update.

> **Tested on**: SteamOS 3.9 Holo — Kernel 6.18.x-neptune-618  
> **Hardware**: AMD BC-250 / Cyan Skillfish (PCI_ID: 1002:13FE)  
> **Gaming validated**: CP2077, RERequiem, Horizon Zero Dawn Remastered, Diablo IV — stable, no crashes

---

## What the script does

| Step | Component | Status |
|------|-----------|-------|
| 1 | Fix ACPI P-States/C-States via `mkinitcpio acpi_override` | ✅ Stable |
| 2 | Remove `cpu-performance.service` (causes GPU artifacts) | ✅ Stable |
| 3 | Persistent `schedutil` CPU governor via systemd | ✅ Stable |
| 4 | `bc250_smu_oc` CPU OC 3800 MHz via Python venv | ✅ Validated |
| 5 | `cyan-skillfish-governor-smu` v0.4.6 GPU governor | ✅ Validated |
| 6 | D-Bus policy `com.cyan.SkillFishGovernor` | ✅ Stable |
| 7 | Governor tuning for stable 60fps | 🔄 In progress |
| 8 | Unlock 40 CUs | 📋 Future |
---

## Quick installation

```bash
# 1. Clone the repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git ~/fix/restore
cd ~/fix/restore

# 2. Make the script executable
chmod +x restore-bc250-steamos.sh

# 3. Run
./restore-bc250-steamos.sh

# 4. Reboot to activate ACPI and D-Bus policies
reboot
```

---

## First boot: manual steps

### bc250_smu_oc (CPU OC)

```bash
# Detect the stable profile for your chip — MANDATORY
# Every BC-250 is different; DO NOT use example values without detection
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_detect.py \
  -f 3800 -v 1275 -t 90 -k -c /etc/bc250-smu-oc.conf

# Apply and install the service
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_apply.py \
  --apply --install /etc/bc250-smu-oc.conf
```

See `bc250-smu-oc.conf.example` for the file format and reference values.

### cyan-skillfish-governor-smu (GPU governor)

```bash
# Copy the validated config
sudo cp config.toml /etc/cyan-skillfish-governor-smu/config.toml

# Start and enable at boot
sudo systemctl enable --now cyan-skillfish-governor-smu

# Verify
systemctl status cyan-skillfish-governor-smu --no-pager -l
```

Expected log:
```
INFO  GPU usage method: busy-flag set method: smu
INFO  SMU communication verified
INFO  D-Bus service thread started
INFO  allowed frequency range 1000..=2000
INFO  D-Bus performance mode service ready
```

---

## CPU OC Profile (bc250-smu-oc.conf)

| Parameter | Value | Notes |
|-----------|--------|------|
| frequency | 3800 MHz | found with bc250_detect.py |
| scale | -12 | optimal undervoltage — found by detect |
| max_temperature | 90°C | thermal limit from detect |

> ⚠️ **Important**: at 4000 MHz, the CPU+GPU peak during Vulkan shader compilation
> exceeds the chip’s shared power budget → crash with black screen.
> 3800 MHz is the balanced point validated across all tested titles.

---

## GPU governor profile (config.toml)

**Profile: performance-balanced v5** — validated on CP2077, RERequiem, Horizon Zero Dawn Remastered, Diablo IV

| Frequency | Voltage | Notes |
|-------- ---|---------|------|
| 1000 MHz | 800 mV | idle / shader compilation |
| 1175 MHz | 850 mV | low transition |
| 1500 MHz | 900 mV | mid |
| 1700 MHz | 920 mV | pre-gaming |
| 1850 MHz | 930 mV | stable gaming |
| 2000 MHz | 960 mV | main gaming ✅ validated |

> ⚠️ **CRITICAL**: `min = 1000` is mandatory. With `min = 1500`, the governor keeps
> the GPU at 1500 MHz even during shader compilation, adding to the
> CPU+GPU load and causing crashes with a black screen.

Safe-points from: [filippor/cyan-skillfish-governor smu branch](https://github.com/filippor/cyan-skillfish-governor/blob/smu/default-config.toml)

---

## Vulkan Shader Compilation — Crash Explanation

Shader compilation is **100% CPU-bound** — the GPU is not involved.
The AMD driver compiles shaders on the CPU using all available threads (90–95% CPU).

On the BC-250, the CPU and GPU **share the same die and the same power budget**.
If the GPU governor pushes to high frequencies while the CPU is already at maximum,
the total exceeds the budget → crash with black screen.

**Solution adopted**: `min = 1000` in config.toml + CPU OC to 3800 MHz instead of 4000.

---

## After changing the governor profile — Cleanup required

> ⚠️ **Important**: after any change to the CPU/GPU governor profile (e.g. modifying
> `config.toml` or `bc250-smu-oc.conf`), some games may crash or fail to save.
> This is caused by a **corrupted Proton prefix** left over from the previous profile,
> not by the new configuration itself.
>
> Validated affected titles: **RE: Requiem** and potentially other Proton-based games
> that store GPU/CPU-specific data in the prefix.

### Why this happens

Each time you run a game under Proton, Wine records system-level state (registry keys,
GPU info, D3D/Vulkan caps) inside `compatdata/<APP_ID>`. When the CPU or GPU governor
profile changes significantly, this cached state becomes stale and causes crashes,
black screens, or failed saves on next launch.

### Fix: clean compatdata and shadercache

Replace `APP_ID` with the Steam App ID of the affected game (e.g. `3764200` for RE: Requiem):

```bash
APP_ID=3764200

# 1. Backup and reset the Proton prefix
mv ~/.local/share/Steam/steamapps/compatdata/${APP_ID} \
   ~/.local/share/Steam/steamapps/compatdata/${APP_ID}.bak

# 2. Delete the shader cache
rm -rf ~/.local/share/Steam/steamapps/shadercache/${APP_ID}

# 3. Verify both are gone (output should be empty)
ls ~/.local/share/Steam/steamapps/compatdata/ | grep ${APP_ID}
ls ~/.local/share/Steam/steamapps/shadercache/ | grep ${APP_ID}
```

Launch the game — Steam will recreate a fresh prefix and recompile shaders automatically.
Allow shader compilation to complete before loading any save.

> 💡 **Tip**: renaming compatdata with `.bak` instead of deleting it preserves your old
> prefix as a fallback. Restore it at any time by reversing the `mv` command.

### GUI alternative: Storage Cleaner (Decky Loader)

If you use [Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader), the
**Storage Cleaner** plugin provides a visual interface to delete compatdata and
shadercache per game without using the terminal:

Decky → Store → search "Storage Cleaner" → Install
Repository: [github.com/mcarlucci/decky-storage-cleaner](https://github.com/mcarlucci/decky-storage-cleaner)

---

## Important technical notes

### Never do
- ❌ `sudo systemctl restart dbus` — **freezes SteamOS** (hard reset required)
- ❌ Modify `/boot/grub.cfg` for ACPI — the path is relative to btrfs, not EFI
- ❌ `pip install --break-system-packages` — blocked by PEP 668 on Python 3.13
- ❌ `cpu-performance.service` with ACPI P-States enabled — causes GPU artifacts
- ❌ `min = 1500` in the governor — causes crashes during Vulkan shader compilation

### PEP 668 — Python on SteamOS
```bash
python3 -m venv ~/.venv/bc250
```
The venv survives SteamOS updates.

### D-Bus policy
After writing the policy to `/etc/dbus-1/system.d/`, a **reboot** is required.
`systemctl restart dbus` freezes the system on SteamOS.

### scaling_available_frequencies
Shows only ACPI P-States (max 3200 MHz). GPU overclocking via SMU operates at the
hardware level — for the actual frequency, use the in-game monitor or `radeontop`.

### cyan-skillfish-governor-smu v0.4.6
The v0.4.6 tarball does not include `scripts/cyan-skillfish-performance-mode` — `install.sh`
fails on that file. The script uses a manual installation that skips that part.

---

## Important paths

```
/etc/cyan-skillfish-governor-smu/config.toml    # GPU governor config
/etc/cyan-skillfish-governor-smu/cyan-skillfish-governor-smu  # binary
/etc/systemd/system/cyan-skillfish-governor-smu.service
/etc/dbus-1/system.d/com.cyan.SkillFishGovernor.conf
/etc/bc250-smu-oc.conf                          # CPU OC profile
~/.venv/bc250/                                  # Python venv bc250_smu_oc
~/fix/bc250_smu_oc/                             # bc250_smu_oc sources
/etc/mkinitcpio.conf.d/20-steamdeck.conf        # mkinitcpio drop-in
/etc/initcpio/acpi_override/                    # ACPI .aml tables
```

---

## Roadmap

- [x] Fix ACPI P-States/C-States
- [x] CPU governor schedutil
- [x] bc250_smu_oc CPU OC (3800 MHz, scale=-12)
- [x] cyan-skillfish-governor-smu v0.4.6 installed and validated
- [x] GPU governor 1000-2000 MHz — validated on 4 AAA titles
- [x] Balanced CPU+GPU profile — stable Vulkan shader compilation
- [x] Documented compatdata/shadercache cleanup after governor changes
- [ ] **Next**: Governor tuning for stable 60fps — Variant D in testing (`upper=0.80`, `down-events=15`)
- [ ] **Next**: Per-game FSR/scaling validation table
- [ ] **Next**: Zswap over Zram — may reduce in-game crashes under memory pressure
- [ ] **Next**: CPU mitigations tuning — potential performance gain on gaming workloads
- [ ] **Future**: Unlock 40 CUs (Compute Units disabled via binning)

---

## References

- [elektricm.github.io/amd-bc250-docs](https://elektricm.github.io/amd-bc250-docs/)
- [bc250-collective/amd_smu_reverse_engineering](https://github.com/bc250-collective/amd_smu_reverse_engineering)
- [bc250-collective/bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
- [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
- [filippor/cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) — `smu` branch
- [cyan-skillfish-governor-smu AUR](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)
- [mcarlucci/decky-storage-cleaner](https://github.com/mcarlucci/decky-storage-cleaner)
- [Old Lamer — BC-250 Full Guide (YouTube)](https://youtu.be/ajZCscNZbE8)
- [InnoVision Games — BC 250 ALL 40 CUs on REAL SteamOS! (YouTube)](https://www.youtube.com/watch?v=L88Ws8XEsbY&t)
