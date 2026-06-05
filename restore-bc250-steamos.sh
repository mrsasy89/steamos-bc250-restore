#!/usr/bin/env bash
# restore-bc250-steamos.sh
# ============================================================
# Ripristino post-update SteamOS per AMD BC-250 / Cyan Skillfish
# ============================================================
# Cosa fa questo script:
#   1. Fix ACPI P-States/C-States via mkinitcpio hook (acpi_override)
#   2. Rimozione cpu-performance.service (incompatibile con P-States ACPI)
#   3. CPU governor schedutil persistente via systemd
#   4. Installazione bc250_smu_oc via Python venv (pip non disponibile su SteamOS)
#   5. Installazione cyan-skillfish-governor-smu (binario precompilato v0.4.6)
#   6. Policy D-Bus per com.cyan.SkillFishGovernor
#
# LEZIONI APPRESE (critiche):
#   - cpu-performance.service NON va usato con P-States ACPI attivi → artefatti GPU
#   - acpi_override va nel drop-in /etc/mkinitcpio.conf.d/20-steamdeck.conf, NON in mkinitcpio.conf principale
#   - NON modificare grub.cfg per ACPI — il path /boot/ è relativo alla btrfs, non alla EFI
#   - modprobe.d è ignorato — parametri amdgpu solo in grub.cfg
#   - steamos-readonly disable prima di qualsiasi modifica
#   - Crash hard corrompono il prefix Proton — cancellare shadercache e compatdata prima di ritestare
#   - Governor corretto: schedutil — SteamOS lo gestisce nativamente con P-Stati
#   - pip non è disponibile su SteamOS Python 3.13 — usare python -m venv
#   - pacman-key --populate holo necessario per firme Valve/SteamOS
#   - bc250-apply non è nel PATH del venv — usare path completo o alias
#   - scaling_available_frequencies mostra solo P-States ACPI, non l'OC SMU
#   - sudo systemctl restart dbus su SteamOS congela il sistema — usare reboot
#   - install.sh di cyan-skillfish-governor NON include scripts/ nel tar v0.4.6
#     → installazione manuale necessaria, policy D-Bus va creata a mano
#   - D-Bus policy va in /etc/dbus-1/system.d/ (non /usr/share/dbus-1/system.d/)
#
# Hardware supportato: AMD BC-250 / Cyan Skillfish (PCI_ID: 1002:13FE)
# Testato su: SteamOS 3.9 Holo — Kernel 6.18.x-neptune-618
# Governor SMU validato con: CP2077, Resident Evil 4 Remake — stabile, nessun crash
#
# https://github.com/mrsasy89/steamos-bc250-restore
# ============================================================

set -euo pipefail

# --- Configurazione ---
BC250_REPO="https://github.com/bc250-collective/bc250_smu_oc.git"
# cyan-skillfish-governor-smu: preferire il binario precompilato dal tag v0.4.6
# Il ramo smu richiede cargo (build lenta ~15min su BC-250)
CSG_RELEASE_URL="https://github.com/filippor/cyan-skillfish-governor/releases/download/v0.4.6/cyan-skillfish-governor-smu-v0.4.6-x86_64-linux.tar.gz"
CSG_REPO="https://github.com/filippor/cyan-skillfish-governor.git"
CSG_BRANCH="smu"
WORKDIR="${HOME}/fix"
VENV_DIR="${HOME}/.venv/bc250"

DBUS_POLICY_DIR="/etc/dbus-1/system.d"
DBUS_POLICY_FILE="${DBUS_POLICY_DIR}/com.cyan.SkillFishGovernor.conf"
CSG_INSTALL_DIR="/etc/cyan-skillfish-governor-smu"
CSG_BIN="${CSG_INSTALL_DIR}/cyan-skillfish-governor-smu"
CSG_CONFIG="${CSG_INSTALL_DIR}/config.toml"
CSG_SERVICE="/etc/systemd/system/cyan-skillfish-governor-smu.service"
CPU_PERF_SERVICE="/etc/systemd/system/cpu-performance.service"
CPU_GOV_SERVICE="/etc/systemd/system/cpu-governor.service"
BC250_SERVICE="/etc/systemd/system/bc250-smu-oc.service"
BC250_CONF="/etc/bc250-smu-oc.conf"

# ACPI fix
ACPI_SRC_DIR="${HOME}/fix/bc250-acpi-fix"
ACPI_INITCPIO_DIR="/etc/initcpio/acpi_override"
MKINITCPIO_DROPIN="/etc/mkinitcpio.conf.d/20-steamdeck.conf"
KERNEL_PRESET="/etc/mkinitcpio.d/linux-neptune-618.preset"

# Profilo OC CPU stabile (verificato su Cyan Skillfish)
OC_FREQ=4000
OC_VID=1275
OC_TEMP=90

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

# --- Verifica unità systemd ---
have_unit() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

# --- Prerequisiti ---
ensure_tools() {
  log "Verifica prerequisiti"

  # Inizializza keyring SteamOS (holo) — necessario per pacman su SteamOS
  if ! pacman-key --list-keys 2>/dev/null | grep -q "steamos.cloud"; then
    log "Inizializzazione keyring SteamOS (holo)"
    sudo pacman-key --init
    sudo pacman-key --populate holo
    ok "Keyring holo inizializzato"
  else
    ok "Keyring holo già presente"
  fi

  for cmd in git python3 curl tar; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$cmd trovato: $(command -v $cmd)"
    else
      err "$cmd non trovato. Installalo prima di continuare."
    fi
  done

  # stress è necessario per bc250_detect.py (stress test durante autotuning)
  if ! command -v stress >/dev/null 2>&1; then
    log "Installazione stress (richiesto da bc250_detect.py)"
    sudo pacman -S stress --noconfirm
    ok "stress installato"
  else
    ok "stress trovato: $(command -v stress)"
  fi
}

# --- Python venv per bc250_smu_oc ---
# SteamOS usa Python 3.13 con PEP 668 — pip --break-system-packages NON funziona.
# Il metodo corretto è un virtualenv in home (sopravvive agli update SteamOS).
setup_venv() {
  log "Configurazione Python venv in ${VENV_DIR}"

  if [[ -f "${VENV_DIR}/bin/python3" ]]; then
    ok "venv già presente in ${VENV_DIR}"
  else
    python3 -m venv "${VENV_DIR}"
    ok "venv creato in ${VENV_DIR}"
  fi
}

# --- Policy D-Bus ---
# NOTA: NON eseguire 'sudo systemctl restart dbus' su SteamOS — congela il sistema.
# La policy viene caricata al prossimo riavvio.
apply_dbus_policy() {
  log "Applico policy D-Bus per com.cyan.SkillFishGovernor"
  sudo mkdir -p "$DBUS_POLICY_DIR"
  sudo tee "$DBUS_POLICY_FILE" >/dev/null <<'DBUSEOF'
<!DOCTYPE busconfig PUBLIC
  "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="root">
    <allow own="com.cyan.SkillFishGovernor"/>
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow receive_sender="com.cyan.SkillFishGovernor"/>
  </policy>

  <policy context="default">
    <allow send_destination="com.cyan.SkillFishGovernor"/>
    <allow send_interface="com.cyan.SkillFishGovernor.PerformanceMode"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
DBUSEOF
  ok "Policy D-Bus scritta in ${DBUS_POLICY_FILE}"
  warn "La policy D-Bus verrà caricata al prossimo riavvio (NON eseguire systemctl restart dbus)"
}

# ---------------------------------------------------------------------------
# Fix ACPI override (P-States / C-States BC-250)
# ---------------------------------------------------------------------------
install_acpi_fix() {
  log "Fix ACPI override per P-States/C-States BC-250 (via mkinitcpio hook)"

  if [[ ! -d "$ACPI_SRC_DIR" ]] || ! ls "$ACPI_SRC_DIR"/*.aml >/dev/null 2>&1; then
    warn "Directory ${ACPI_SRC_DIR} non trovata o senza file .aml — salto fix ACPI"
    warn "Assicurati di avere i file .aml compilati in ${ACPI_SRC_DIR}/"
    warn "Puoi clonarli da: https://github.com/bc250-collective/bc250-acpi-fix"
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
      ok "Hook acpi_override già presente in ${MKINITCPIO_DROPIN}"
    else
      log "Aggiungo hook acpi_override al drop-in ${MKINITCPIO_DROPIN}"
      sudo sed -i 's/^HOOKS=(/HOOKS=(acpi_override /' "$MKINITCPIO_DROPIN"
      ok "Drop-in aggiornato"
    fi
  else
    warn "${MKINITCPIO_DROPIN} non trovato — aggiorno il preset direttamente"
    if grep -q "acpi_override" "$KERNEL_PRESET"; then
      ok "Hook acpi_override già presente nel preset"
    else
      sudo sed -i 's/^HOOKS=(/HOOKS=(acpi_override /' "$KERNEL_PRESET"
      ok "Preset aggiornato"
    fi
  fi

  log "Rigenero initramfs con hook acpi_override"
  sudo mkinitcpio -p linux-neptune-618

  sudo steamos-readonly enable

  ok "Fix ACPI completato — riavvio necessario per attivare le tabelle"
}

# ---------------------------------------------------------------------------
# Rimozione cpu-performance.service
# CRITICO: incompatibile con P-States ACPI → artefatti GPU e cali FPS
# ---------------------------------------------------------------------------
remove_cpu_performance_service() {
  log "Verifica e rimozione cpu-performance.service"

  if have_unit "cpu-performance.service" || [[ -f "$CPU_PERF_SERVICE" ]]; then
    warn "cpu-performance.service trovato — rimozione in corso"
    sudo systemctl stop cpu-performance.service 2>/dev/null || true
    sudo systemctl disable cpu-performance.service 2>/dev/null || true
    sudo rm -f "$CPU_PERF_SERVICE"
    sudo systemctl daemon-reload
    ok "cpu-performance.service rimosso"
  else
    ok "cpu-performance.service non presente"
  fi
}

# ---------------------------------------------------------------------------
# CPU governor schedutil persistente
# ---------------------------------------------------------------------------
install_cpu_governor() {
  log "Configurazione CPU governor schedutil persistente"

  if have_unit "cpu-governor.service" && grep -q "schedutil" "$CPU_GOV_SERVICE" 2>/dev/null; then
    ok "cpu-governor.service già configurato con schedutil"
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
    ok "schedutil attivo su tutti i ${core_count} core"
  fi
}

# ---------------------------------------------------------------------------
# Installazione bc250_smu_oc
# ---------------------------------------------------------------------------
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

  setup_venv

  log "Installo bc250_smu_oc nel venv"
  "${VENV_DIR}/bin/pip" install "$WORKDIR/bc250_smu_oc/"

  ok "bc250_smu_oc installato nel venv ${VENV_DIR}"
  "${VENV_DIR}/bin/python3" -c "import bc250_smu; print('bc250_smu import OK')"

  if [[ -f "$BC250_CONF" ]]; then
    log "Configurazione OC trovata in ${BC250_CONF} — applico profilo"
    sudo "${VENV_DIR}/bin/python3" "$WORKDIR/bc250_smu_oc/bc250_apply.py" \
      --apply --install "$BC250_CONF"
    sudo systemctl daemon-reload
    sudo systemctl enable --now bc250-smu-oc.service
    ok "Profilo OC applicato e servizio abilitato al boot"
  else
    echo ""
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${YELLOW}  Nessun profilo OC trovato in ${BC250_CONF}${NC}\n"
    printf "${YELLOW}  Esegui prima il detect per trovare il tuo profilo stabile:${NC}\n"
    printf "${YELLOW}${NC}\n"
    printf "${YELLOW}  sudo ${VENV_DIR}/bin/python3 ${WORKDIR}/bc250_smu_oc/bc250_detect.py \\\n"
    printf "${YELLOW}    -f ${OC_FREQ} -v ${OC_VID} -t ${OC_TEMP} -k -c ${BC250_CONF}${NC}\n"
    printf "${YELLOW}${NC}\n"
    printf "${YELLOW}  Profilo di riferimento: ${OC_FREQ} MHz @ ${OC_VID} mV, ${OC_TEMP}°C${NC}\n"
    printf "${YELLOW}  ATTENZIONE: ogni chip è diverso — NON eccedere 1300 mV${NC}\n"
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
  fi
}

# ---------------------------------------------------------------------------
# Installazione cyan-skillfish-governor-smu (binario precompilato)
#
# METODO PREFERITO: binario precompilato v0.4.6 da GitHub Releases
# Il tar v0.4.6 NON include scripts/ → install.sh fallisce su cp scripts/...
# Installazione manuale necessaria (come documentato in questo script)
#
# ALTERNATIVA: compilare dal sorgente (ramo smu) con cargo
#   → lento su BC-250 (~15min), richiede cargo installato
#
# NOTA D-Bus: NON eseguire 'systemctl restart dbus' — congela SteamOS
#   La policy viene caricata automaticamente al riavvio
# ---------------------------------------------------------------------------
install_csg() {
  log "Installazione cyan-skillfish-governor-smu v0.4.6 (binario precompilato)"
  mkdir -p "$WORKDIR"

  local TAR_NAME="cyan-skillfish-governor-smu-v0.4.6-x86_64-linux"
  local TAR_PATH="${WORKDIR}/${TAR_NAME}.tar.gz"
  local EXTRACT_DIR="${WORKDIR}/${TAR_NAME}"

  # Scarica se non già presente
  if [[ ! -f "$TAR_PATH" ]]; then
    log "Download binario precompilato v0.4.6"
    curl -L -o "$TAR_PATH" "$CSG_RELEASE_URL"
  else
    ok "Archivio già presente: ${TAR_PATH}"
  fi

  # Estrai
  if [[ ! -d "$EXTRACT_DIR" ]]; then
    log "Estrazione archivio"
    tar -xzf "$TAR_PATH" -C "$WORKDIR"
  else
    ok "Directory già estratta: ${EXTRACT_DIR}"
  fi

  # Installazione manuale (install.sh fallisce su scripts/ mancante)
  log "Installazione binario in ${CSG_INSTALL_DIR}"
  sudo mkdir -p "$CSG_INSTALL_DIR"
  sudo cp "${EXTRACT_DIR}/cyan-skillfish-governor-smu" "$CSG_BIN"
  sudo chmod +x "$CSG_BIN"

  # Config: non sovrascrivere se già presente (configurazione utente)
  if [[ ! -f "$CSG_CONFIG" ]]; then
    log "Copio config.toml di default"
    sudo cp "${EXTRACT_DIR}/config.toml" "$CSG_CONFIG"
    ok "config.toml installato in ${CSG_CONFIG}"
    warn "Edita ${CSG_CONFIG} con il profilo validato (vedi config.toml nel repo)"
  else
    ok "config.toml già presente — mantengo configurazione utente"
  fi

  # Policy D-Bus
  apply_dbus_policy

  # Service file
  log "Creo service file systemd"
  sudo tee "$CSG_SERVICE" >/dev/null <<SERVICEEOF
[Unit]
Description=Cyan Skillfish GPU Governor
After=multi-user.target

[Service]
Type=simple
ExecStart=${CSG_BIN} ${CSG_CONFIG}
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now cyan-skillfish-governor-smu.service

  ok "cyan-skillfish-governor-smu installato e avviato"
  echo ""
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${YELLOW}  Config attivo: ${CSG_CONFIG}${NC}\n"
  printf "${YELLOW}  Profilo validato: min=1000, max=2000 MHz${NC}\n"
  printf "${YELLOW}  Safe-points: 1000/800mV → 1175/850 → 1500/900 → 1700/920 → 1850/930 → 2000/960mV${NC}\n"
  printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  echo ""
}

# --- Verifica finale servizi ---
verify_services() {
  log "Verifica finale stato servizi"
  echo ""

  printf "${BLUE}--- cyan-skillfish-governor-smu.service -------------------${NC}\n"
  systemctl status cyan-skillfish-governor-smu.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- bc250-smu-oc.service ----------------------------------${NC}\n"
  systemctl status bc250-smu-oc.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- cpu-governor.service ----------------------------------${NC}\n"
  systemctl status cpu-governor.service --no-pager -l 2>/dev/null || true

  echo ""
  printf "${BLUE}--- Governor CPU attivo -----------------------------------${NC}\n"
  echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
  echo "Freq corrente core0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf "%.0f MHz", $1/1000}' || echo 'N/A')"
  echo ""
  printf "${YELLOW}NOTA: scaling_available_frequencies mostra solo P-States ACPI (max 3200 MHz).${NC}\n"
  printf "${YELLOW}      L'OC SMU agisce a livello hardware — verificare la frequenza reale${NC}\n"
  printf "${YELLOW}      con /proc/cpuinfo sotto carico o con il monitor in-game.${NC}\n"

  echo ""
  printf "${BLUE}--- P-States / C-States CPU (ACPI override) ---------------${NC}\n"
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]]; then
    echo "P-States ACPI: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)"
    echo "C-States:      $(ls /sys/devices/system/cpu/cpu0/cpuidle/ 2>/dev/null | tr '\n' ' ')"
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
  printf "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}\n"
  printf "${BLUE}║   SteamOS BC-250 Restore — AMD BC-250 / Cyan Skillfish   ║${NC}\n"
  printf "${BLUE}║   https://github.com/mrsasy89/steamos-bc250-restore      ║${NC}\n"
  printf "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}\n"
  echo ""

  ensure_tools
  install_acpi_fix
  remove_cpu_performance_service
  install_cpu_governor

  # bc250_smu_oc (CPU OC)
  if have_unit "bc250-smu-oc.service"; then
    ok "bc250-smu-oc.service presente — riciclo configurazione"
    if [[ -f "$BC250_CONF" ]]; then
      setup_venv
      if [[ -d "$WORKDIR/bc250_smu_oc" ]]; then
        sudo "${VENV_DIR}/bin/python3" "$WORKDIR/bc250_smu_oc/bc250_apply.py" \
          --apply "$BC250_CONF" || warn "Impossibile riapplicare OC — riavvia il servizio manualmente"
        ok "Profilo OC CPU riapplicato"
      fi
    fi
  else
    warn "bc250-smu-oc.service NON trovato: avvio installazione"
    install_bc250
  fi

  # cyan-skillfish-governor-smu (GPU governor)
  if have_unit "cyan-skillfish-governor-smu.service"; then
    ok "cyan-skillfish-governor-smu.service presente"
    log "Aggiorno policy D-Bus (sicurezza post-update)"
    apply_dbus_policy
    sudo systemctl restart cyan-skillfish-governor-smu.service
    ok "Governor GPU riavviato"
  else
    warn "cyan-skillfish-governor-smu.service NON trovato: avvio installazione"
    install_csg
  fi

  verify_services

  echo ""
  printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
  printf "${GREEN}║   Ripristino completato!                                 ║${NC}\n"
  printf "${GREEN}║                                                          ║${NC}\n"
  printf "${GREEN}║   Se è il primo avvio o dopo update, riavvia per         ║${NC}\n"
  printf "${GREEN}║   attivare le tabelle ACPI e la policy D-Bus.            ║${NC}\n"
  printf "${GREEN}║                                                          ║${NC}\n"
  printf "${GREEN}║   Prossimi step:                                         ║${NC}\n"
  printf "${GREEN}║   → Tuning governor per target 60fps stabili             ║${NC}\n"
  printf "${GREEN}║   → Step futuro: sblocco 40 CU                          ║${NC}\n"
  printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
  echo ""
}

main "$@"
