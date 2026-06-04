#!/usr/bin/env bash
# restore-bc250-steamos.sh
# Ripristino post-update SteamOS per bc250_smu_oc e cyan-skillfish-governor-smu
# + Fix ACPI override per P-States/C-States su AMD BC-250 / Cyan Skillfish
# + CPU governor schedutil persistente via systemd
# AMD BC-250 / Cyan Skillfish su SteamOS
# https://github.com/mrsasy89/steamos-bc250-restore

set -euo pipefail

# --- Configurazione ---
BC250_REPO="https://github.com/bc250-collective/bc250_smu_oc.git"
CSG_REPO="https://github.com/filippor/cyan-skillfish-governor.git"
CSG_BRANCH="smu"
WORKDIR="${HOME}/steamos-bc250-restore-work"
DBUS_POLICY_DIR="/usr/share/dbus-1/system.d"
DBUS_POLICY_FILE="${DBUS_POLICY_DIR}/com.cyan.SkillFishGovernor.conf"
CSG_BIN="/usr/local/bin/cyan-skillfish-governor-smu"
CSG_CONFIG_DIR="/etc/cyan-skillfish-governor-smu"
CSG_SERVICE="/etc/systemd/system/cyan-skillfish-governor-smu.service"
CPU_GOV_SERVICE="/etc/systemd/system/cpu-governor.service"

# ACPI fix — usa hook nativo acpi_override di mkinitcpio
ACPI_SRC_DIR="${HOME}/bc250-acpi-fix"
ACPI_INITCPIO_DIR="/etc/initcpio/acpi_override"
MKINITCPIO_DROPIN="/etc/mkinitcpio.conf.d/20-steamdeck.conf"
KERNEL_PRESET="/etc/mkinitcpio.d/linux-neptune-618.preset"

# --- Colori output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { printf "${BLUE}\n==> %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}\n[WARN] %s${NC}\n" "$*"; }
ok()   { printf "${GREEN}[OK] %s${NC}\n" "$*"; }
err()  { printf "${RED}[ERROR] %s${NC}\n" "$*"; exit 1; }

# --- Verifica unita systemd ---
have_unit() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

# --- Prerequisiti ---
ensure_tools() {
  log "Verifica prerequisiti"
  for cmd in git python3 cargo cpio; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$cmd trovato: $(command -v $cmd)"
    else
      err "$cmd non trovato. Installalo prima di continuare."
    fi
  done
  command -v pipx >/dev/null 2>&1 && ok "pipx trovato" || warn "pipx non trovato: usero pip --break-system-packages"
}

# --- Policy D-Bus ---
apply_dbus_policy() {
  log "Applico policy D-Bus per com.cyan.SkillFishGovernor"
  sudo mkdir -p "$DBUS_POLICY_DIR"
  sudo tee "$DBUS_POLICY_FILE" >/dev/null <<'DBUSEOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="deck">
    <allow own="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyan.SkillFishGovernor"/>
  </policy>
  <policy context="default">
    <allow own="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyan.SkillFishGovernor"/>
  </policy>
</busconfig>
DBUSEOF
  ok "Policy D-Bus scritta in ${DBUS_POLICY_FILE}"
}

# ---------------------------------------------------------------------------
# Fix ACPI override (P-States / C-States BC-250)
#
# NOTA: SteamOS usa steamcl.efi come bootloader primario che bypassa GRUB
# completamente. L'unico metodo affidabile per caricare tabelle ACPI custom
# e incorporarle direttamente nell'initramfs tramite l'hook nativo
# 'acpi_override' di mkinitcpio, che le inserisce nel early uncompressed CPIO.
# ---------------------------------------------------------------------------
install_acpi_fix() {
  log "Fix ACPI override per P-States/C-States BC-250 (via mkinitcpio hook)"

  if [[ ! -d "$ACPI_SRC_DIR" ]] || ! ls "$ACPI_SRC_DIR"/*.aml >/dev/null 2>&1; then
    warn "Directory ${ACPI_SRC_DIR} non trovata o senza file .aml — salto fix ACPI"
    warn "Assicurati di avere i file .aml compilati in ~/bc250-acpi-fix/"
    return 0
  fi

  sudo steamos-readonly disable

  log "Copio file .aml in ${ACPI_INITCPIO_DIR}"
  sudo mkdir -p "$ACPI_INITCPIO_DIR"
  sudo cp "$ACPI_SRC_DIR"/*.aml "$ACPI_INITCPIO_DIR/"
  ok "File .aml copiati:"
  ls -lh "$ACPI_INITCPIO_DIR"/*.aml

  if [[ -f "$MKINITCPIO_DROPIN" ]]; then
    if grep -q "acpi_override" "$MKINITCPIO_DROPIN"; then
      ok "Hook acpi_override gia presente in ${MKINITCPIO_DROPIN}"
    else
      log "Aggiungo hook acpi_override al drop-in ${MKINITCPIO_DROPIN}"
      sudo sed -i 's/^HOOKS=(/HOOKS=(acpi_override /' "$MKINITCPIO_DROPIN"
      ok "Drop-in aggiornato: $(cat $MKINITCPIO_DROPIN)"
    fi
  else
    warn "${MKINITCPIO_DROPIN} non trovato — aggiorno il preset direttamente"
    if grep -q "acpi_override" "$KERNEL_PRESET"; then
      ok "Hook acpi_override gia presente nel preset"
    else
      sudo sed -i 's/^HOOKS=(/HOOKS=(acpi_override /' "$KERNEL_PRESET"
      ok "Preset aggiornato"
    fi
  fi

  log "Rigenero initramfs con hook acpi_override"
  sudo mkinitcpio -p linux-neptune-618

  sudo steamos-readonly enable

  ok "Fix ACPI completato — tabelle caricate nel early uncompressed CPIO"

  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]]; then
    local freqs
    freqs=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)
    ok "P-States attivi: ${freqs}"
  else
    warn "P-States non ancora attivi — riavvia per caricare le nuove tabelle ACPI"
  fi
}

# ---------------------------------------------------------------------------
# CPU governor schedutil persistente
#
# SteamOS non usa /etc/default/cpupower, quindi il metodo corretto e
# un'unita systemd oneshot che imposta il governor su tutti i core al boot.
# schedutil e il governor consigliato con P-States ACPI attivi: scala la
# frequenza in base al carico dello scheduler, ottimale per gaming.
# ---------------------------------------------------------------------------
install_cpu_governor() {
  log "Configurazione CPU governor schedutil persistente"

  if have_unit "cpu-governor.service" && grep -q "schedutil" "$CPU_GOV_SERVICE" 2>/dev/null; then
    ok "cpu-governor.service gia presente e configurato con schedutil"
    return 0
  fi

  sudo tee "$CPU_GOV_SERVICE" >/dev/null <<'GOVEOF'
[Unit]
Description=Set CPU governor to schedutil
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo schedutil > $cpu; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
GOVEOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now cpu-governor.service

  # Verifica
  local all_ok=true
  for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    val=$(cat "$gov")
    if [[ "$val" != "schedutil" ]]; then
      warn "Governor non schedutil su ${gov}: ${val}"
      all_ok=false
    fi
  done

  if $all_ok; then
    local core_count
    core_count=$(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | wc -l)
    ok "schedutil attivo su tutti i ${core_count} core — servizio abilitato al boot"
  fi
}

# --- Installa bc250_smu_oc ---
install_bc250() {
  log "Installazione/Aggiornamento bc250_smu_oc"
  mkdir -p "$WORKDIR"

  if [[ -d "$WORKDIR/bc250_smu_oc/.git" ]]; then
    log "Aggiorno repo esistente bc250_smu_oc"
    git -C "$WORKDIR/bc250_smu_oc" pull --ff-only
  else
    log "Clono bc250_smu_oc"
    git clone "$BC250_REPO" "$WORKDIR/bc250_smu_oc"
  fi

  cd "$WORKDIR/bc250_smu_oc"

  if command -v pipx >/dev/null 2>&1; then
    pipx install . --force
  else
    python3 -m pip install . --break-system-packages
  fi

  ok "bc250_smu_oc installato"
  echo ""
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${YELLOW}  PROMEMORIA: Importa il tuo profilo overclock stabile!${NC}\n"
  printf "${YELLOW}  Profilo testato: 3700 MHz @ 1125 mV${NC}\n"
  printf "${YELLOW}  Vedi: examples/overclock.conf.example nel repo${NC}\n"
  printf "${YELLOW}  Poi esegui: bc250-apply --install ~/overclock.conf${NC}\n"
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  echo ""
}

# --- Installa cyan-skillfish-governor-smu ---
install_csg() {
  log "Installazione/Aggiornamento cyan-skillfish-governor-smu (ramo: ${CSG_BRANCH})"
  mkdir -p "$WORKDIR"

  if [[ -d "$WORKDIR/cyan-skillfish-governor/.git" ]]; then
    log "Aggiorno repo esistente cyan-skillfish-governor"
    git -C "$WORKDIR/cyan-skillfish-governor" fetch origin
    git -C "$WORKDIR/cyan-skillfish-governor" checkout "$CSG_BRANCH"
    git -C "$WORKDIR/cyan-skillfish-governor" pull --ff-only origin "$CSG_BRANCH"
  else
    log "Clono cyan-skillfish-governor (ramo ${CSG_BRANCH})"
    git clone --branch "$CSG_BRANCH" "$CSG_REPO" "$WORKDIR/cyan-skillfish-governor"
  fi

  cd "$WORKDIR/cyan-skillfish-governor"

  log "Compilazione con cargo"
  cargo build --release --bin cyan-skillfish-governor-smu

  log "Installo binario in ${CSG_BIN}"
  sudo install -Dm755 target/release/cyan-skillfish-governor-smu "$CSG_BIN"

  log "Creo file .service systemd"
  sudo tee "$CSG_SERVICE" >/dev/null <<SERVICEEOF
[Unit]
Description=Cyan Skillfish Governor SMU
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=${CSG_BIN}
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SERVICEEOF

  sudo mkdir -p "$CSG_CONFIG_DIR"

  apply_dbus_policy

  sudo systemctl daemon-reload
  sudo systemctl enable cyan-skillfish-governor-smu.service
  sudo systemctl restart cyan-skillfish-governor-smu.service

  ok "cyan-skillfish-governor-smu installato, policy D-Bus applicata, servizio avviato"
  echo ""
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${YELLOW}  PROMEMORIA: Importa il tuo config.toml stabile!${NC}\n"
  printf "${YELLOW}  Config stabile: GPU range 1000..=2000 MHz${NC}\n"
  printf "${YELLOW}  Vedi: examples/config.toml.example nel repo${NC}\n"
  printf "${YELLOW}  Poi esegui:${NC}\n"
  printf "${YELLOW}  sudo cp examples/config.toml.example ${CSG_CONFIG_DIR}/config.toml${NC}\n"
  printf "${YELLOW}  sudo systemctl restart cyan-skillfish-governor-smu.service${NC}\n"
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  echo ""
}

# --- Verifica finale servizi ---
verify_services() {
  log "Verifica finale stato servizi"
  echo ""

  printf "${BLUE}--- bc250-smu-oc.service ----------------------------------${NC}\n"
  systemctl status bc250-smu-oc.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- cyan-skillfish-governor-smu.service -------------------${NC}\n"
  systemctl status cyan-skillfish-governor-smu.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- cpu-governor.service ----------------------------------${NC}\n"
  systemctl status cpu-governor.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- Journal cyan-skillfish-governor-smu (ultimi 20 log) ---${NC}\n"
  journalctl -u cyan-skillfish-governor-smu.service -n 20 --no-pager 2>/dev/null || true

  echo ""
  printf "${BLUE}--- P-States / C-States CPU (ACPI override) ---------------${NC}\n"
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]]; then
    echo "Frequenze disponibili: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)"
    echo "Governor attivo:       $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    echo "Core con schedutil:    $(grep -l schedutil /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | wc -l) / $(ls /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | wc -l)"
    echo "C-States:              $(ls /sys/devices/system/cpu/cpu0/cpuidle/ 2>/dev/null | tr '\n' ' ')"
    echo ""
    printf "${BLUE}--- dmesg ACPI override -----------------------------------${NC}\n"
    dmesg | grep -i "acpi.*override\|SSDT.*PST\|SSDT.*CST\|Table Upgrade" 2>/dev/null || true
  else
    warn "P-States non attivi — ACPI fix non ancora caricato (riavvio necessario)"
  fi
}

# --- Main ---
main() {
  echo ""
  printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
  printf "${BLUE}║   SteamOS BC-250 Restore - AMD BC-250 / Cyan Skillfish ║${NC}\n"
  printf "${BLUE}║   https://github.com/mrsasy89/steamos-bc250-restore  ║${NC}\n"
  printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
  echo ""

  ensure_tools

  # 1. Fix ACPI P-States/C-States via mkinitcpio hook
  install_acpi_fix

  # 2. CPU governor schedutil persistente
  install_cpu_governor

  # 3. bc250_smu_oc
  if have_unit "bc250-smu-oc.service"; then
    ok "bc250-smu-oc.service presente - nessuna reinstallazione necessaria"
  else
    warn "bc250-smu-oc.service NON trovato: avvio installazione"
    install_bc250
  fi

  # 4. cyan-skillfish-governor-smu
  if have_unit "cyan-skillfish-governor-smu.service"; then
    ok "cyan-skillfish-governor-smu.service presente"
    log "Riciclo policy D-Bus (sicurezza post-update)"
    apply_dbus_policy
    sudo systemctl restart cyan-skillfish-governor-smu.service
    ok "Servizio riavviato con policy D-Bus aggiornata"
  else
    warn "cyan-skillfish-governor-smu.service NON trovato: avvio installazione"
    install_csg
  fi

  verify_services

  echo ""
  printf "${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
  printf "${GREEN}║   Ripristino completato!                             ║${NC}\n"
  printf "${GREEN}║   Ricorda di importare i tuoi profili stabili.       ║${NC}\n"
  printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
  echo ""
}

main "$@"
