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
#   5. Installazione cyan-skillfish-governor-smu (ramo smu)
#   6. Policy D-Bus per com.cyan.SkillFishGovernor
#
# LEZIONI APPRESE (critiche):
#   - cpu-performance.service NON va usato con P-States ACPI attivi → artefatti GPU
#   - acpi_override va nel drop-in /etc/mkinitcpio.conf.d/20-steamdeck.conf, NON in mkinitcpio.conf principale
#   - NON modificare grub.cfg per ACPI — il path /boot/ è relativo alla btrfs, non alla EFI
#   - modprobe.d è ignorato — parametri amdgpu solo in grub.cfg
#   - steamos-readonly disable prima di qualsiasi modifica
#   - Crash hard corrompono il prefix Proton — cancellare shadercache e compatdata prima di ritestare
#   - Governor corretto: schedutil — SteamOS lo gestisce nativamente con P-States
#   - pip non è disponibile su SteamOS Python 3.13 — usare python -m venv
#   - pacman-key --populate holo necessario per firme Valve/SteamOS
#   - bc250-apply non è nel PATH del venv — usare path completo o alias
#   - scaling_available_frequencies mostra solo P-States ACPI, non l'OC SMU
#
# Hardware supportato: AMD BC-250 / Cyan Skillfish (PCI_ID: 1002:13FE)
# Testato su: SteamOS 3.9 Holo — Kernel 6.18.x-neptune-618
#
# https://github.com/mrsasy89/steamos-bc250-restore
# ============================================================

set -euo pipefail

# --- Configurazione ---
BC250_REPO="https://github.com/bc250-collective/bc250_smu_oc.git"
CSG_REPO="https://github.com/filippor/cyan-skillfish-governor.git"
CSG_BRANCH="smu"
WORKDIR="${HOME}/fix"
VENV_DIR="${HOME}/.venv/bc250"

DBUS_POLICY_DIR="/usr/share/dbus-1/system.d"
DBUS_POLICY_FILE="${DBUS_POLICY_DIR}/com.cyan.SkillFishGovernor.conf"
CSG_BIN="/usr/local/bin/cyan-skillfish-governor-smu"
CSG_CONFIG_DIR="/etc/cyan-skillfish-governor-smu"
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
  # Le chiavi Arch standard non coprono i pacchetti firmati da Valve
  if ! pacman-key --list-keys 2>/dev/null | grep -q "steamos.cloud"; then
    log "Inizializzazione keyring SteamOS (holo)"
    sudo pacman-key --init
    sudo pacman-key --populate holo
    ok "Keyring holo inizializzato"
  else
    ok "Keyring holo già presente"
  fi

  for cmd in git python3 cargo cpio; do
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
# METODO CORRETTO: hook nativo acpi_override di mkinitcpio nel drop-in
# /etc/mkinitcpio.conf.d/20-steamdeck.conf
#
# NON modificare:
#   - mkinitcpio.conf principale (viene sovrascritto dagli update)
#   - grub.cfg per ACPI (il path /boot/ è relativo alla btrfs, non alla EFI)
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
      ok "Drop-in aggiornato: $(cat $MKINITCPIO_DROPIN)"
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

  ok "Fix ACPI completato — tabelle caricate nel early uncompressed CPIO"

  echo ""
  printf "${YELLOW}Verifica post-riavvio:${NC}\n"
  printf "${YELLOW}  sudo dmesg | grep -i 'Table Upgrade'${NC}\n"
  printf "${YELLOW}  Atteso: install [SSDT- HACK- P_CST3] e install [SSDT- HACK- PSTATES]${NC}\n"
}

# ---------------------------------------------------------------------------
# Rimozione cpu-performance.service
#
# CRITICO: cpu-performance.service imposta P-States manualmente via cpupower
# o simili, causando conflitti con le tabelle ACPI P-States caricate via
# acpi_override. Il risultato sono artefatti GPU e cali FPS in gaming.
# Con SSDT-PST attivo, schedutil gestisce la frequenza correttamente da solo.
# ---------------------------------------------------------------------------
remove_cpu_performance_service() {
  log "Verifica e rimozione cpu-performance.service (incompatibile con P-States ACPI)"

  if have_unit "cpu-performance.service" || [[ -f "$CPU_PERF_SERVICE" ]]; then
    warn "cpu-performance.service trovato — rimozione in corso"
    sudo systemctl stop cpu-performance.service 2>/dev/null || true
    sudo systemctl disable cpu-performance.service 2>/dev/null || true
    sudo rm -f "$CPU_PERF_SERVICE"
    sudo systemctl daemon-reload
    ok "cpu-performance.service rimosso"
  else
    ok "cpu-performance.service non presente — nessuna azione necessaria"
  fi
}

# ---------------------------------------------------------------------------
# CPU governor schedutil persistente
#
# schedutil è il governor corretto con P-States ACPI attivi:
# scala la frequenza in base al carico dello scheduler, ottimale per gaming.
# SteamOS lo gestisce nativamente — non serve cpupower o altri tool.
#
# NOTA: scaling_available_frequencies mostra solo i P-States ACPI (max 3200 MHz).
# L'OC via SMU agisce a livello hardware e bypassa questo limite — è normale.
# Per verificare l'OC reale usare /proc/cpuinfo o il monitor in-game.
# ---------------------------------------------------------------------------
install_cpu_governor() {
  log "Configurazione CPU governor schedutil persistente"

  if have_unit "cpu-governor.service" && grep -q "schedutil" "$CPU_GOV_SERVICE" 2>/dev/null; then
    ok "cpu-governor.service già presente e configurato con schedutil"
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
    ok "schedutil attivo su tutti i ${core_count} core — servizio abilitato al boot"
  fi
}

# ---------------------------------------------------------------------------
# Installazione bc250_smu_oc
#
# NOTA IMPORTANTE su pip in SteamOS:
# SteamOS usa Python 3.13 con PEP 668 — l'ambiente è "externally managed".
# - pip --break-system-packages: BLOCCATO da PEP 668
# - ensurepip --upgrade: BLOCCATO da PEP 668
# - pacman -S python-pipx: richiede keyring holo + non sopravvive agli update
#
# SOLUZIONE CORRETTA: python -m venv ~/.venv/bc250
# Il venv vive nella home — sopravvive agli update SteamOS.
# bc250-apply non è nel PATH di sistema — usare il path completo del venv.
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

  # Verifica import
  "${VENV_DIR}/bin/python3" -c "import bc250_smu; print('bc250_smu import OK')"

  # Applica profilo OC e installa il servizio systemd
  # bc250_apply.py --install genera automaticamente il service file
  # usando il path corretto del venv Python (non un path hardcodato)
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
    printf "${YELLOW}  ATTENZIONE: ogni chip è diverso — il detect verifica il tuo specifico hardware${NC}\n"
    printf "${YELLOW}  NON eccedere 1300 mV per evitare danni alla CPU${NC}\n"
    printf "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo ""
  fi
}

# --- Installazione cyan-skillfish-governor-smu ---
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
  printf "${YELLOW}  Importa il tuo config.toml stabile:${NC}\n"
  printf "${YELLOW}  Profilo stabile: min=1800, max=2000, down-events=60,${NC}\n"
  printf "${YELLOW}                   burst=25, upper=0.75, lower=0.55${NC}\n"
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
  printf "${BLUE}--- Governor CPU attivo -----------------------------------${NC}\n"
  echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
  echo "Freq corrente core0: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null | awk '{printf \"%.0f MHz\", $1/1000}' || echo 'N/A')"
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

  # 0. Prerequisiti e keyring
  ensure_tools

  # 1. Fix ACPI P-States/C-States via mkinitcpio hook
  install_acpi_fix

  # 2. Rimuovi cpu-performance.service (causa artefatti con P-States ACPI)
  remove_cpu_performance_service

  # 3. CPU governor schedutil persistente
  install_cpu_governor

  # 4. bc250_smu_oc (via Python venv — pip non disponibile su SteamOS)
  if have_unit "bc250-smu-oc.service"; then
    ok "bc250-smu-oc.service presente — riciclo configurazione"
    # Riapplica il profilo OC (necessario dopo ogni update SteamOS)
    if [[ -f "$BC250_CONF" ]]; then
      setup_venv
      if [[ -d "$WORKDIR/bc250_smu_oc" ]]; then
        sudo "${VENV_DIR}/bin/python3" "$WORKDIR/bc250_smu_oc/bc250_apply.py" \
          --apply "$BC250_CONF" || warn "Impossibile riapplicare OC — riavvia il servizio manualmente"
        ok "Profilo OC riapplicato"
      fi
    fi
  else
    warn "bc250-smu-oc.service NON trovato: avvio installazione"
    install_bc250
  fi

  # 5. cyan-skillfish-governor-smu
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
  printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
  printf "${GREEN}║   Ripristino completato!                                 ║${NC}\n"
  printf "${GREEN}║                                                          ║${NC}\n"
  printf "${GREEN}║   Se è il primo avvio o dopo update, riavvia per         ║${NC}\n"
  printf "${GREEN}║   attivare le tabelle ACPI caricate nell'initramfs.      ║${NC}\n"
  printf "${GREEN}║                                                          ║${NC}\n"
  printf "${GREEN}║   Prossimi step:                                         ║${NC}\n"
  printf "${GREEN}║   → Importa config.toml per cyan-skillfish-governor-smu  ║${NC}\n"
  printf "${GREEN}║   → Testa stabilità con CP2077 o altro titolo AAA        ║${NC}\n"
  printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
  echo ""
}

main "$@"
