# cyan-skillfish-governor-smu — Profili di configurazione

Configurazione per [cyan-skillfish-governor-smu](https://aur.archlinux.org/packages/cyan-skillfish-governor-smu),
il governor GPU via SMU per il BC-250 (Cyan Skillfish APU).

> ⚠️ **Non usare** `power_dpm_force_performance_level` o `pp_dpm_sclk` mentre
> il governor è attivo — controlla la GPU direttamente via SMU e i file sysfs
> DPM standard vengono ignorati o creano conflitto.

## File disponibili

| File | Descrizione |
|---|---|
| `config.toml.aggressive` | Profilo aggressivo testato — ramp rapido, downclock ritardato |

## Installazione

```bash
# Copia il profilo aggressivo
cp config.toml.aggressive ~/.config/cyan-skillfish-governor/config.toml

# Riavvia il governor
systemctl --user restart cyan-skillfish-governor-smu

# Verifica
systemctl --user status cyan-skillfish-governor-smu
```

## Differenze rispetto al default

| Parametro | Default | Aggressivo | Effetto |
|---|---|---|---|
| `burst` ramp rate | 15 | **25** | Picco di frequenza più rapido |
| `normal` ramp rate | 2 | **4** | Scaling su più reattivo |
| `burst-samples` | 10 | **5** | Riconosce il burst in metà tempo |
| `down-events` | 20 | **30** | Resiste prima di scalare giù |
| `upper` load target | 0.90 | **0.80** | Scala su prima |
| `lower` load target | 0.75 | **0.65** | Mantiene freq alta più a lungo |

## Stack completo BC-250

Questo profilo fa parte dello stack di ottimizzazione:

1. ✅ `bc250-acpi-fix` — fix tabelle ACPI
2. ✅ `cpu-performance.service` — governor CPU + C-states + scheduler
3. ✅ `cyan-skillfish-governor-smu` + questo `config.toml`
4. ⏳ `bc250_smu_oc` — OC via SMU (prossimo step)
5. ⏳ 40 CU unlock (step finale)
