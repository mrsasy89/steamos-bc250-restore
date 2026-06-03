# steamos-bc250-restore

Post-update restoration script for **SteamOS** on AMD BC-250.

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

- SteamOS on AMD BC-250
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

## What is restored

### `bc250_smu_oc`
- Clone/update the upstream repo `bc250-collective/bc250_smu_oc`
- Install with `pipx` (fallback: `pip --break-system-packages`)
- Prompts you to reimport the stable overclock profile

### `cyan-skillfish-governor-smu`
- Clone/update the `smu` branch of `filippor/cyan-skillfish-governor`
- Compile with `cargo build --release`
- Install the binary in `/usr/local/bin/`
- Regenerate the systemd `.service` file
- **Regenerate the D-Bus policy in `/usr/share/dbus-1/system.d/`** (fix for the `AccessDenied` error)
- Prompts you to reimport your stable `config.toml`

---

## Notes

- On SteamOS, the root filesystem is read-only by default: use `sudo steamos-readonly disable` before running the script if necessary.
- The D-Bus policy file goes in `/usr/share/dbus-1/system.d/` (verified to work on SteamOS).
- Files in `/etc/` are preserved by SteamOS updates; those in `/usr/` may be overwritten: the script always recreates the policy.

---

## Contributions

PRs are welcome. Please open issues to report problems on specific SteamOS versions or different hardware.
