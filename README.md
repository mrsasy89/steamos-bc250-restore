# SteamOS BC-250 Restore

Script di ripristino post-update SteamOS per **AMD BC-250 / Cyan Skillfish** (Lenovo Legion Go Gen 1).

Permette a utenti meno esperti di attivare e mantenere i fix e l'overclock su BC-250 appena formattata o dopo ogni aggiornamento SteamOS.

> **Testato su**: SteamOS 3.9 Holo — Kernel 6.18.x-neptune-618  
> **Hardware**: AMD BC-250 / Cyan Skillfish (PCI_ID: 1002:13FE)  
> **Validato gaming**: CP2077, RE4 Remake, Horizon Zero Dawn Remastered, Diablo IV — stabile, nessun crash

---

## Cosa fa lo script

| Step | Componente | Stato |
|------|-----------|-------|
| 1 | Fix ACPI P-States/C-States via `mkinitcpio acpi_override` | ✅ Stabile |
| 2 | Rimozione `cpu-performance.service` (causa artefatti GPU) | ✅ Stabile |
| 3 | CPU governor `schedutil` persistente via systemd | ✅ Stabile |
| 4 | `bc250_smu_oc` CPU OC 3800 MHz via Python venv | ✅ Validato |
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

# 3. Esegui
./restore-bc250-steamos.sh

# 4. Riavvia per attivare ACPI e policy D-Bus
reboot
```

---

## Primo avvio: passi manuali

### bc250_smu_oc (CPU OC)

```bash
# Detect del profilo stabile per il tuo chip — OBBLIGATORIO
# Ogni BC-250 è diverso, NON usare valori di esempio senza detect
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_detect.py \
  -f 3800 -v 1275 -t 90 -k -c /etc/bc250-smu-oc.conf

# Applica e installa il servizio
sudo ~/.venv/bc250/bin/python3 ~/fix/bc250_smu_oc/bc250_apply.py \
  --apply --install /etc/bc250-smu-oc.conf
```

Vedi `bc250-smu-oc.conf.example` per il formato del file e i valori di riferimento.

### cyan-skillfish-governor-smu (GPU governor)

```bash
# Copia il config validato
sudo cp config.toml /etc/cyan-skillfish-governor-smu/config.toml

# Avvia e abilita al boot
sudo systemctl enable --now cyan-skillfish-governor-smu

# Verifica
systemctl status cyan-skillfish-governor-smu --no-pager -l
```

Log atteso:
```
INFO  GPU usage method: busy-flag set method: smu
INFO  SMU communication verified
INFO  D-Bus service thread started
INFO  allowed frequency range 1000..=2000
INFO  D-Bus performance mode service ready
```

---

## Profilo CPU OC (bc250-smu-oc.conf)

| Parametro | Valore | Note |
|-----------|--------|------|
| frequency | 3800 MHz | trovato con bc250_detect.py |
| scale | -12 | undervolt ottimale — trovato da detect |
| max_temperature | 90°C | limite termico detect |

> ⚠️ **Importante**: a 4000 MHz il picco CPU+GPU durante la compilazione shader Vulkan
> supera il budget energetico condiviso del chip → crash con schermo nero.
> 3800 MHz è il punto bilanciato validato su tutti i titoli testati.

---

## Profilo GPU governor (config.toml)

**Profilo: performance-balanced v5** — validato CP2077, RE4R, Horizon Zero Dawn Remastered, Diablo IV

| Frequenza | Voltage | Note |
|-----------|---------|------|
| 1000 MHz | 800 mV | idle / compilazione shader |
| 1175 MHz | 850 mV | transizione bassa |
| 1500 MHz | 900 mV | mid |
| 1700 MHz | 920 mV | pre-gaming |
| 1850 MHz | 930 mV | gaming stabile |
| 2000 MHz | 960 mV | gaming principale ✅ validato |

> ⚠️ **CRITICO**: `min = 1000` è obbligatorio. Con `min = 1500` il governor mantiene
> la GPU a 1500 MHz anche durante la compilazione shader, sommando il consumo
> CPU+GPU e causando crash con schermo nero.

Safe-points da: [filippor/cyan-skillfish-governor ramo smu](https://github.com/filippor/cyan-skillfish-governor/blob/smu/default-config.toml)

---

## Compilazione shader Vulkan — spiegazione crash

La compilazione shader è **100% CPU-bound** — la GPU non è coinvolta.
Il driver AMD converte gli shader su CPU usando tutti i thread disponibili (90-95% CPU).

Su BC-250, CPU e GPU **condividono lo stesso die e lo stesso budget energetico**.
Se il governor GPU spinge a frequenze alte mentre la CPU è già al massimo,
la somma supera il budget → crash con schermo nero.

**Soluzione adottata**: `min = 1000` nel config.toml + CPU OC a 3800 MHz invece di 4000.

---

## Note tecniche importanti

### Non fare mai
- ❌ `sudo systemctl restart dbus` — **congela SteamOS** (hard reset necessario)
- ❌ Modificare `/boot/grub.cfg` per ACPI — il path è relativo a btrfs, non EFI
- ❌ `pip install --break-system-packages` — bloccato da PEP 668 su Python 3.13
- ❌ `cpu-performance.service` con P-States ACPI attivi — causa artefatti GPU
- ❌ `min = 1500` nel governor — causa crash durante compilazione shader Vulkan

### PEP 668 — Python su SteamOS
```bash
python3 -m venv ~/.venv/bc250
```
Il venv sopravvive agli update SteamOS.

### D-Bus policy
Dopo aver scritto la policy in `/etc/dbus-1/system.d/`, è necessario un **riavvio**.
`systemctl restart dbus` congela il sistema su SteamOS.

### scaling_available_frequencies
Mostra solo i P-States ACPI (max 3200 MHz). L'OC GPU via SMU agisce a livello
hardware — per la frequenza reale usare il monitor in-game o `radeontop`.

### cyan-skillfish-governor-smu v0.4.6
Il tar v0.4.6 non include `scripts/cyan-skillfish-performance-mode` — `install.sh`
fallisce su quel file. Lo script usa installazione manuale che salta quella parte.

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
- [x] bc250_smu_oc CPU OC (3800 MHz, scale=-12)
- [x] cyan-skillfish-governor-smu v0.4.6 installato e validato
- [x] GPU governor 1000-2000 MHz — validato su 4 titoli AAA
- [x] Profilo bilanciato CPU+GPU — compilazione shader Vulkan stabile
- [ ] **Prossimo**: Tuning governor per target 60fps stabili su titoli AAA
- [ ] **Futuro**: Sblocco 40 CU (Compute Unit disabilitate via binning)

---

## Riferimenti

- [filippor/cyan-skillfish-governor](https://github.com/filippor/cyan-skillfish-governor) — ramo `smu`
- [bc250-collective/bc250_smu_oc](https://github.com/bc250-collective/bc250_smu_oc)
- [elektricm.github.io/amd-bc250-docs](https://elektricm.github.io/amd-bc250-docs/)
- [cyan-skillfish-governor-smu AUR](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu)
