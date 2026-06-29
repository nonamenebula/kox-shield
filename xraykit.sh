#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   KOX Shield — Remote Installer (Mac / PC → Keenetic)             ║
# ║   Запускает актуальный install.sh на роутере через SSH          ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Запуск: chmod +x xraykit.sh && ./xraykit.sh
# Альтернатива (на роутере напрямую):
#   wget -O /tmp/kox-install.sh https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh && sh /tmp/kox-install.sh

set -euo pipefail

GITHUB_RAW="https://raw.githubusercontent.com/nonamenebula/kox-shield/main"
INSTALL_URL="${GITHUB_RAW}/install.sh"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
BOLD='\033[1m'; M='\033[0;35m'

ok()   { echo -e " ${G}✓${N}  $*"; }
fail() { echo -e " ${R}✗${N}  $*"; }
info() { echo -e " ${Y}→${N}  $*"; }
warn() { echo -e " ${Y}⚠${N}  $*"; }
die()  { echo -e "\n ${R}ОШИБКА:${N} $*\n"; exit 1; }
sep()  { echo -e "  ${B}────────────────────────────────────────────────${N}"; }

banner() {
  clear
  echo ""
  echo -e "${B}"
  echo '  ██╗  ██╗ ██████╗ ██╗  ██╗   ██╗   ██╗██████╗ ███╗   ██╗'
  echo '  ██║ ██╔╝██╔═══██╗╚██╗██╔╝   ██║   ██║██╔══██╗████╗  ██║'
  echo '  █████╔╝ ██║   ██║ ╚███╔╝    ██║   ██║██████╔╝██╔██╗ ██║'
  echo '  ██╔═██╗ ██║   ██║ ██╔██╗    ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║'
  echo '  ██║  ██╗╚██████╔╝██╔╝ ██╗    ╚████╔╝ ██║     ██║ ╚████║'
  echo '  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝     ╚═══╝  ╚═╝     ╚═╝  ╚═══╝'
  echo -e "${N}"
  echo -e "  ${W}VPN для Keenetic (VLESS + Hysteria2)${N}"
  echo -e "  ${M}★${N} ${C}https://kox.nonamenebula.ru${N}"
  echo -e "  ${M}★${N} Telegram: ${C}@PrivateProxyKox${N}  Бот: ${C}@kox_nonamenebula_bot${N}"
  sep
  echo ""
}

router() {
  sshpass -p "$ROUTER_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -p "${ROUTER_SSH_PORT:-222}" "root@${ROUTER_IP}" "$@" 2>/dev/null
}

router_tty() {
  sshpass -p "$ROUTER_PASS" ssh -tt \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -p "${ROUTER_SSH_PORT:-222}" "root@${ROUTER_IP}" "$@" 2>/dev/null
}

phase_deps() {
  info "[1/4] Проверка зависимостей на этом компьютере"
  command -v curl &>/dev/null || die "curl не найден"
  ok "curl"
  if ! command -v sshpass &>/dev/null; then
    warn "sshpass не найден — нужен для автоматического SSH"
    echo -e " ${C}?${N}  Установить через Homebrew? [Y/n]: "
    read -r REPLY
    if [[ "${REPLY,,}" != "n" ]]; then
      command -v brew &>/dev/null || die "Установите sshpass вручную: brew install hudochenkov/sshpass/sshpass"
      brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 || die "Не удалось установить sshpass"
      ok "sshpass установлен"
    else
      die "sshpass обязателен для удалённой установки"
    fi
  else
    ok "sshpass"
  fi
}

phase_router_input() {
  info "[2/4] Подключение к роутеру Keenetic"
  echo ""
  echo -e "  ${W}IP роутера${N} (обычно 192.168.1.1):"
  read -r ROUTER_IP
  ROUTER_IP="${ROUTER_IP:-192.168.1.1}"
  echo -e "  ${W}SSH-порт${N} (Keenetic Entware: 222):"
  read -r ROUTER_SSH_PORT
  ROUTER_SSH_PORT="${ROUTER_SSH_PORT:-222}"
  echo -e "  ${W}Пароль root${N} (Entware SSH):"
  read -rs ROUTER_PASS
  echo ""
  [ -n "$ROUTER_PASS" ] || die "Пароль не может быть пустым"
}

phase_connect() {
  info "[3/4] Проверка SSH и Entware на роутере"
  router "echo ok" | grep -q ok || die "Не удалось подключиться по SSH к root@${ROUTER_IP}:${ROUTER_SSH_PORT}"
  ok "SSH подключение работает"
  router "[ -f /opt/bin/opkg ]" || die "Entware не установлен на роутере (/opt/bin/opkg отсутствует)"
  ok "Entware найден"
}

phase_install() {
  info "[4/4] Установка KOX Shield на роутере"
  echo ""
  warn "Сейчас на роутере запустится официальный install.sh с GitHub."
  warn "Понадобится ввести URL подписки или vless:// / hysteria2:// ссылку."
  echo ""
  sep
  echo -e "  ${W}Команда на роутере:${N}"
  echo -e "  ${C}wget -O /tmp/kox-install.sh ${INSTALL_URL} && sh /tmp/kox-install.sh${N}"
  sep
  echo ""

  router_tty "wget -q -O /tmp/kox-install.sh '${INSTALL_URL}' && sh /tmp/kox-install.sh" || \
    die "Установка на роутере завершилась с ошибкой"

  echo ""
  sep
  ok "Установка завершена!"
  sep
  echo ""
  echo -e "  ${W}Дальше на роутере:${N}"
  echo -e "  ${G}ssh root@${ROUTER_IP} -p ${ROUTER_SSH_PORT}${N}"
  echo -e "  ${G}kox status${N}          — проверить VPN"
  echo -e "  ${G}kox upgrade${N}         — обновить до последней версии"
  echo -e "  ${G}kox bot-setup${N}       — настроить Telegram-бота"
  echo ""
  echo -e "  ${M}★${N} Поддержка: ${C}https://t.me/PrivateProxyKox${N}"
  echo ""
}

trap 'echo -e "\n${Y}[KOX Shield] Прервано.${N}"; exit 1' INT TERM

banner
phase_deps
phase_router_input
phase_connect
phase_install
