#!/bin/sh
# KOX Shield Management Console
# https://kox.nonamenebula.ru | t.me/PrivateProxyKox

KOX_VERSION="2026.04.13"

CONF="/opt/etc/xray/config.json"
KOXCONF="/opt/etc/xray/kox.conf"
ERRLOG="/opt/var/log/xray-err.log"
ACCLOG="/opt/var/log/xray-acc.log"
BACKUP_DIR="/opt/etc/xray/backups"
XRAY_INIT="/opt/etc/init.d/S24xray"
BOT_INIT="/opt/etc/init.d/S90kox-bot"
DOMAIN_MARKER="kox-custom-marker"
IP_MARKER="192.0.2.255/32"

R=$(printf '\033[0;31m'); G=$(printf '\033[0;32m'); Y=$(printf '\033[0;33m')
C=$(printf '\033[0;36m'); W=$(printf '\033[1;37m'); N=$(printf '\033[0m')

ok()   { printf " ${G}✓${N}  %s\n" "$*"; }
fail() { printf " ${R}✗${N}  %s\n" "$*"; }
info() { printf " ${C}•${N}  %s\n" "$*"; }
warn() { printf " ${Y}!${N}  %s\n" "$*"; }
sep()  { printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"; }

# OSC 8 clickable hyperlink (works in iTerm2, VSCode, Kitty, etc.)
# Uses BEL (0x07) as OSC terminator to avoid \t escape conflicts
hyperlink() { printf '\033]8;;%s\007%s\033]8;;\007' "$1" "$2"; }

kox_banner() {
  printf "\n"
  printf "${W}  ██╗  ██╗  ██████╗  ██╗  ██╗${N}\n"
  printf "${W}  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝${N}\n"
  printf "${W}  █████╔╝   ██║  ██║  ╚███╔╝ ${N}\n"
  printf "${W}  ██╔═██╗   ██║  ██║  ██╔██╗ ${N}\n"
  printf "${W}  ██║  ██╗  ╚██████╔╝██╔╝ ██╗${N}\n"
  printf "${W}  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝${N}\n"
  printf "\n"
  printf "${C}            ── VPN Console ──${N}\n"
  printf "${C}              v${KOX_VERSION}${N}\n"
  printf "\n"
  printf "  ${C}🌐 $(hyperlink 'https://kox.nonamenebula.ru/register' 'kox.nonamenebula.ru')${N}\n"
  printf "  ${C}📢 $(hyperlink 'https://t.me/PrivateProxyKox' 't.me/PrivateProxyKox')${N}\n"
  printf "  ${C}🤖 $(hyperlink 'https://t.me/kox_nonamenebula_bot' '@kox_nonamenebula_bot')${N}\n"
  sep
}

kox_help() {
  printf " ${W}Команды KOX Shield:${N}\n\n"
  printf "  ${G}kox status${N}           — статус Xray и туннеля\n"
  printf "  ${G}kox on${N}               — включить VPN (iptables)\n"
  printf "  ${G}kox off${N}              — выключить VPN (iptables)\n"
  printf "  ${G}kox restart${N}          — перезапустить Xray\n"
  printf "  ${G}kox test${N}             — проверить конфиг Xray\n"
  printf "  ${G}kox server${N}           — инфо о VLESS сервере\n"
  printf "  ${G}kox stats${N}            — статистика трафика\n\n"
  printf "  ${G}kox add <домен>${N}      — добавить домен в туннель\n"
  printf "  ${G}kox del <домен>${N}      — удалить домен из туннеля\n"
  printf "  ${G}kox check <домен>${N}    — проверить маршрут домена\n"
  printf "  ${G}kox list${N}             — все домены в туннеле\n\n"
  printf "  ${G}kox add-ip <CIDR>${N}    — добавить IP/подсеть в туннель\n"
  printf "  ${G}kox del-ip <CIDR>${N}    — удалить IP/подсеть\n"
  printf "  ${G}kox list-ip${N}          — все IP/подсети\n\n"
  printf "  ${G}kox log${N}              — последние ошибки Xray\n"
  printf "  ${G}kox log-live${N}         — логи в реальном времени\n"
  printf "  ${G}kox clear-log${N}        — очистить логи\n\n"
  printf "  ${G}kox backup${N}           — создать резервную копию\n"
  printf "  ${G}kox restore [файл]${N}   — восстановить из бэкапа\n\n"
  printf "  ${G}kox list-cats${N}                   — список категорий доменов\n"
  printf "  ${G}kox list-load <slug|all>${N}       — загрузить категорию в туннель\n"
  printf "  ${G}kox list-remove <slug|all>${N}     — удалить категорию из туннеля\n"
  printf "  ${G}kox list-check${N}                 — проверить обновления списков\n"
  printf "  ${G}kox list-update${N}                — обновить списки с GitHub\n\n"
  printf "  ${G}kox update-sub${N}       — обновить серверные параметры из подписки\n"
  printf "  ${G}kox cron-on${N}          — авто-обновление (ежедневно 04:00)\n"
  printf "  ${G}kox cron-off${N}         — отключить авто-обновление\n"
  printf "  ${G}kox upgrade${N}          — проверить и установить обновление KOX Shield\n\n"
  printf "  ${G}kox bot${N}              — статус Telegram бота\n"
  printf "  ${G}kox admin set <id>${N}   — назначить Telegram-администратора\n"
  printf "  ${G}kox admin show${N}       — показать текущего администратора\n\n"
  printf "  ${G}kox help${N}             — эта справка\n\n"
}

load_conf() {
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
}

kox_status() {
  kox_banner
  info "Проверка статуса KOX Shield..."
  sep

  # Xray process
  if pgrep xray >/dev/null 2>&1; then
    ok "Xray запущен (PID: $(pgrep xray | head -1))"
  else
    fail "Xray НЕ запущен"
  fi

  # Port
  if netstat -tlnp 2>/dev/null | grep -q 10808; then
    ok "Порт 10808 слушает"
  else
    fail "Порт 10808 не слушает"
  fi

  # IPTables
  if iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT; then
    ok "iptables правила активны"
  else
    warn "iptables правила отсутствуют — VPN может быть отключен"
  fi

  # VPN on/off marker
  if [ -f /tmp/kox-vpn-off ]; then
    warn "VPN выключен командой 'kox off'"
  else
    ok "VPN включен"
  fi

  # Server info
  load_conf
  if [ -n "${KOX_SERVER:-}" ]; then
    info "Сервер: ${W}${KOX_SERVER}:${KOX_PORT:-443}${N}"
  else
    SRV=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')
    PORT=$(grep -m1 '"port"' "$CONF" 2>/dev/null | sed 's/.*"port": *\([0-9]*\).*/\1/')
    [ -n "$SRV" ] && info "Сервер: ${W}${SRV}:${PORT}${N}"
  fi

  # Connectivity
  if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
    ok "Интернет: доступен"
  else
    fail "Интернет: недоступен"
  fi

  # Recent errors
  ERRS=$(tail -5 "$ERRLOG" 2>/dev/null | grep -ic "error\|fail\|reject" || true)
  if [ "${ERRS:-0}" -gt 0 ]; then
    warn "Ошибок в последних строках лога: ${ERRS} (kox log)"
  else
    ok "Критических ошибок в логе нет"
  fi

  info "Версия KOX Shield: ${W}v${KOX_VERSION}${N}"
  sep
}

kox_on() {
  info "Включаю VPN..."
  rm -f /tmp/kox-vpn-off
  NAT_SCRIPT=$(ls /opt/etc/ndm/netfilter.d/*nat.sh 2>/dev/null | head -1)
  if [ -n "$NAT_SCRIPT" ] && sh "$NAT_SCRIPT" 2>/dev/null; then
    ok "iptables правила применены — VPN включен"
  else
    fail "Ошибка применения iptables правил"
  fi
}

kox_off() {
  info "Выключаю VPN (iptables)..."
  touch /tmp/kox-vpn-off
  iptables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -X XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -X XRAY_REDIRECT 2>/dev/null || true
  ok "VPN выключен. Xray продолжает работать, трафик не перенаправляется."
  info "Для включения: ${W}kox on${N}"
}

kox_restart() {
  info "Перезапускаю Xray..."
  "$XRAY_INIT" restart
  sleep 2
  if pgrep xray >/dev/null 2>&1; then
    ok "Xray перезапущен успешно"
  else
    fail "Xray не запустился, проверьте: kox log"
  fi
}

kox_test() {
  info "Проверяю конфигурацию Xray..."
  /opt/sbin/xray -test -config "$CONF" && ok "Конфиг корректен" || fail "Ошибка в конфиге!"
}

kox_server() {
  kox_banner
  load_conf
  info "${W}Информация о VLESS сервере:${N}"
  sep
  if [ -n "${KOX_SERVER:-}" ]; then
    printf "  Сервер:    ${W}%s${N}\n" "$KOX_SERVER"
    printf "  Порт:      ${W}%s${N}\n" "${KOX_PORT:-443}"
    printf "  UUID:      ${W}%s${N}\n" "${KOX_UUID:-неизвестно}"
    printf "  SNI:       ${W}%s${N}\n" "${KOX_SNI:-}"
    printf "  Flow:      ${W}%s${N}\n" "${KOX_FLOW:-}"
    [ -n "${KOX_SUB_URL:-}" ] && printf "  Подписка:  ${W}%s${N}\n" "$KOX_SUB_URL"
  else
    SRV=$(grep -m1 '"address"' "$CONF" | sed 's/.*"address": *"\([^"]*\)".*/\1/')
    PORT=$(grep -m1 '"port"' "$CONF" | sed 's/.*"port": *\([0-9]*\).*/\1/')
    UUID=$(grep -m1 '"id"' "$CONF" | sed 's/.*"id": *"\([^"]*\)".*/\1/')
    SNI=$(grep -m1 '"serverName"' "$CONF" | sed 's/.*"serverName": *"\([^"]*\)".*/\1/')
    printf "  Сервер:    ${W}%s${N}\n" "${SRV:-неизвестно}"
    printf "  Порт:      ${W}%s${N}\n" "${PORT:-443}"
    printf "  UUID:      ${W}%s${N}\n" "${UUID:-неизвестно}"
    printf "  SNI:       ${W}%s${N}\n" "${SNI:-}"
  fi
  sep
}

kox_check_domain() {
  DOM="${1:-}"
  [ -z "$DOM" ] && fail "Укажите домен: kox check example.com" && return 1
  if grep -q "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    ok "Домен ${W}${DOM}${N} — ${G}в туннеле${N}"
  else
    info "Домен ${W}${DOM}${N} — ${W}прямое соединение${N}"
  fi
}

kox_add_domain() {
  DOM="${1:-}"
  [ -z "$DOM" ] && fail "Укажите домен: kox add example.com" && return 1

  if grep -q "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    warn "Домен ${W}${DOM}${N} уже в конфиге"
    return 0
  fi

  if ! grep -q "$DOMAIN_MARKER" "$CONF"; then
    fail "Маркер '${DOMAIN_MARKER}' не найден в конфиге"
    info "Обратитесь в поддержку: t.me/PrivateProxyKox"
    return 1
  fi

  awk -v dom="$DOM" -v marker="$DOMAIN_MARKER" '
    index($0, marker) > 0 {
      print "          \"domain:" dom "\","
    }
    { print }
  ' "$CONF" > /tmp/kox-config.tmp && mv /tmp/kox-config.tmp "$CONF"

  ok "Добавлен: ${W}${DOM}${N}"
  info "Перезапускаю Xray..."
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен — домен активен" || fail "Ошибка перезапуска"
}

kox_del_domain() {
  DOM="${1:-}"
  [ -z "$DOM" ] && fail "Укажите домен: kox del example.com" && return 1

  if ! grep -q "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    warn "Домен ${W}${DOM}${N} не найден в конфиге"
    return 0
  fi

  grep -v "\"domain:${DOM}\"" "$CONF" > /tmp/kox-config.tmp && mv /tmp/kox-config.tmp "$CONF"
  ok "Удалён: ${W}${DOM}${N}"
  info "Перезапускаю Xray..."
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_add_ip() {
  IP="${1:-}"
  [ -z "$IP" ] && fail "Укажите IP/CIDR: kox add-ip 1.2.3.0/24" && return 1

  if grep -q "\"${IP}\"" "$CONF" 2>/dev/null; then
    warn "IP ${W}${IP}${N} уже в конфиге"
    return 0
  fi

  if ! grep -q "$IP_MARKER" "$CONF"; then
    fail "Маркер IP не найден в конфиге"
    return 1
  fi

  awk -v ip="$IP" -v marker="$IP_MARKER" '
    index($0, marker) > 0 {
      print "          \"" ip "\","
    }
    { print }
  ' "$CONF" > /tmp/kox-config.tmp && mv /tmp/kox-config.tmp "$CONF"

  ok "Добавлен IP: ${W}${IP}${N}"
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_del_ip() {
  IP="${1:-}"
  [ -z "$IP" ] && fail "Укажите IP/CIDR: kox del-ip 1.2.3.0/24" && return 1

  if ! grep -qF "\"${IP}\"" "$CONF" 2>/dev/null; then
    warn "IP ${W}${IP}${N} не найден в конфиге"
    return 0
  fi

  grep -vF "\"${IP}\"" "$CONF" > /tmp/kox-config.tmp && mv /tmp/kox-config.tmp "$CONF"
  ok "Удалён IP: ${W}${IP}${N}"
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_list_domains() {
  info "${W}Домены в туннеле:${N}"
  sep
  grep '"domain:' "$CONF" 2>/dev/null | grep -v 'kox-custom-marker' | \
    sed 's/.*"domain:\([^"]*\)".*/  \1/' | sort
  sep
  COUNT=$(grep '"domain:' "$CONF" 2>/dev/null | grep -v 'kox-custom-marker' | wc -l | tr -d ' ')
  info "Всего: ${W}${COUNT}${N} доменов"
}

kox_list_ips() {
  info "${W}IP/подсети в туннеле:${N}"
  sep
  grep -E '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+"' "$CONF" 2>/dev/null | \
    grep -v '192\.0\.2\.255' | \
    sed 's/.*"\([0-9./]*\)".*/  \1/'
  grep -E '"[0-9a-f:]+/[0-9]+"' "$CONF" 2>/dev/null | \
    sed 's/.*"\([0-9a-f:./]*\)".*/  \1/'
  sep
}

kox_log() {
  sep
  info "${W}Последние ошибки Xray:${N}"
  sep
  tail -50 "$ERRLOG" 2>/dev/null || warn "Лог пуст или отсутствует"
  sep
}

kox_log_live() {
  info "Логи в реальном времени (Ctrl+C для выхода):"
  tail -f "$ERRLOG" 2>/dev/null
}

kox_clear_log() {
  printf '' > "$ERRLOG" 2>/dev/null || true
  printf '' > "$ACCLOG" 2>/dev/null || true
  printf '' > "/opt/var/log/kox-bot.log" 2>/dev/null || true
  ok "Логи очищены"
}

kox_backup() {
  mkdir -p "$BACKUP_DIR"
  TS=$(date +%Y%m%d_%H%M%S)
  BFILE="${BACKUP_DIR}/config_${TS}.json"
  cp "$CONF" "$BFILE"
  [ -f "$KOXCONF" ] && cp "$KOXCONF" "${BACKUP_DIR}/kox_${TS}.conf"
  ok "Бэкап создан: ${W}${BFILE}${N}"
  ls -la "$BACKUP_DIR" | tail -5
}

kox_restore() {
  BFILE="${1:-}"
  if [ -z "$BFILE" ]; then
    info "Доступные бэкапы:"
    ls -lh "${BACKUP_DIR}/"*.json 2>/dev/null || warn "Бэкапы не найдены"
    info "Использование: kox restore <файл>"
    return 0
  fi

  [ ! -f "$BFILE" ] && BFILE="${BACKUP_DIR}/${BFILE}"

  if [ ! -f "$BFILE" ]; then
    fail "Файл не найден: ${BFILE}"
    return 1
  fi

  /opt/sbin/xray -test -config "$BFILE" 2>/dev/null || { fail "Файл не прошёл проверку xray"; return 1; }
  cp "$CONF" "${CONF}.pre-restore"
  cp "$BFILE" "$CONF"
  ok "Конфиг восстановлен из: ${W}${BFILE}${N}"
  kox_restart
}

kox_stats() {
  sep
  info "${W}Статистика трафика:${N}"
  sep
  info "iptables XRAY_REDIRECT:"
  iptables -t nat -vL XRAY_REDIRECT 2>/dev/null | grep -v "^$" | \
    while IFS= read -r LINE; do printf "  %s\n" "$LINE"; done
  sep
  CONN=$(netstat -tn 2>/dev/null | grep -c :10808 || echo 0)
  info "Соединений через Xray: ${W}${CONN}${N}"
  sep
  info "Размер логов:"
  [ -f "$ERRLOG" ] && printf "  Ошибки:  %s\n" "$(ls -lh "$ERRLOG" | awk '{print $5}')"
  [ -f "$ACCLOG" ] && printf "  Доступ:  %s\n" "$(ls -lh "$ACCLOG" | awk '{print $5}')"
  sep
}

kox_update_sub() {
  load_conf
  [ -z "${KOX_SUB_URL:-}" ] && fail "KOX_SUB_URL не задан в kox.conf" && return 1
  info "Обновляю подписку: ${W}${KOX_SUB_URL}${N}"
  RAW=$(curl -sSL --max-time 15 "$KOX_SUB_URL" 2>/dev/null | base64 -d 2>/dev/null || \
        curl -sSL --max-time 15 "$KOX_SUB_URL" 2>/dev/null)
  [ -z "$RAW" ] && fail "Не удалось получить данные подписки" && return 1
  # Extract first vless:// entry
  VLESS_LINE=$(printf '%s' "$RAW" | grep -m1 '^vless://')
  [ -z "$VLESS_LINE" ] && fail "vless:// запись не найдена в подписке" && return 1

  # Parse fields
  BODY=${VLESS_LINE#vless://}
  NEW_UUID=${BODY%%@*}
  HOSTPORT=${BODY#*@}; HOSTPORT=${HOSTPORT%%\?*}
  NEW_HOST=${HOSTPORT%%:*}; NEW_PORT=${HOSTPORT##*:}
  PARAMS=${BODY#*\?}; PARAMS=${PARAMS%%#*}

  get_param() { printf '%s' "$PARAMS" | tr '&' '\n' | grep "^$1=" | cut -d= -f2 | head -1; }
  NEW_PBK=$(get_param pbk); NEW_SID=$(get_param sid); NEW_SNI=$(get_param sni)
  NEW_FP=$(get_param fp); NEW_FLOW=$(get_param flow)

  [ -z "$NEW_HOST" ] || [ -z "$NEW_UUID" ] && fail "Не удалось разобрать VLESS URL" && return 1

  # Update config.json
  if [ -f "$CONF" ]; then
    sed -i "s|\"address\": \"[^\"]*\"|\"address\": \"${NEW_HOST}\"|" "$CONF" 2>/dev/null || true
    sed -i "s|\"port\": [0-9]*\(.*vnext\)\?|\"port\": ${NEW_PORT}|" "$CONF" 2>/dev/null || true
    sed -i "s|\"id\": \"[^\"]*\"|\"id\": \"${NEW_UUID}\"|" "$CONF" 2>/dev/null || true
    [ -n "$NEW_PBK" ] && sed -i "s|\"publicKey\": \"[^\"]*\"|\"publicKey\": \"${NEW_PBK}\"|" "$CONF" 2>/dev/null || true
    [ -n "$NEW_SNI" ] && sed -i "s|\"serverName\": \"[^\"]*\"|\"serverName\": \"${NEW_SNI}\"|" "$CONF" 2>/dev/null || true
    ok "config.json обновлён"
  fi

  # Update kox.conf
  if [ -f "$KOXCONF" ]; then
    sed -i "s|^KOX_SERVER=.*|KOX_SERVER=\"${NEW_HOST}\"|" "$KOXCONF"
    sed -i "s|^KOX_PORT=.*|KOX_PORT=\"${NEW_PORT}\"|" "$KOXCONF"
    sed -i "s|^KOX_UUID=.*|KOX_UUID=\"${NEW_UUID}\"|" "$KOXCONF"
    [ -n "$NEW_SNI" ] && sed -i "s|^KOX_SNI=.*|KOX_SNI=\"${NEW_SNI}\"|" "$KOXCONF"
    ok "kox.conf обновлён"
  fi

  kox_restart
  ok "Подписка обновлена: ${W}${NEW_HOST}:${NEW_PORT}${N}"
}

kox_cron_enable() {
  load_conf
  if [ -z "${KOX_SUB_URL:-}" ]; then
    warn "URL подписки не настроен"
    info "Добавьте KOX_SUB_URL в ${KOXCONF}"
    return 1
  fi
  crontab -l 2>/dev/null | grep -q kox-update && { warn "Авто-обновление уже настроено"; return 0; }
  (crontab -l 2>/dev/null; echo "0 4 * * * /opt/bin/kox update-sub >> /opt/var/log/kox-update.log 2>&1") | crontab -
  ok "Авто-обновление включено (ежедневно в 04:00)"
}

kox_cron_disable() {
  crontab -l 2>/dev/null | grep -v kox-update | crontab -
  ok "Авто-обновление отключено"
}

kox_bot() {
  load_conf
  sep
  info "${W}Telegram Bot статус:${N}"
  sep
  if [ -f "$BOT_INIT" ]; then
    "$BOT_INIT" status 2>/dev/null
  else
    warn "Telegram bot не установлен"
  fi
  if [ -n "${KOX_BOT_TOKEN:-}" ]; then
    info "Token: ${W}${KOX_BOT_TOKEN%%:*}:****${N}"
  else
    warn "Bot token не настроен"
  fi
  if [ -n "${KOX_ADMIN_ID:-}" ]; then
    info "Admin ID: ${W}${KOX_ADMIN_ID}${N}"
  else
    warn "Admin ID не установлен"
    info "Напишите боту — он ответит вашим Telegram ID"
    info "Затем: ${W}kox admin set <ID>${N}"
  fi
  sep
}

kox_admin() {
  SUBCMD="${1:-}"
  case "$SUBCMD" in
    set)
      NEW_ID="${2:-}"
      [ -z "$NEW_ID" ] && fail "Укажите ID: kox admin set 123456789" && return 1
      printf '%s' "$NEW_ID" | grep -qE '^[0-9]+$' || { fail "ID должен быть числом"; return 1; }

      if [ ! -f "$KOXCONF" ]; then
        printf 'KOX_ADMIN_ID="%s"\n' "$NEW_ID" > "$KOXCONF"
      elif grep -q 'KOX_ADMIN_ID' "$KOXCONF"; then
        sed -i "s|^KOX_ADMIN_ID=.*|KOX_ADMIN_ID=\"${NEW_ID}\"|" "$KOXCONF"
      else
        printf '\nKOX_ADMIN_ID="%s"\n' "$NEW_ID" >> "$KOXCONF"
      fi

      ok "Admin ID установлен: ${W}${NEW_ID}${N}"

      if [ -f "$BOT_INIT" ]; then
        info "Перезапускаю Telegram бота..."
        "$BOT_INIT" restart >/dev/null 2>&1 && ok "Бот перезапущен" || warn "Не удалось перезапустить бота"
      fi
      ;;
    show)
      load_conf
      if [ -n "${KOX_ADMIN_ID:-}" ]; then
        info "Admin ID: ${W}${KOX_ADMIN_ID}${N}"
      else
        warn "Admin ID не установлен"
      fi
      ;;
    *)
      info "Использование:"
      info "  kox admin set <telegram_id>   — назначить администратора"
      info "  kox admin show                — показать администратора"
      ;;
  esac
}

KOX_LISTS_DIR="/opt/etc/xray/lists"
KOX_LISTS_LOADED="/opt/etc/xray/kox-lists-loaded.conf"
GITHUB_LISTS="https://raw.githubusercontent.com/nonamenebula/kox-shield/main/lists"

_list_is_loaded() { grep -qx "$1" "$KOX_LISTS_LOADED" 2>/dev/null; }
_list_mark_loaded() {
  touch "$KOX_LISTS_LOADED"
  grep -qx "$1" "$KOX_LISTS_LOADED" 2>/dev/null || printf '%s\n' "$1" >> "$KOX_LISTS_LOADED"
}
_list_unmark_loaded() {
  [ -f "$KOX_LISTS_LOADED" ] && grep -v "^${1}$" "$KOX_LISTS_LOADED" > /tmp/kox-ll.tmp && mv /tmp/kox-ll.tmp "$KOX_LISTS_LOADED"
}
_list_fetch_cat() {
  mkdir -p "$KOX_LISTS_DIR"
  curl -fsSL --max-time 15 "${GITHUB_LISTS}/${1}.txt" -o "${KOX_LISTS_DIR}/${1}.txt" 2>/dev/null
}
_list_fetch_categories_json() {
  mkdir -p "$KOX_LISTS_DIR"
  curl -fsSL --max-time 10 "${GITHUB_LISTS}/categories.json" -o "${KOX_LISTS_DIR}/categories.json" 2>/dev/null
}

_list_add_entries() {
  SLUG="$1"; FILE="${KOX_LISTS_DIR}/${SLUG}.txt"
  [ -f "$FILE" ] || { fail "Файл ${SLUG}.txt не найден"; return 1; }
  APPLIED="${KOX_LISTS_DIR}/.applied-${SLUG}"
  printf '' > "$APPLIED"
  ADDED_D=0; ADDED_IP=0; SKIP_D=0; SKIP_IP=0
  while IFS= read -r LINE; do
    case "$LINE" in '#'*|'') continue ;; esac
    if printf '%s' "$LINE" | grep -qE '^[0-9a-f:]+.*\/[0-9]+$'; then
      if grep -qF "\"${LINE}\"" "$CONF" 2>/dev/null; then
        SKIP_IP=$((SKIP_IP+1))
      elif grep -q "$IP_MARKER" "$CONF"; then
        awk -v ip="$LINE" -v m="$IP_MARKER" 'index($0,m)>0{print "          \""ip"\","}{print}' \
          "$CONF" > /tmp/kox-c.tmp && mv /tmp/kox-c.tmp "$CONF"
        printf 'cidr:%s\n' "$LINE" >> "$APPLIED"; ADDED_IP=$((ADDED_IP+1))
      fi
    else
      if grep -qF "\"domain:${LINE}\"" "$CONF" 2>/dev/null; then
        SKIP_D=$((SKIP_D+1))
      elif grep -q "$DOMAIN_MARKER" "$CONF"; then
        awk -v d="$LINE" -v m="$DOMAIN_MARKER" 'index($0,m)>0{print "          \"domain:"d"\","}{print}' \
          "$CONF" > /tmp/kox-c.tmp && mv /tmp/kox-c.tmp "$CONF"
        printf 'domain:%s\n' "$LINE" >> "$APPLIED"; ADDED_D=$((ADDED_D+1))
      fi
    fi
  done < "$FILE"
  printf '%d %d %d %d' "$ADDED_D" "$ADDED_IP" "$SKIP_D" "$SKIP_IP"
}

_list_remove_entries() {
  SLUG="$1"; APPLIED="${KOX_LISTS_DIR}/.applied-${SLUG}"
  [ -f "$APPLIED" ] || { warn "Нет данных для ${SLUG}"; return 0; }
  REM_D=0; REM_IP=0
  while IFS= read -r ENTRY; do
    case "$ENTRY" in
      domain:*) DOM="${ENTRY#domain:}"
        grep -vF "\"domain:${DOM}\"" "$CONF" > /tmp/kox-c.tmp && mv /tmp/kox-c.tmp "$CONF"
        REM_D=$((REM_D+1)) ;;
      cidr:*)   IP="${ENTRY#cidr:}"
        grep -vF "\"${IP}\"" "$CONF" > /tmp/kox-c.tmp && mv /tmp/kox-c.tmp "$CONF"
        REM_IP=$((REM_IP+1)) ;;
    esac
  done < "$APPLIED"
  rm -f "$APPLIED"
  printf '%d %d' "$REM_D" "$REM_IP"
}

kox_list_cats() {
  sep; info "${W}Категории доменов KOX Shield:${N}"; sep
  CATS_FILE="${KOX_LISTS_DIR}/categories.json"
  if [ ! -f "$CATS_FILE" ]; then
    info "Загружаю список категорий..."; _list_fetch_categories_json || { fail "Нет подключения"; return 1; }
  fi
  LOADED=$(cat "$KOX_LISTS_LOADED" 2>/dev/null || echo "")
  if command -v jq >/dev/null 2>&1; then
    jq -r '.categories[] | "\(.slug)|\(.emoji)|\(.name)|\(.domains)|\(.cidrs)"' "$CATS_FILE" | \
    while IFS='|' read -r SLUG EMJ NAME DOMS CIDRS; do
      STATUS=" "
      printf '%s' "$LOADED" | grep -qx "$SLUG" && STATUS="✓"
      CNT="${DOMS}д"; [ "$CIDRS" -gt 0 ] 2>/dev/null && CNT="${CNT}+${CIDRS}ip"
      printf "  [%s] %s  %-30s (%s)  %s\n" "$STATUS" "$EMJ" "$NAME" "$CNT" "$SLUG"
    done
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$CATS_FILE" "$LOADED" << 'PY'
import sys, json
cats_file = sys.argv[1]
loaded = sys.argv[2].split('\n') if len(sys.argv) > 2 and sys.argv[2] else []
with open(cats_file) as f:
    data = json.load(f)
for c in data['categories']:
    status = "✓" if c['slug'] in loaded else " "
    cnt = f"{c['domains']}д" + (f"+{c['cidrs']}ip" if c['cidrs'] else "")
    print(f"  [{status}] {c['emoji']}  {c['name']:<28} ({cnt})   {c['slug']}")
PY
  else
    grep '"slug"' "$CATS_FILE" | sed 's/.*"slug": *"\([^"]*\)".*/  \1/'
  fi
  sep
  info "Загрузить:  ${W}kox list-load <slug>${N}  или  ${W}kox list-load all${N}"
  info "Удалить:    ${W}kox list-remove <slug>${N}"
  info "Обновления: ${W}kox list-check${N}"
  sep
}

kox_list_load() {
  SLUG="${1:-}"
  [ -z "$SLUG" ] && fail "Укажите: kox list-load <slug> | all" && kox_list_cats && return 1

  if [ "$SLUG" = "all" ]; then
    info "Загружаю все категории..."
    CATS_FILE="${KOX_LISTS_DIR}/categories.json"
    [ -f "$CATS_FILE" ] || _list_fetch_categories_json
    if command -v jq >/dev/null 2>&1; then
      SLUGS=$(jq -r '.categories[].slug' "$CATS_FILE")
    elif command -v python3 >/dev/null 2>&1; then
      SLUGS=$(python3 -c "import json; d=json.load(open('$CATS_FILE')); print('\n'.join(c['slug'] for c in d['categories']))")
    else
      SLUGS=$(grep '"slug"' "$CATS_FILE" | sed 's/.*"slug": *"\([^"]*\)".*/\1/')
    fi
    TOTAL_D=0; TOTAL_IP=0
    for S in $SLUGS; do
      _list_fetch_cat "$S" >/dev/null 2>&1
      RES=$(_list_add_entries "$S")
      D=$(printf '%s' "$RES" | cut -d' ' -f1); I=$(printf '%s' "$RES" | cut -d' ' -f2)
      TOTAL_D=$((TOTAL_D+D)); TOTAL_IP=$((TOTAL_IP+I))
      _list_mark_loaded "$S"
    done
    ok "Загружено: ${W}${TOTAL_D}${N} доменов, ${W}${TOTAL_IP}${N} IP/подсетей"
  else
    _list_is_loaded "$SLUG" && { warn "Категория ${W}${SLUG}${N} уже загружена"; return 0; }
    info "Загружаю: ${W}${SLUG}${N}..."
    _list_fetch_cat "$SLUG" || { fail "Категория '${SLUG}' не найдена"; return 1; }
    RES=$(_list_add_entries "$SLUG")
    D=$(printf '%s' "$RES" | cut -d' ' -f1); I=$(printf '%s' "$RES" | cut -d' ' -f2)
    SD=$(printf '%s' "$RES" | cut -d' ' -f3); SI=$(printf '%s' "$RES" | cut -d' ' -f4)
    _list_mark_loaded "$SLUG"
    if [ "$D" -gt 0 ] || [ "$I" -gt 0 ]; then
      ok "Добавлено: ${W}${D}${N} доменов, ${W}${I}${N} IP/подсетей (уже было: ${SD}д+${SI}ip)"
    else
      ok "Категория ${W}${SLUG}${N} загружена (все ${SD}д+${SI}ip уже были в туннеле)"
    fi
  fi
  info "Перезапускаю Xray..."
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_list_remove() {
  SLUG="${1:-}"
  [ -z "$SLUG" ] && fail "Укажите: kox list-remove <slug> | all" && return 1
  if [ "$SLUG" = "all" ]; then
    info "Удаляю все загруженные категории..."
    TOTAL_D=0; TOTAL_IP=0
    while IFS= read -r S; do
      [ -z "$S" ] && continue
      RES=$(_list_remove_entries "$S")
      D=$(printf '%s' "$RES" | cut -d' ' -f1); I=$(printf '%s' "$RES" | cut -d' ' -f2)
      TOTAL_D=$((TOTAL_D+D)); TOTAL_IP=$((TOTAL_IP+I))
      _list_unmark_loaded "$S"
    done < "${KOX_LISTS_LOADED:-/dev/null}"
    ok "Удалено: ${W}${TOTAL_D}${N} доменов, ${W}${TOTAL_IP}${N} IP/подсетей"
  else
    _list_is_loaded "$SLUG" || { warn "Категория ${W}${SLUG}${N} не загружена"; return 0; }
    info "Удаляю: ${W}${SLUG}${N}..."
    RES=$(_list_remove_entries "$SLUG")
    D=$(printf '%s' "$RES" | cut -d' ' -f1); I=$(printf '%s' "$RES" | cut -d' ' -f2)
    _list_unmark_loaded "$SLUG"
    ok "Удалено: ${W}${D}${N} доменов, ${W}${I}${N} IP/подсетей"
  fi
  info "Перезапускаю Xray..."
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_list_check() {
  info "Проверяю обновления списков..."
  LOCAL_VER=$(cat "${KOX_LISTS_DIR}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  REMOTE_VER=$(curl -fsSL --max-time 10 "${GITHUB_LISTS}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  if [ -z "$REMOTE_VER" ] || ! printf '%s' "$REMOTE_VER" | grep -qE '^[0-9]'; then
    fail "Не удалось получить версию списков"; return 1
  fi
  CUR_INT=$(printf '%s' "${LOCAL_VER:-0}" | tr -d '.'); REM_INT=$(printf '%s' "$REMOTE_VER" | tr -d '.')
  if [ "$REM_INT" -le "${CUR_INT:-0}" ] 2>/dev/null; then
    ok "Списки актуальны: ${W}v${REMOTE_VER}${N}"
  else
    warn "Доступно обновление: ${W}v${REMOTE_VER}${N} (текущая: ${LOCAL_VER:-нет})"
    info "Для обновления: ${W}kox list-update${N}"
  fi
}

kox_list_update() {
  info "Обновляю списки с GitHub..."
  mkdir -p "$KOX_LISTS_DIR"
  REMOTE_VER=$(curl -fsSL --max-time 10 "${GITHUB_LISTS}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -z "$REMOTE_VER" ] && fail "Нет подключения" && return 1
  ! printf '%s' "$REMOTE_VER" | grep -qE '^[0-9]' && fail "Некорректная версия списков" && return 1
  LOCAL_VER=$(cat "${KOX_LISTS_DIR}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  CUR_INT=$(printf '%s' "${LOCAL_VER:-0}" | tr -d '.'); REM_INT=$(printf '%s' "$REMOTE_VER" | tr -d '.')
  if [ "$REM_INT" -le "${CUR_INT:-0}" ] 2>/dev/null; then
    ok "Списки уже актуальны: ${W}v${REMOTE_VER}${N}"; return 0
  fi
  warn "Новая версия: ${W}v${REMOTE_VER}${N}"
  _list_fetch_categories_json || { fail "Ошибка загрузки индекса"; return 1; }
  LOADED=$(cat "$KOX_LISTS_LOADED" 2>/dev/null || echo "")
  if [ -z "$LOADED" ]; then
    printf '%s\n' "$REMOTE_VER" > "${KOX_LISTS_DIR}/LISTS_VERSION"
    ok "Индекс категорий обновлён. Загруженных категорий нет."; return 0
  fi
  printf '%s\n' "$LOADED" | while IFS= read -r S; do
    [ -z "$S" ] && continue
    _list_remove_entries "$S" >/dev/null 2>&1
    _list_fetch_cat "$S" >/dev/null 2>&1
    RES=$(_list_add_entries "$S")
    D=$(printf '%s' "$RES" | cut -d' ' -f1); I=$(printf '%s' "$RES" | cut -d' ' -f2)
    ok "Обновлено ${W}${S}${N}: +${D}д +${I}ip"
  done
  printf '%s\n' "$REMOTE_VER" > "${KOX_LISTS_DIR}/LISTS_VERSION"
  ok "Обновлено до v${REMOTE_VER}"
  "$XRAY_INIT" restart >/dev/null 2>&1 && ok "Xray перезапущен" || fail "Ошибка перезапуска"
}

kox_clear_log() {
  printf '' > "$ERRLOG" 2>/dev/null || true
  printf '' > "$ACCLOG" 2>/dev/null || true
  printf '' > "/opt/var/log/kox-bot.log" 2>/dev/null || true
  ok "Логи очищены"
}

kox_upgrade() {
  FORCE="${1:-}"
  GITHUB_RAW_UP="https://raw.githubusercontent.com/nonamenebula/kox-shield/main"
  info "Проверяю обновления KOX Shield..."

  REMOTE_VERSION=$(curl -fsSL --max-time 10 "${GITHUB_RAW_UP}/VERSION" 2>/dev/null | tr -d '[:space:]')

  if [ -z "$REMOTE_VERSION" ] || ! printf '%s' "$REMOTE_VERSION" | grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}'; then
    fail "Не удалось получить версию с GitHub"
    info "Проверьте подключение к интернету"
    return 1
  fi

  CUR_INT=$(printf '%s' "$KOX_VERSION"    | tr -d '.')
  REM_INT=$(printf '%s' "$REMOTE_VERSION" | tr -d '.')

  if [ "$REM_INT" -le "$CUR_INT" ] 2>/dev/null; then
    ok "У вас актуальная версия: ${W}v${KOX_VERSION}${N}"
    return 0
  fi

  warn "Доступно обновление: ${W}v${REMOTE_VERSION}${N}  (текущая: v${KOX_VERSION})"
  sep

  CHANGELOG=$(curl -sSL --max-time 10 "${GITHUB_RAW_UP}/CHANGELOG.md" 2>/dev/null)
  if [ -n "$CHANGELOG" ]; then
    info "${W}Что нового в v${REMOTE_VERSION}:${N}"
    printf '%s\n' "$CHANGELOG" | \
      awk '/^## /{if(found)exit; found=1; next} found{print}' | \
      grep -v '^[[:space:]]*$' | \
      while IFS= read -r LINE; do printf "  ${C}%s${N}\n" "$LINE"; done
  fi

  sep

  # --force: skip interactive prompt (called from bot)
  if [ "$FORCE" != "--force" ]; then
    printf "\n"
    printf "  Установить обновление? [y/N] "
    read -r ANSWER </dev/tty 2>/dev/null || ANSWER=""
    case "$ANSWER" in
      y|Y|yes|YES|д|Д) : ;;
      *)
        info "Обновление отменено"
        return 0
        ;;
    esac
  fi

  info "Загружаю обновление..."

  # Backup current scripts
  cp /opt/bin/kox     /opt/bin/kox.backup     2>/dev/null || true
  cp /opt/bin/kox-bot /opt/bin/kox-bot.backup 2>/dev/null || true

  FAIL=0

  # kox-cli.sh → /opt/bin/kox
  if curl -sSL --max-time 30 "${GITHUB_RAW_UP}/kox-cli.sh" -o /tmp/kox-upgrade-cli 2>/dev/null \
      && [ -s /tmp/kox-upgrade-cli ]; then
    chmod +x /tmp/kox-upgrade-cli
    mv /tmp/kox-upgrade-cli /opt/bin/kox
    ok "kox (консоль) обновлён"
  else
    fail "Ошибка загрузки kox-cli.sh — восстанавливаю backup"
    mv /opt/bin/kox.backup /opt/bin/kox 2>/dev/null || true
    FAIL=1
  fi

  # kox-bot.sh → /opt/bin/kox-bot
  if curl -sSL --max-time 30 "${GITHUB_RAW_UP}/kox-bot.sh" -o /tmp/kox-upgrade-bot 2>/dev/null \
      && [ -s /tmp/kox-upgrade-bot ]; then
    chmod +x /tmp/kox-upgrade-bot
    mv /tmp/kox-upgrade-bot /opt/bin/kox-bot
    ok "kox-bot обновлён"
  else
    warn "Ошибка загрузки kox-bot.sh"
  fi

  # S90kox-bot → /opt/etc/init.d/S90kox-bot
  if curl -sSL --max-time 30 "${GITHUB_RAW_UP}/S90kox-bot" -o /tmp/kox-upgrade-init 2>/dev/null \
      && [ -s /tmp/kox-upgrade-init ]; then
    chmod +x /tmp/kox-upgrade-init
    mv /tmp/kox-upgrade-init "$BOT_INIT"
    ok "S90kox-bot обновлён"
  fi

  [ "$FAIL" -eq 1 ] && return 1

  sep
  ok "Обновление завершено! Версия: ${W}v${REMOTE_VERSION}${N}"
  info "Перезапускаю Telegram бота..."
  "$BOT_INIT" restart >/dev/null 2>&1 && ok "Бот перезапущен" || warn "Не удалось перезапустить бота"
  info "Изменения в консоли вступят в силу в следующем SSH-сеансе"

  # Suggest loading domain lists if none loaded
  LOADED=$(cat "$KOX_LISTS_LOADED" 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
  if [ "${LOADED:-0}" -eq 0 ]; then
    sep
    warn "У вас не загружено ни одной категории доменов!"
    info "KOX Shield работает только с доменами из вашего конфига."
    info "Рекомендуем загрузить готовые списки:"
    printf "\n"
    info "  ${W}kox list-cats${N}           — посмотреть доступные категории"
    info "  ${W}kox list-load telegram${N}  — загрузить категорию"
    info "  ${W}kox list-load all${N}       — загрузить все категории сразу"
    printf "\n"
    printf "  Загрузить все категории сейчас? [y/N] "
    read -r ANS </dev/tty 2>/dev/null || ANS=""
    case "$ANS" in
      y|Y|yes|YES|д|Д) kox_list_load all ;;
      *) info "Загрузить позже: ${W}kox list-load all${N}" ;;
    esac
  fi
  sep
}

# ── Main ──────────────────────────────────────────────────────────────
CMD="${1:-}"
shift 2>/dev/null || true

case "$CMD" in
  status)        kox_status ;;
  on)            kox_on ;;
  off)           kox_off ;;
  restart)       kox_restart ;;
  test)          kox_test ;;
  server)        kox_server ;;
  stats)         kox_stats ;;
  add)           kox_add_domain "$@" ;;
  del)           kox_del_domain "$@" ;;
  check)         kox_check_domain "$@" ;;
  list)          kox_list_domains ;;
  add-ip)        kox_add_ip "$@" ;;
  del-ip)        kox_del_ip "$@" ;;
  list-ip)       kox_list_ips ;;
  log)           kox_log ;;
  log-live)      kox_log_live ;;
  clear-log)     kox_clear_log ;;
  backup)        kox_backup ;;
  restore)       kox_restore "$@" ;;
  update-sub)    kox_update_sub ;;
  cron-on)       kox_cron_enable ;;
  cron-off)      kox_cron_disable ;;
  list-cats)     kox_list_cats ;;
  list-load)     kox_list_load "$@" ;;
  list-remove)   kox_list_remove "$@" ;;
  list-check)    kox_list_check ;;
  list-update)   kox_list_update ;;
  upgrade)       kox_upgrade "$@" ;;
  clear-log)     kox_clear_log ;;
  bot)           kox_bot ;;
  admin)         kox_admin "$@" ;;
  help|--help|-h|"") kox_banner; kox_help ;;
  *) fail "Неизвестная команда: $CMD"; printf "\n"; kox_banner; kox_help ;;
esac
