#!/usr/bin/env bash
# post-update-check.sh
# Controllo rapido stato servizi dopo aggiornamento SteamOS
# NON reinstalla nulla - solo verifica
# https://github.com/mrsasy89/steamos-bc250-restore

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]   %s${NC}\n" "$*"; }
fail() { printf "${RED}[MISS] %s${NC}\n" "$*"; }
info() { printf "${BLUE}[INFO] %s${NC}\n" "$*"; }

have_unit() {
  systemctl list-unit-files "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

check_service() {
  local unit="$1"
  local label="$2"
  if have_unit "$unit"; then
    local state
    state=$(systemctl is-active "$unit" 2>/dev/null || echo "inactive")
    if [[ "$state" == "active" ]]; then
      ok "$label: attivo"
    else
      printf "${YELLOW}[WARN] %s: installato ma non attivo (stato: %s)${NC}\n" "$label" "$state"
    fi
  else
    fail "$label: NON trovato - esegui ./restore-bc250-steamos.sh"
  fi
}

check_dbus_policy() {
  local policy="/usr/share/dbus-1/system.d/com.cyan.SkillFishGovernor.conf"
  if [[ -f "$policy" ]]; then
    ok "Policy D-Bus: presente in $policy"
  else
    fail "Policy D-Bus: MANCANTE - esegui ./restore-bc250-steamos.sh"
  fi
}

check_config() {
  local cfg="/etc/cyan-skillfish-governor-smu/config.toml"
  if [[ -f "$cfg" ]]; then
    ok "config.toml governor: presente"
    info "Range attivo: $(grep -E 'min_freq|max_freq|initial' "$cfg" 2>/dev/null | head -5 || echo 'non leggibile')"
  else
    printf "${YELLOW}[WARN] config.toml governor: MANCANTE - importa il tuo profilo stabile${NC}\n"
    printf "${YELLOW}       Profilo stabile: range 1000..=2000 MHz${NC}\n"
    printf "${YELLOW}       sudo cp examples/config.toml.example /etc/cyan-skillfish-governor-smu/config.toml${NC}\n"
  fi
}

echo ""
printf "${BLUE}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║   SteamOS BC-250 Post-Update Check                   ║${NC}\n"
printf "${BLUE}║   https://github.com/mrsasy89/steamos-bc250-restore  ║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════╝${NC}\n"
echo ""

check_service "bc250-smu-oc.service"                "bc250_smu_oc"
check_service "cyan-skillfish-governor-smu.service" "cyan-skillfish-governor-smu"
check_dbus_policy
check_config

echo ""
printf "${BLUE}--- Journal cyan-skillfish-governor-smu (ultimi 10 log) ---${NC}\n"
journalctl -u cyan-skillfish-governor-smu.service -n 10 --no-pager 2>/dev/null || true
echo ""
printf "${BLUE}--- Journal bc250-smu-oc (ultimi 10 log) ------------------${NC}\n"
journalctl -u bc250-smu-oc.service -n 10 --no-pager 2>/dev/null || true
echo ""
