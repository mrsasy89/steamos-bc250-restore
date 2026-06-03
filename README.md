# steamos-bc250-restore

Script di ripristino post-update per **SteamOS** su Lenovo Legion Go (AMD BC-250 / Cyan Skillfish).

Dopo ogni aggiornamento di SteamOS, è possibile che i servizi `bc250-smu-oc` e `cyan-skillfish-governor-smu` vengano rimossi o smettano di funzionare. Questi script ripristinano l'intera configurazione.

---

## Contenuto

| File | Descrizione |
|---|---|
| `restore-bc250-steamos.sh` | Ripristino completo: verifica, reinstalla e ricrea la policy D-Bus |
| `post-update-check.sh` | Controllo rapido stato servizi senza reinstallare |
| `examples/overclock.conf.example` | Profilo overclock di esempio per bc250_smu_oc |
| `examples/config.toml.example` | Config di esempio per cyan-skillfish-governor-smu |

---

## Uso rapido

```bash
# Clona il repo
git clone https://github.com/mrsasy89/steamos-bc250-restore.git
cd steamos-bc250-restore

# Rendi gli script eseguibili
chmod +x restore-bc250-steamos.sh post-update-check.sh

# Controlla lo stato dei servizi
./post-update-check.sh

# Ripristino completo (solo se i servizi mancano)
./restore-bc250-steamos.sh
```

---

## Prerequisiti

- SteamOS su Lenovo Legion Go (AMD BC-250 / Cyan Skillfish APU)
- `git`, `python3`, `cargo` (Rust) installati
- Connessione internet per scaricare le ultime versioni

---

## ⚠️ Profilo stabile consigliato

Questo repo **non applica automaticamente** valori di overclock o undervolt.
Impostazioni errate possono danneggiare l'hardware.

**Profilo testato e stabile:**
- `bc250_smu_oc`: **3700 MHz @ 1125 mV** (vedi `examples/overclock.conf.example`)
- `cyan-skillfish-governor-smu`: GPU range **1000..=2000** (vedi `examples/config.toml.example`)

Dopo ogni ripristino, copia manualmente i tuoi profili:

```bash
# bc250_smu_oc
cp examples/overclock.conf.example ~/overclock.conf
# Modifica i valori se necessario, poi:
bc250-apply --install ~/overclock.conf

# cyan-skillfish-governor-smu
sudo cp examples/config.toml.example /etc/cyan-skillfish-governor-smu/config.toml
sudo systemctl restart cyan-skillfish-governor-smu.service
```

---

## Cosa viene ripristinato

### `bc250_smu_oc`
- Clona/aggiorna il repo upstream `bc250-collective/bc250_smu_oc`
- Installa con `pipx` (fallback: `pip --break-system-packages`)
- Ti avvisa di reimportare il profilo overclock stabile

### `cyan-skillfish-governor-smu`
- Clona/aggiorna il ramo `smu` di `filippor/cyan-skillfish-governor`
- Compila con `cargo build --release`
- Installa il binario in `/usr/local/bin/`
- Ricrea il file `.service` systemd
- **Ricrea la policy D-Bus in `/usr/share/dbus-1/system.d/`** (fix per l'errore `AccessDenied`)
- Ti avvisa di reimportare il tuo `config.toml` stabile

---

## Note

- Su SteamOS il filesystem root è read-only di default: usa `sudo steamos-readonly disable` prima di eseguire lo script se necessario.
- Il file di policy D-Bus va in `/usr/share/dbus-1/system.d/` (verificato funzionante su SteamOS).
- I file in `/etc/` vengono preservati dagli update di SteamOS, quelli in `/usr/` possono essere sovrascritti: lo script ricrea sempre la policy.

---

## Contributi

PR benvenute. Issues per segnalare problemi su versioni specifiche di SteamOS o hardware diverso.
