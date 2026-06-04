#!/usr/bin/env bash
# restore-bc250-steamos.sh
# Ripristino post-update SteamOS per bc250_smu_oc e cyan-skillfish-governor-smu
# + Fix ACPI override per P-States/C-States su AMD BC-250 / Cyan Skillfish
# Lenovo Legion Go - AMD BC-250 / Cyan Skillfish
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

# ACPI fix
ACPI_SRC_DIR="${HOME}/bc250-acpi-fix"
ACPI_CPIO="/boot/acpi_override.cpio"
GRUB_CUSTOM_CFG="/efi/EFI/steamos/custom.cfg"
# UUID della partizione root BTRFS di SteamOS (da non modificare)
STEAMOS_ROOT_UUID="a80835cd-019a-4e51-a668-941409c6b0ee"

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
  for cmd in git python3 cargo cpio; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$cmd trovato: $(command -v $cmd)"
    else
      err "$cmd non trovato. Installalo prima di continuare."
    fi
  done
  command -v pipx >/dev/null 2>&1 && ok "pipx trovato" || warn "pipx non trovato: userò pip --break-system-packages"
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

# --- Fix ACPI override (P-States / C-States BC-250) ---
install_acpi_fix() {
  log "Fix ACPI override per P-States/C-States BC-250"

  # Verifica che esistano file .aml nella directory sorgente
  if [[ ! -d "$ACPI_SRC_DIR" ]] || ! ls "$ACPI_SRC_DIR"/*.aml >/dev/null 2>&1; then
    warn "Directory ${ACPI_SRC_DIR} non trovata o senza file .aml — salto fix ACPI"
    warn "Assicurati di avere i file .aml compilati in ~/bc250-acpi-fix/"
    return 0
  fi

  # Costruisci il CPIO
  log "Costruisco acpi_override.cpio"
  local tmp_acpi
  tmp_acpi="$(mktemp -d)"
  mkdir -p "${tmp_acpi}/kernel/firmware/acpi"
  cp "$ACPI_SRC_DIR"/*.aml "${tmp_acpi}/kernel/firmware/acpi/"
  ( cd "$tmp_acpi" && find kernel | cpio -H newc --create > "${tmp_acpi}/acpi_override.cpio" )
  local cpio_size
  cpio_size=$(du -h "${tmp_acpi}/acpi_override.cpio" | cut -f1)
  ok "CPIO creato: ${cpio_size}"

  # Copia in /boot (BTRFS, accessibile da GRUB)
  log "Copio acpi_override.cpio in /boot"
  sudo steamos-readonly disable
  sudo install -m 644 "${tmp_acpi}/acpi_override.cpio" "$ACPI_CPIO"
  sudo steamos-readonly enable
  ok "Installato: ${ACPI_CPIO} ($(du -h $ACPI_CPIO | cut -f1))"
  rm -rf "$tmp_acpi"

  # Crea/aggiorna custom.cfg GRUB (menu nascosto, avvio silenzioso)
  log "Aggiorno GRUB custom.cfg con voce ACPI fix (menu nascosto)"

  # Recupera il kernel attivo
  local kernel_ver
  kernel_ver=$(ls /boot/vmlinuz-* 2>/dev/null | head -1 | xargs basename | sed 's/vmlinuz-//')
  if [[ -z "$kernel_ver" ]]; then
    warn "Impossibile rilevare versione kernel — uso linux-neptune-618 come default"
    kernel_ver="linux-neptune-618"
  fi
  ok "Kernel rilevato: ${kernel_ver}"

  sudo tee "$GRUB_CUSTOM_CFG" >/dev/null <<GRUBEOF
# ACPI override BC-250 — generato da restore-bc250-steamos.sh
# Menu nascosto: timeout=0. Per mostrare il menu al prossimo avvio:
#   sudo grub-editenv /efi/EFI/steamos/grubenv set menu_show_once=y
set timeout=0
set timeout_style=hidden

menuentry 'SteamOS + ACPI BC-250 Fix' --class steamos {
       load_video
       insmod gzio
       insmod part_gpt
       insmod btrfs
       insmod search_part_uuid
       search --no-floppy --part-uuid --set=root ${STEAMOS_ROOT_UUID}
       steamenv_boot linux /boot/vmlinuz-${kernel_ver} console=tty1 rd.luks=0 rd.lvm=0 rd.md=0 rd.dm=0 rd.systemd.gpt_auto=no log_buf_len=4M amd_iommu=off amdgpu.lockup_timeout=5000,10000,10000,5000 ttm.pages_min=2097152 amdgpu.sched_hw_submission=4 amdgpu.dcdebugmask=0x20000 audit=0 fbcon=vc:4-6 fsck.mode=auto fsck.repair=preen crashkernel=256M crash_kexec_post_notifiers loglevel=3 quiet splash plymouth.ignore-serial-consoles
       initrd /boot/amd-ucode.img /boot/acpi_override.cpio /boot/initramfs-${kernel_ver}.img
}
GRUBEOF

  ok "GRUB custom.cfg aggiornato: ${GRUB_CUSTOM_CFG}"

  # Verifica P-States attivi (solo se siamo già bootati con il fix)
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]]; then
    local freqs
    freqs=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)
    ok "P-States attivi: ${freqs}"
  else
    warn "P-States non rilevati — riavvia e seleziona 'SteamOS + ACPI BC-250 Fix' dal menu GRUB"
    warn "Per mostrare il menu una volta: sudo grub-editenv /efi/EFI/steamos/grubenv set menu_show_once=y"
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
  printf "${BLUE}--- Journal cyan-skillfish-governor-smu (ultimi 20 log) ---${NC}\n"
  journalctl -u cyan-skillfish-governor-smu.service -n 20 --no-pager 2>/dev/null || true

  echo ""
  printf "${BLUE}--- P-States CPU (ACPI fix) --------------------------------${NC}\n"
  if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]]; then
    echo "Frequenze disponibili: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies)"
    echo "Governor attivo:       $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    echo "C-States:              $(ls /sys/devices/system/cpu/cpu0/cpuidle/ 2>/dev/null | tr '\n' ' ')"
  else
    warn "P-States non attivi — ACPI fix non ancora caricato (riavvio necessario)"
  fi
}

# --- Main ---
main() {
  echo ""
  printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
  printf "${BLUE}║   SteamOS BC-250 Restore - Lenovo Legion Go          ║${NC}\n"
  printf "${BLUE}║   https://github.com/mrsasy89/steamos-bc250-restore  ║${NC}\n"
  printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
  echo ""

  ensure_tools

  # --- Fix ACPI (P-States/C-States) ---
  install_acpi_fix

  # --- bc250_smu_oc ---
  if have_unit "bc250-smu-oc.service"; then
    ok "bc250-smu-oc.service presente - nessuna reinstallazione necessaria"
  else
    warn "bc250-smu-oc.service NON trovato: avvio installazione"
    install_bc250
  fi

  # --- cyan-skillfish-governor-smu ---
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
