# CPU Aggressive Performance Mode

Servizio systemd per la modalità performance **massima e permanente** sulla Legion Go (BC250 / Z1 Extreme).

## Cosa fa

| Ottimizzazione | Dettaglio | Impatto |
|---|---|---|
| `scaling_governor=performance` | Tutti i 12 core fissi al massimo | +latenza prevedibile |
| `scaling_min_freq = max_freq` | Nessuno scaling verso il basso | +fps stabili |
| AMD Core Performance Boost | Mantiene il boost attivo | +burst monothread |
| `sched_latency_ns=1ms` | Scheduler più reattivo | −jitter CPU |
| IRQ pinning su core 0 | Interrupt di sistema su CPU0, core 1-11 liberi | −interrupt overhead nei giochi |
| Transparent HugePages=always | Pagine di memoria da 2MB | −TLB miss |
| `vm.swappiness=10` | Usa la RAM, non la swap | −latenza I/O |
| `kernel.nmi_watchdog=0` | Disabilita watchdog NMI | −interrupt spurii |

## Installazione

```bash
# Copia il file di servizio
sudo cp cpu-governor.service /etc/systemd/system/

# Abilita e avvia
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-governor.service

# Verifica
systemctl status cpu-governor.service
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# → performance
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
# → 3493000  (o il valore max del tuo SoC)
```

## Ripristino rapido

```bash
sudo systemctl stop cpu-governor.service
# → torna automaticamente a schedutil + impostazioni default
```

## ⚠️ Note importanti

- Con tutti i core fissi al massimo, **la temperatura in idle salirà di ~5-10°C** rispetto a schedutil. Monitora con `watch -n1 sensors`.
- L'IRQ pinning su core 0 è aggressivo: se noti instabilità audio o input lag, commenta il blocco `# 5` nel `.service`.
- `THP=always` può aumentare il consumo di RAM nei workload con molte piccole allocazioni. Per uso gaming-only è ottimale.
- Il servizio si auto-ripristina allo stop: `systemctl stop` riporta tutto ai default SteamOS.
