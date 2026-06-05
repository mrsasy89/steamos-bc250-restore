# SteamOS BC-250 Restore

Script di ripristino post-update SteamOS per **AMD BC-250 / Cyan Skillfish** (Lenovo Legion Go Gen 1).

Permette a utenti meno esperti di attivare e mantenere i fix e l'overclock su BC-250 appena formattata o dopo ogni aggiornamento SteamOS.

> **Testato su**: SteamOS 3.9 Holo — Kernel 6.18.x-neptune-618  
> **Hardware**: AMD BC-250 / Cyan Skillfish (PCI_ID: 1002:13FE)  
> **Validato gaming**: CP2077, Resident Evil 4 Remake — stabile, nessun crash

---

## Cosa fa lo script

| Step | Componente | Stato |
|------|-----------|-------|
| 1 | Fix ACPI P-States/C-States via `mkinitcpio acpi_override` | ✅ Stabile |
| 2 | Rimozione `cpu-performance.service` (causa artefatti GPU) | ✅ Stabile |
| 3 | CPU governor `schedutil` persistente via systemd | ✅ Stabile |
| 4 | `bc250_smu_oc` CPU OC via Python venv | ✅ Stabile |
| 5 | `cyan-skillfish-governor-smu` v0.4.6 GPU governor | ✅ Validato |
| 6 | Policy D-Bus `com.cyan.SkillFishGovernor` | ✅ Stabile |
| 7 | Tuning governor per 60fps stabili | 🔄 In corso |
| 8 | Sblocco 40 CU | 📋 Futuro |

---

## Installazione rapida

```bash
# 1. Clona il repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git ~/fix/restore
cd ~/fix/restore

# 2. Rendi lo script eseguibile
chmod +x restore-bc250-steamos.sh

# 3. Esegui come utente deck (usa sudo internamente dove necessario)
./restore-bc250-steamos.sh

# 4. Riavvia per attivare le tabelle ACPI e la policy D-Bus
reboot
```

---

## Primo avvio: passi manuali

Alcuni componenti richiedono configurazione manuale la prima volta:

### bc250_smu_oc (CPU OC)

```bash
# Detect del profilo stabile per il tuo chip
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_detect.py \
  -f 4000 -v 1275 -t 90 -k -c /etc/bc250-smu-oc.conf

# Applica e installa il servizio
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_apply.py \
  --apply --install /etc/bc250-smu-oc.conf
```

### cyan-skillfish-governor-smu (GPU governor)

Il binario v0.4.6 viene installato automaticamente dallo script.
Il config viene copiato da `config.toml` (questo repo) in `/etc/cyan-skillfish-governor-smu/config.toml`.

```bash
# Copia il config validato
sudo cp config.toml /etc/cyan-skillfish-governor-smu/config.toml

# Avvia e abilita al boot
sudo systemctl enable --now cyan-skillfish-governor-smu

# Verifica
systemctl status cyan-skillfish-governor-smu --no-pager -l
```

Log atteso con configurazione corretta:
```
INFO  GPU usage method: busy-flag set method: smu
INFO  SMU communication verified
INFO  D-Bus service thread started
INFO  allowed frequency range 1000..=2000
INFO  D-Bus performance mode service ready
```

---

## Profilo GPU governor (config.toml)

**Profilo: performance-stable v3** — validato CP2077 + RE4R

| Frequenza | Voltage | Note |
|-----------|---------|------|
| 1000 MHz | 800 mV | idle |
| 1175 MHz | 850 mV | transizione bassa |
| 1500 MHz | 900 mV | mid |
| 1700 MHz | 920 mV | pre-gaming |
| 1850 MHz | 930 mV | gaming stabile |
| 2000 MHz | 960 mV | gaming principale ✅ validato |

Safe-points da: [filippor/cyan-skillfish-governor ramo smu](https://github.com/filippor/cyan-skillfish-governor/blob/smu/default-config.toml)

---

## Note tecniche importanti

### Non fare mai
- ❌ `sudo systemctl restart dbus` — **congela SteamOS** (hard reset necessario)
- ❌ Modificare `/boot/grub.cfg` per ACPI — il path è relativo a btrfs, non EFI
- ❌ `pip install --break-system-packages` — bloccato da PEP 668 su Python 3.13
- ❌ `cpu-performance.service` con P-States ACPI attivi — causa artefatti GPU

### PEP 668 — Python su SteamOS
SteamOS usa Python 3.13 con ambiente "externally managed". L'unico metodo corretto è:
```bash
python3 -m venv ~/.venv/bc250
```
Il venv sopravvive agli update SteamOS.

### Keyring SteamOS
```bash
sudo pacman-key --init
sudo pacman-key --populate holo
```
Necessario per pacman su SteamOS — le chiavi Arch standard non coprono i pacchetti firmati da Valve.

### ACPI override
L'hook `acpi_override` va nel drop-in `/etc/mkinitcpio.conf.d/20-steamdeck.conf`, **non** nel `mkinitcpio.conf` principale (viene sovrascritto dagli update).

### D-Bus policy
Dopo aver scritto la policy in `/etc/dbus-1/system.d/`, è necessario un **riavvio** per caricarla. `systemctl restart dbus` congela il sistema su SteamOS.

### scaling_available_frequencies
Mostra solo i P-States ACPI (max 3200 MHz). L'OC GPU via SMU agisce a livello hardware e bypassa questo limite — è normale. Per verificare la frequenza GPU reale usare il monitor in-game o `radeontop`.

### cyan-skillfish-governor-smu v0.4.6
Il tar v0.4.6 **non include** `scripts/cyan-skillfish-performance-mode` — `install.sh` fallisce su quel file. Lo script usa l'installazione manuale che salta quella parte non critica.

---

## Path importanti

```
/etc/cyan-skillfish-governor-smu/config.toml    # config GPU governor
/etc/cyan-skillfish-governor-smu/cyan-skillfish-governor-smu  # binario
/etc/systemd/system/cyan-skillfish-governor-smu.service
/etc/dbus-1/system.d/com.cyan.SkillFishGovernor.conf
/etc/bc250-smu-oc.conf                          # profilo CPU OC
~/.venv/bc250/                                  # Python venv bc250_smu_oc
~/fix/bc250_smu_oc/                             # sorgenti bc250_smu_oc
/etc/mkinitcpio.conf.d/20-steamdeck.conf        # drop-in mkinitcpio
/etc/initcpio/acpi_override/                    # tabelle ACPI .aml
```

---

## Roadmap

- [x] Fix ACPI P-States/C-States
- [x] CPU governor schedutil
- [x] bc250_smu_oc CPU OC (4000 MHz @ 1275 mV)
- [x] cyan-skillfish-governor-smu v0.4.6 installato e validato
- [x] GPU governor 1000-2000 MHz safe-points ufficiali
- [ ] **Prossimo**: Tuning governor per target 60fps stabili su titoli AAA
- [ ] **Futuro**: Sblocco 40 CU (Compute Unit disabilitate via binning)

---

## Riferimenti

- [filippor/cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) — ramo `smu`
- [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
- [elektricm.github.io/amd-bc250-docs](https://elektricm.github.io/amd-bc250-docs/)
- [cyan-skillfish-governor-smu AUR](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)
