#!/bin/sh
# KOX VPN Management Console
# https://kox.nonamenebula.ru | t.me/PrivateProxyKox

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
  printf "\n"
  printf "  ${C}🌐 $(hyperlink 'https://kox.nonamenebula.ru/register' 'kox.nonamenebula.ru')${N}\n"
  printf "  ${C}📢 $(hyperlink 'https://t.me/PrivateProxyKox' 't.me/PrivateProxyKox')${N}\n"
  printf "  ${C}🤖 $(hyperlink 'https://t.me/kox_nonamenebula_bot' '@kox_nonamenebula_bot')${N}\n"
  sep
}

kox_help() {
  printf " ${W}Команды KOX VPN:${N}\n\n"
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
  printf "  ${G}kox update-sub${N}       — обновить серверные параметры из подписки\n"
  printf "  ${G}kox cron-on${N}          — авто-обновление (ежедневно 04:00)\n"
  printf "  ${G}kox cron-off${N}         — отключить авто-обновление\n\n"
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
  info "Проверка статуса KOX VPN..."
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
  bot)           kox_bot ;;
  admin)         kox_admin "$@" ;;
  help|--help|-h|"") kox_banner; kox_help ;;
  *) fail "Неизвестная команда: $CMD"; printf "\n"; kox_banner; kox_help ;;
esac
