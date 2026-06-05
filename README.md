# SteamOS BC-250 Restore

Script di ripristino post-update SteamOS per **AMD BC-250 / Cyan Skillfish** (ASRock).

Permette a utenti meno esperti di attivare i fix e l'overclock su un BC-250 appena formattato o dopo un aggiornamento di SteamOS.

---

## Supported hardware

Post-update SteamOS restore script for **AMD BC-250 / Cyan Skillfish** (ASRock).

Allows less experienced users to apply fixes and overclock a freshly formatted BC-250 or one that has been updated via SteamOS.

---

## Supported Hardware

| Field | Value |
|---|---|
| **Device** | AMD BC-250 (ASRock) |
| **APU** | Cyan Skillfish (RDNA2, PS5-based) |
| **PCI_ID** | `1002:13FE` |
| **CPU** | 12 threads (6 physical cores, 2 disabled via binning) |
| **VRAM** | 4 GB shared |
| **OS** | SteamOS 3.x Holo (Arch-based) |
| **Kernel** | linux-neptune-618 |

---

## What the script does

| Step | Component | Description |
|---|---|---|
| 1 | **SteamOS Keyring** | Initializes the `holo` keyring — required for `pacman` on SteamOS |
| 2 | **ACPI Fix** | Loads SSDT-CST and SSDT-PST via `acpi_override` in `mkinitcpio` |
| 3 | **CPU Governor** | Sets persistent `schedutil` via systemd |
| 4 | **bc250-smu-oc** | Installs and enables CPU overclocking via SMU (Python venv) |
| 5 | **cyan-skillfish-governor-smu** | Install the custom GPU governor for Cyan Skillfish |

---

## Component Status

| Component | Status | Notes |
|---|---|---|
| `bc250-acpi-fix` | ✅ Stable | SSDT-CST + SSDT-PST via acpi_override in 20-steamdeck.conf |
| `bc250-smu-oc` | ✅ Active | Profile: 4000 MHz @ 1256 mV scale -27 max_temp 90°C |
| `cyan-skillfish-governor-smu` | 🔄 Testing | GPU Profile: min=1800, max=2000 MHz |

---

## Usage

```bash
# 1. Clone the repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git ~/fix/steamos-bc250-restore
cd ~/fix/steamos-bc250-restore

# 2. Make executable
chmod +x restore-bc250-steamos.sh

# 3. Run
./restore-bc250-steamos.sh
```

> ⚠️ The script requires an internet connection to clone the component repositories.

---

## First boot: CPU OC (bc250-smu-oc)

If this is your first installation, the script does not have a saved OC profile. 
You must first run the detect script to find stable values for your chip:

```bash
# The detect script performs incremental stress tests from 3500 MHz up to the target
# and automatically finds stable values for your specific hardware
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_detect.py \
  
-f 4000 \
  -v 1275 \
  -t 90 \
  -k \
  -c /etc/bc250-smu-oc.conf
```

| Parameter | Value | Meaning |
|---|---|---|
| `-f 4000` | 4000 MHz | Maximum target frequency |
| `-v 1275` | 1275 mV | Maximum allowed voltage |
| `-t 90` | 90°C | CPU+GPU temperature limit |
| `-k` | keep | Keep OC active after the test |
| `-c` | path | Configuration file path |

> ⚠️ **Every chip is different.** The detection process finds the optimal values for your specific hardware. 
> ⚠️ **Do not exceed 1300 mV** to avoid damaging the CPU.

After detection, apply the profile and install the systemd service:

```bash
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_apply.py \
  --apply --install /etc/bc250-smu-oc.conf
sudo systemctl enable --now bc250-smu-oc.service
```

---

## Important Technical Notes

### Python and pip on SteamOS

SteamOS uses Python 3.13 with **PEP 668** — the environment is “externally managed”. 
`pip --break-system-packages` is blocked. The correct method is a **virtualenv**:

```bash
python3 -m venv ~/.venv/bc250
~/.venv/bc250/bin/pip install ~/fix/bc250_smu_oc/
```

The venv resides in the home directory — **it survives SteamOS updates**.

### Pacman Keyring on SteamOS

SteamOS packages are signed by `ci-package-builder-1@steamos.cloud`. 
Standard Arch keys aren’t enough — you need the `holo` keyring:

```bash
sudo pacman-key --init
sudo pacman-key --populate holo
```

### Overclocking via SMU and scaling_available_frequencies

`scaling_available_frequencies` only shows **ACPI P-States** (maximum 3200 MHz). 
SMU overclocking operates at the hardware level and bypasses this limit — this is normal and expected. 
To verify the actual frequency, use `/proc/cpuinfo` under load or the in-game monitor.

### ACPI fix — correct method

```
/etc/initcpio/acpi_override/SSDT-CST.aml ← active .aml files
/etc/initcpio/acpi_override/SSDT-PST.aml
/etc/mkinitcpio.conf.d/20-steamdeck.conf ← drop-in with acpi_override hook
```

**DO NOT modify:**
- Main `mkinitcpio.conf` (overwritten by updates)
- `grub.cfg` for ACPI (the `/boot/` path is relative to btrfs, not to EFI)

Post-reboot verification:
```bash
sudo dmesg | grep -i “Table Upgrade”
# Expected: install [SSDT- HACK- P_CST3] and install [SSDT- HACK- PSTATES]
```

### CPU Governor

The correct governor with ACPI P-States enabled is **schedutil**. 
SteamOS handles this natively — no `cpupower` or external tools are needed.

---

## Active grub.cfg parameters (stock — DO NOT modify)

```
amd_iommu=off
amdgpu.lockup_timeout=5000,10000,10000,5000
ttm.pages_min=2097152
amdgpu.sched_hw_submission=4
amdgpu.dcdebugmask=0x20000
```

> ⚠️ If CP2077 shows a green screen → increase `lockup_timeout=10000,10000,10000,10000`

---

## Important paths

```
~/fix/ → directory containing all fix repositories
~/fix/bc250-acpi-fix/ → source .aml files
/etc/initcpio/acpi_override/ → active .aml files (initramfs)
/etc/mkinitcpio.conf.d/20-steamdeck.conf → mkinitcpio drop-in
/boot/efi/EFI/steamos/grub.cfg → kernel parameters (overwritten with every update)
/etc/bc250-smu-oc.conf → CPU OC config
/etc/cyan-skillfish-governor-smu/config.toml → GPU governor config
~/.venv/bc250/ → Python venv for bc250_smu_oc
```

---

## Next steps

- [ ] **cyan-skillfish-governor-smu** — stable GPU profile test (min=1800, max=2000 MHz)
- [ ] **Unlock 40 CUs** — enable Compute Units disabled via binning

---

## Sources

- [amd-bc250-docs](https://github.com/elektricM/amd-bc250-docs)
- [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
- [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor)
- [bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
- [cyan-skillfish-governor-smu AUR](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)


| Campo | Valore |
|---|---|
| **Device** | AMD BC-250 (ASRock) |
| **APU** | Cyan Skillfish (RDNA2, base PS5) |
| **PCI_ID** | `1002:13FE` |
| **CPU** | 12 thread (6 core fisici, 2 disabilitati via binning) |
| **VRAM** | 4 GB condivisa |
| **OS** | SteamOS 3.x Holo (Arch-based) |
| **Kernel** | linux-neptune-618 |

---

## Cosa fa lo script

| Step | Componente | Descrizione |
|---|---|---|
| 1 | **Keyring SteamOS** | Inizializza `holo` keyring — necessario per `pacman` su SteamOS |
| 2 | **ACPI Fix** | Carica SSDT-CST e SSDT-PST via `acpi_override` in `mkinitcpio` |
| 3 | **Rimozione cpu-performance.service** | Elimina il servizio incompatibile con P-States ACPI |
| 4 | **CPU Governor** | Imposta `schedutil` persistente via systemd |
| 5 | **bc250-smu-oc** | Installa e abilita l'overclock CPU via SMU (Python venv) |
| 6 | **cyan-skillfish-governor-smu** | Installa il GPU governor personalizzato per Cyan Skillfish |

---

## Stato componenti

| Componente | Stato | Note |
|---|---|---|
| `bc250-acpi-fix` | ✅ Stabile | SSDT-CST + SSDT-PST via acpi_override in 20-steamdeck.conf |
| `cpu-performance.service` | ❌ Rimosso | Causa artefatti e cali FPS con P-States ACPI attivi |
| `bc250-smu-oc` | ✅ Attivo | Profilo: 4000 MHz @ 1256 mV scale -27 max_temp 90°C |
| `cyan-skillfish-governor-smu` | 🔄 In test | Profilo GPU: min=1800, max=2000 MHz |

---

## Utilizzo

```bash
# 1. Clona il repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git ~/fix/steamos-bc250-restore
cd ~/fix/steamos-bc250-restore

# 2. Rendi eseguibile
chmod +x restore-bc250-steamos.sh

# 3. Esegui
./restore-bc250-steamos.sh
```

> ⚠️ Lo script richiede connessione internet per clonare i repo dei componenti.

---

## Primo avvio: OC CPU (bc250-smu-oc)

Se è la prima installazione, lo script non ha un profilo OC salvato.  
Devi prima eseguire il detect per trovare i valori stabili del tuo chip:

```bash
# Il detect esegue stress test incrementali da 3500 MHz fino al target
# e trova automaticamente i valori stabili per il tuo hardware specifico
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_detect.py \
  -f 4000 \
  -v 1275 \
  -t 90 \
  -k \
  -c /etc/bc250-smu-oc.conf
```

| Parametro | Valore | Significato |
|---|---|---|
| `-f 4000` | 4000 MHz | Frequenza target massima |
| `-v 1275` | 1275 mV | Tensione massima consentita |
| `-t 90` | 90°C | Limite temperatura CPU+GPU |
| `-k` | keep | Mantieni OC attivo dopo il test |
| `-c` | path | Percorso del file di configurazione |

> ⚠️ **Ogni chip è diverso.** Il detect trova i valori ottimali per il tuo hardware specifico.  
> ⚠️ **Non superare 1300 mV** per evitare danni alla CPU.

Dopo il detect, applica il profilo e installa il servizio systemd:

```bash
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_apply.py \
  --apply --install /etc/bc250-smu-oc.conf
sudo systemctl enable --now bc250-smu-oc.service
```

---

## Note tecniche importanti

### Python e pip su SteamOS

SteamOS usa Python 3.13 con **PEP 668** — l'ambiente è "externally managed".  
`pip --break-system-packages` è bloccato. Il metodo corretto è un **virtualenv**:

```bash
python3 -m venv ~/.venv/bc250
~/.venv/bc250/bin/pip install ~/fix/bc250_smu_oc/
```

Il venv vive nella home — **sopravvive agli update SteamOS**.

### Keyring pacman su SteamOS

I pacchetti SteamOS sono firmati da `ci-package-builder-1@steamos.cloud`.  
Le chiavi Arch standard non bastano — serve il keyring `holo`:

```bash
sudo pacman-key --init
sudo pacman-key --populate holo
```

### OC via SMU e scaling_available_frequencies

`scaling_available_frequencies` mostra solo i **P-States ACPI** (massimo 3200 MHz).  
L'OC SMU agisce a livello hardware e bypassa questo limite — è normale e atteso.  
Per verificare la frequenza reale, usare `/proc/cpuinfo` sotto carico o il monitor in-game.

### ACPI fix — metodo corretto

```
/etc/initcpio/acpi_override/SSDT-CST.aml   ← file .aml attivi
/etc/initcpio/acpi_override/SSDT-PST.aml
/etc/mkinitcpio.conf.d/20-steamdeck.conf    ← drop-in con hook acpi_override
```

**NON modificare:**
- `mkinitcpio.conf` principale (sovrascritto dagli update)
- `grub.cfg` per ACPI (il path `/boot/` è relativo alla btrfs, non alla EFI)

Verifica post-riavvio:
```bash
sudo dmesg | grep -i "Table Upgrade"
# Atteso: install [SSDT- HACK- P_CST3] e install [SSDT- HACK- PSTATES]
```

### Governor CPU

Il governor corretto con P-States ACPI attivi è **schedutil**.  
SteamOS lo gestisce nativamente — non serve `cpupower` o tool esterni.

---

## Parametri grub.cfg attivi (stock — NON modificare)

```
amd_iommu=off
amdgpu.lockup_timeout=5000,10000,10000,5000
ttm.pages_min=2097152
amdgpu.sched_hw_submission=4
amdgpu.dcdebugmask=0x20000
```

> ⚠️ Se CP2077 mostra schermo verde → aumentare `lockup_timeout=10000,10000,10000,10000`

---

## Path importanti

```
~/fix/                                        → directory tutti i repo fix
~/fix/bc250-acpi-fix/                         → file .aml sorgente
/etc/initcpio/acpi_override/                  → file .aml attivi (initramfs)
/etc/mkinitcpio.conf.d/20-steamdeck.conf      → drop-in mkinitcpio
/boot/efi/EFI/steamos/grub.cfg               → parametri kernel (sovrascritto ad ogni update)
/etc/bc250-smu-oc.conf                        → config OC CPU
/etc/cyan-skillfish-governor-smu/config.toml  → config GPU governor
~/.venv/bc250/                                → Python venv per bc250_smu_oc
```

---

## Prossimi step

- [ ] **cyan-skillfish-governor-smu** — test profilo GPU stabile (min=1800, max=2000 MHz)
- [ ] **Sblocco 40 CU** — attivazione delle Compute Unit disabilitate via binning

---

## Fonti

- [amd-bc250-docs](https://github.com/elektricM/amd-bc250-docs)
- [bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
- [cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor)
- [bc250-acpi-fix](https://github.com/bc250-collective/bc250-acpi-fix)
- [cyan-skillfish-governor-smu AUR](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)
