#!/bin/sh
# ╔══════════════════════════════════════════════════════════════════╗
# ║   KOX Shield — Installer for Keenetic Router (Entware)            ║
# ║   https://kox.nonamenebula.ru | t.me/PrivateProxyKox           ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Запуск на роутере одной командой:
#   wget -qO- https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh | sh
#
# Требования:
#   • Keenetic с установленным Entware (/opt)
#   • Доступ к интернету с роутера
#   • VLESS-подписка (URL вида https://...)

set -e

GITHUB_RAW="https://raw.githubusercontent.com/nonamenebula/kox-shield/main"
OPT="/opt"
XRAY_CONF="/opt/etc/xray"
BIN="/opt/bin"
INIT="/opt/etc/init.d"

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

ok()   { printf " ${G}✓${N}  %s\n" "$*"; }
fail() { printf " ${R}✗${N}  %s\n" "$*" >&2; exit 1; }
info() { printf " ${C}•${N}  %s\n" "$*"; }
warn() { printf " ${Y}!${N}  %s\n" "$*"; }
sep()  { printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"; }
ask()  { printf " ${W}?${N}  %s " "$*"; }

banner() {
  printf "\n"
  printf "${W}  ██╗  ██╗  ██████╗  ██╗  ██╗${N}\n"
  printf "${W}  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝${N}\n"
  printf "${W}  █████╔╝   ██║  ██║  ╚███╔╝ ${N}\n"
  printf "${W}  ██╔═██╗   ██║  ██║  ██╔██╗ ${N}\n"
  printf "${W}  ██║  ██╗  ╚██████╔╝██╔╝ ██╗${N}\n"
  printf "${W}  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝${N}\n"
  printf "\n"
  printf "${C}        ── VPN Installer for Keenetic ──${N}\n"
  printf "\n"
  printf "  ${C}🌐 kox.nonamenebula.ru/register${N}\n"
  printf "  ${C}📢 t.me/PrivateProxyKox${N}\n"
  printf "  ${C}🤖 @kox_nonamenebula_bot${N}\n"
  sep
  printf "\n"
}

# ── Проверки ──────────────────────────────────────────────────────────────────
check_entware() {
  if [ ! -f /opt/bin/opkg ]; then
    fail "Entware не установлен! Установите Entware через веб-интерфейс Keenetic."
  fi
  ok "Entware найден"
}

check_internet() {
  # BusyBox wget не поддерживает HTTPS — используем curl
  if curl -fsSL --max-time 10 --silent https://github.com -o /dev/null 2>/dev/null; then
    ok "Интернет доступен"
  elif ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    ok "Интернет доступен (ping)"
  else
    fail "Нет доступа к интернету с роутера"
  fi
}

# ── Парсинг VLESS URL ──────────────────────────────────────────────────────────
parse_vless_url() {
  VLESS_URL="$1"
  # vless://UUID@HOST:PORT?params#name
  BODY=${VLESS_URL#vless://}
  VLESS_UUID=${BODY%%@*}
  HOSTPORT=${BODY#*@}; HOSTPORT=${HOSTPORT%%\?*}
  VLESS_HOST=${HOSTPORT%%:*}; VLESS_PORT=${HOSTPORT##*:}
  PARAMS=${BODY#*\?}; PARAMS=${PARAMS%%#*}

  get_param() { printf '%s' "$PARAMS" | tr '&' '\n' | grep "^$1=" | cut -d= -f2- | head -1; }
  VLESS_PBK=$(get_param pbk)
  VLESS_SID=$(get_param sid)
  VLESS_SNI=$(get_param sni)
  VLESS_FP=$(get_param fp); [ -z "$VLESS_FP" ] && VLESS_FP="chrome"
  VLESS_FLOW=$(get_param flow); [ -z "$VLESS_FLOW" ] && VLESS_FLOW="xtls-rprx-vision"

  { [ -z "$VLESS_UUID" ] || [ -z "$VLESS_HOST" ]; } && fail "Не удалось разобрать VLESS URL" || true
}

# URL-decode (%XX → байты UTF-8, + → пробел). Работает в busybox sh.
url_decode() {
  # ВАЖНО: сначала экранируем символ % → \x, затем printf '%b' интерпретирует \x
  printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

parse_subscription() {
  SUB_URL="$1"
  info "Загружаю подписку: $SUB_URL"
  RAW=$(curl -fsSL --max-time 15 "$SUB_URL" 2>/dev/null | base64 -d 2>/dev/null || curl -fsSL --max-time 15 "$SUB_URL" 2>/dev/null)
  [ -z "$RAW" ] && fail "Не удалось загрузить подписку"

  COUNT=$(printf '%s' "$RAW" | grep -c '^vless://' || echo 0)
  if [ "$COUNT" -eq 0 ]; then
    fail "vless:// серверы не найдены в подписке"
  fi

  if [ "$COUNT" -eq 1 ]; then
    VLESS_URL=$(printf '%s' "$RAW" | grep '^vless://' | head -1)
    parse_vless_url "$VLESS_URL"
    ok "Сервер: ${W}${VLESS_HOST}:${VLESS_PORT}${N}"
    return
  fi

  # Несколько серверов — предлагаем выбор. Список делаем через временный файл,
  # чтобы избежать subshell и неправильного i++ при пайпе через while.
  TMPLIST="/tmp/.kox-sublist.$$"
  printf '%s\n' "$RAW" | grep '^vless://' > "$TMPLIST" 2>/dev/null
  COUNT=$(wc -l < "$TMPLIST" | tr -d ' ')

  printf "\n"
  info "${W}Доступно серверов: ${COUNT}${N}"
  sep
  i=1
  while IFS= read -r line; do
    HOST=$(printf '%s' "$line" | sed 's|vless://[^@]*@\([^:?#]*\).*|\1|')
    case "$line" in
      *\#*) NAME_RAW=${line##*\#} ;;
      *)    NAME_RAW="" ;;
    esac
    if [ -n "$NAME_RAW" ]; then
      NAME=$(url_decode "$NAME_RAW" 2>/dev/null || printf '%s' "$NAME_RAW")
      [ -z "$NAME" ] && NAME="—"
    else
      NAME="—"
    fi
    printf "  ${W}%d${N}) %s  ${C}%s${N}\n" "$i" "$HOST" "$NAME"
    i=$((i+1))
  done < "$TMPLIST"
  sep
  printf "\n"
  ask "Выберите сервер [1-${COUNT}], Enter = 1:"
  read -r CHOICE
  [ -z "$CHOICE" ] && CHOICE=1

  VLESS_URL=$(sed -n "${CHOICE}p" "$TMPLIST")
  rm -f "$TMPLIST"
  [ -z "$VLESS_URL" ] && fail "Неверный выбор: $CHOICE"
  parse_vless_url "$VLESS_URL"
  ok "Выбран сервер: ${W}${VLESS_HOST}:${VLESS_PORT}${N}"
}

# ── Установка пакетов ─────────────────────────────────────────────────────────
install_packages() {
  info "Обновляю список пакетов..."
  opkg update >/dev/null 2>&1 || warn "opkg update завершился с ошибкой"

  for PKG in xray-core curl jq cron; do
    if opkg list-installed 2>/dev/null | grep -q "^${PKG} "; then
      ok "${PKG} уже установлен"
    else
      info "Устанавливаю ${PKG}..."
      opkg install "$PKG" >/dev/null 2>&1 && ok "${PKG} установлен" || warn "Не удалось установить ${PKG}"
    fi
  done

  # Создать xray init скрипт если не существует
  if [ ! -f "${INIT}/S24xray" ]; then
    info "Создаю xray init скрипт..."
    cat > "${INIT}/S24xray" << 'INITSCRIPT'
#!/bin/sh
ENABLED=yes
PROCS=xray
ARGS="-config /opt/etc/xray/config.json"
PIDFILE=/var/run/xray.pid
. /opt/etc/init.d/rc.func
INITSCRIPT
    chmod +x "${INIT}/S24xray"
    ok "Xray init скрипт создан"
  else
    sed -i 's/^ENABLED=no/ENABLED=yes/' "${INIT}/S24xray" 2>/dev/null || true
    ok "Xray init скрипт активирован"
  fi

  # Запустить crond если не работает
  if ! pgrep crond >/dev/null 2>&1; then
    "${INIT}/S10cron" start 2>/dev/null || crond -c /opt/var/spool/cron/crontabs 2>/dev/null || true
  fi
}

# ── Генерация конфига ─────────────────────────────────────────────────────────
generate_config() {
  mkdir -p "$XRAY_CONF" /opt/var/log

  info "Генерирую config.json..."
  cat > "${XRAY_CONF}/config.json" << CONFIG
{
  "log": {
    "loglevel": "warning",
    "error": "/opt/var/log/xray-err.log",
    "access": "/opt/var/log/xray-acc.log"
  },
  "inbounds": [
    {
      "tag": "kox-transparent",
      "listen": "0.0.0.0",
      "port": 10808,
      "protocol": "dokodemo-door",
      "settings": {"network": "tcp,udp", "followRedirect": true},
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    },
    {
      "tag": "socks-local",
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {
      "tag": "kox-proxy",
      "protocol": "vless",
      "settings": {"vnext": [{"address": "${VLESS_HOST}", "port": ${VLESS_PORT},
        "users": [{"id": "${VLESS_UUID}", "encryption": "none", "flow": "${VLESS_FLOW}"}]}]},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "fingerprint": "${VLESS_FP}",
          "serverName": "${VLESS_SNI}",
          "publicKey": "${VLESS_PBK}",
          "shortId": "${VLESS_SID}", "spiderX": "/"
        }
      }
    },
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","ip":["geoip:private"],"outboundTag":"direct"},
      {"type":"field","domain":["domain:${VLESS_HOST}"],"outboundTag":"direct"},
      {"type":"field","network":"udp","port":"53","outboundTag":"direct"},
      {
        "type": "field",
        "domain": [
          "domain:youtube.com",       "domain:youtu.be",           "domain:googlevideo.com",
          "domain:ytimg.com",         "domain:ggpht.com",
          "domain:whatsapp.com",      "domain:whatsapp.net",       "domain:wa.me",
          "domain:twitter.com",       "domain:x.com",              "domain:t.co",
          "domain:twimg.com",
          "domain:instagram.com",     "domain:cdninstagram.com",   "domain:threads.net",
          "domain:facebook.com",      "domain:fbcdn.net",          "domain:fb.com",
          "domain:discord.com",       "domain:discord.gg",         "domain:discordapp.com",
          "domain:tiktok.com",        "domain:tiktokcdn.com",
          "domain:spotify.com",       "domain:scdn.co",
          "domain:netflix.com",       "domain:nflxext.com",        "domain:nflxvideo.net",
          "domain:openai.com",        "domain:chatgpt.com",        "domain:oaiusercontent.com",
          "domain:claude.ai",         "domain:anthropic.com",
          "domain:steampowered.com",  "domain:steamcommunity.com",
          "domain:reddit.com",        "domain:redd.it",
          "domain:linkedin.com",      "domain:licdn.com",
          "domain:canva.com",
          "domain:medium.com",        "domain:notion.so",
          "domain:figma.com",         "domain:zoom.us",
          "domain:twitch.tv",         "domain:twitchcdn.net",
          "domain:github.com",        "domain:githubusercontent.com",
          "domain:npmjs.com",         "domain:docker.io",
          "domain:viber.com",         "domain:signal.org",
          "domain:wikipedia.org",     "domain:wikimedia.org",
          "domain:proton.me",         "domain:protonmail.com",
          "domain:rutracker.org",     "domain:rutor.info",
          "domain:telegram.org",      "domain:t.me",               "domain:tdesktop.com",
          "domain:core.telegram.org", "domain:api.telegram.org",   "domain:cdn.telegram.org",
          "domain:web.telegram.org",  "domain:telegra.ph",         "domain:graph.org",
          "domain:2ip.ru",            "domain:2ip.io",
          "domain:kox.nonamenebula.ru",
          "domain:kox-custom-marker"
        ],
        "outboundTag": "kox-proxy"
      },
      {
        "type": "field",
        "ip": [
          "149.154.160.0/20","91.108.4.0/22",  "91.108.8.0/22",   "91.108.12.0/22",
          "91.108.16.0/22",  "91.108.20.0/22", "91.108.56.0/22",  "95.161.64.0/20",
          "31.13.24.0/21",   "31.13.64.0/18",  "157.240.0.0/17",
          "192.0.2.255/32"
        ],
        "outboundTag": "kox-proxy"
      },
      {"type":"field","network":"udp","outboundTag":"direct"},
      {"type":"field","network":"tcp","outboundTag":"direct"}
    ]
  }
}
CONFIG
  ok "config.json создан"

  # kox.conf
  cat > "${XRAY_CONF}/kox.conf" << KOXCONF
# KOX Shield — параметры сервера
# https://kox.nonamenebula.ru | t.me/PrivateProxyKox
KOX_SERVER="${VLESS_HOST}"
KOX_PORT="${VLESS_PORT}"
KOX_UUID="${VLESS_UUID}"
KOX_SNI="${VLESS_SNI}"
KOX_FLOW="${VLESS_FLOW}"
KOX_SUB_URL="${SUB_URL:-}"
KOX_INSTALLED="$(date '+%Y-%m-%d %H:%M')"
KOX_BOT_TOKEN=""
KOX_ADMIN_ID=""
KOXCONF
  ok "kox.conf сохранён"
}

# ── iptables NAT ──────────────────────────────────────────────────────────────
setup_nat() {
  info "Настраиваю iptables NAT..."
  NAT_DIR="/opt/etc/ndm/netfilter.d"
  mkdir -p "$NAT_DIR"

  cat > "${NAT_DIR}/99-kox-nat.sh" << 'NATSCRIPT'
#!/bin/sh
[ "$1" = "ip6tables" ] && IPTS=ip6tables || IPTS=iptables

$IPTS -t nat -N XRAY_REDIRECT 2>/dev/null || $IPTS -t nat -F XRAY_REDIRECT

# Пропустить приватные IP
for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
            172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$CIDR" -j RETURN 2>/dev/null || true
done

# Перенаправить TCP и UDP/443 в Xray
$IPTS -t nat -A XRAY_REDIRECT -p tcp -j REDIRECT --to-ports 10808 2>/dev/null || true
$IPTS -t nat -A XRAY_REDIRECT -p udp --dport 443 -j REDIRECT --to-ports 10808 2>/dev/null || true

# Применить к трафику LAN
$IPTS -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -A PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -A PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
NATSCRIPT

  chmod +x "${NAT_DIR}/99-kox-nat.sh"
  sh "${NAT_DIR}/99-kox-nat.sh" 2>/dev/null || true
  ok "iptables правила настроены"

  # Watchdog: если Xray упал — снимаем iptables чтобы интернет продолжал работать напрямую
  cat > /opt/etc/kox-watchdog.sh << 'WATCHDOG'
#!/bin/sh
# KOX Watchdog — авто-fallback если Xray не работает
XRAY_INIT="/opt/etc/init.d/S24xray"
NAT_SCRIPT="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
LOGF="/opt/var/log/kox-watchdog.log"
TS=$(date '+%H:%M:%S')

if pgrep xray >/dev/null 2>&1; then
  # Xray работает — убедиться что iptables правила есть (восстановить если пропали)
  if ! iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT; then
    if [ ! -f /tmp/kox-vpn-off ]; then
      [ -x "$NAT_SCRIPT" ] && sh "$NAT_SCRIPT" 2>/dev/null
      echo "$TS iptables восстановлен" >> "$LOGF"
    fi
  fi
else
  # Xray не работает — снять iptables чтобы интернет шёл напрямую
  iptables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  echo "$TS Xray упал — iptables снят, интернет работает напрямую" >> "$LOGF"
  # Попытка перезапуска
  if [ -x "$XRAY_INIT" ]; then
    "$XRAY_INIT" start 2>/dev/null
    sleep 3
    if pgrep xray >/dev/null 2>&1; then
      [ -x "$NAT_SCRIPT" ] && sh "$NAT_SCRIPT" 2>/dev/null
      echo "$TS Xray перезапущен, iptables восстановлен" >> "$LOGF"
    else
      echo "$TS Xray не удалось перезапустить — трафик идёт напрямую" >> "$LOGF"
    fi
  fi
  # Ротация лога
  [ $(wc -l < "$LOGF" 2>/dev/null || echo 0) -gt 200 ] && tail -100 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
fi
WATCHDOG

  chmod +x /opt/etc/kox-watchdog.sh

  # Добавить watchdog в cron (каждую минуту)
  CRON_LINE="* * * * * /opt/etc/kox-watchdog.sh"
  mkdir -p /opt/var/spool/cron/crontabs
  if ! crontab -l 2>/dev/null | grep -q kox-watchdog; then
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab - 2>/dev/null || \
      echo "$CRON_LINE" >> /opt/var/spool/cron/crontabs/root
    ok "Watchdog добавлен в cron (каждую минуту)"
  else
    ok "Watchdog уже в cron"
  fi

  # Символические ссылки для geo-данных
  if [ ! -f "/opt/usr/share/xray/geoip.dat" ] && [ -f "/opt/usr/share/xray-core/geoip.dat" ]; then
    mkdir -p /opt/usr/share/xray
    ln -sf /opt/usr/share/xray-core/geoip.dat /opt/usr/share/xray/geoip.dat
    ln -sf /opt/usr/share/xray-core/geosite.dat /opt/usr/share/xray/geosite.dat
  fi
}

# ── Загрузка kox CLI и бота с GitHub ─────────────────────────────────────────
download_scripts() {
  info "Загружаю kox CLI с GitHub..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-cli.sh" -o "${BIN}/kox" && chmod +x "${BIN}/kox" || \
    fail "Не удалось загрузить kox CLI"
  ok "kox → /opt/bin/kox"

  info "Загружаю kox-bot с GitHub..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-bot.sh" -o "${BIN}/kox-bot" && chmod +x "${BIN}/kox-bot" || \
    warn "Не удалось загрузить kox-bot (опционально)"

  info "Загружаю init.d сервис..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/S90kox-bot" -o "${INIT}/S90kox-bot" && chmod +x "${INIT}/S90kox-bot" || \
    warn "Не удалось загрузить S90kox-bot (опционально)"
}

# ── Запуск Xray ───────────────────────────────────────────────────────────────
start_xray() {
  info "Запускаю Xray..."
  # Остановить если уже запущен
  pkill xray 2>/dev/null || true; sleep 1
  if [ -f "${INIT}/S24xray" ]; then
    "${INIT}/S24xray" start 2>/dev/null || true
  else
    # Прямой запуск
    /opt/sbin/xray -config "${XRAY_CONF}/config.json" >> /opt/var/log/xray-err.log 2>&1 &
  fi
  sleep 3
  if pgrep xray >/dev/null 2>&1; then
    ok "Xray запущен (PID: $(pgrep xray | head -1))"
  else
    warn "Xray не запустился — проверьте: kox log"
  fi
}

# ── Итог ──────────────────────────────────────────────────────────────────────
show_result() {
  printf "\n"
  sep
  printf " ${G}✓${N}  ${W}KOX Shield установлен!${N}\n"
  sep
  printf "\n"
  printf "  Сервер:  ${W}%s:%s${N}\n" "$VLESS_HOST" "$VLESS_PORT"
  printf "\n"
  printf "  ${C}Команды управления:${N}\n"
  printf "    kox status     — статус VPN\n"
  printf "    kox on/off     — включить/выключить\n"
  printf "    kox add <домен>— добавить домен в туннель\n"
  printf "    kox list       — список доменов\n"
  printf "    kox help       — все команды\n"
  printf "\n"
  printf "  ${C}Telegram Bot:${N}\n"
  printf "    kox.conf: добавьте KOX_BOT_TOKEN и KOX_ADMIN_ID\n"
  printf "    Или: напишите @kox_nonamenebula_bot за токеном\n"
  printf "\n"
  sep
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
banner

# 1. Проверки
info "Проверяю окружение..."
check_entware
check_internet

# 2. Получить URL подписки или VLESS URL
printf "\n"
sep
printf " ${W}Настройка VLESS подключения${N}\n"
sep
printf "\n"
printf "  Введите ${W}URL подписки${N} (https://...) или ${W}VLESS URL${N} (vless://...):\n"
printf "\n"
ask "→"
read -r USER_INPUT
[ -z "$USER_INPUT" ] && fail "Ввод не может быть пустым"

if printf '%s' "$USER_INPUT" | grep -q '^vless://'; then
  parse_vless_url "$USER_INPUT"
  ok "VLESS URL принят: ${W}${VLESS_HOST}:${VLESS_PORT}${N}"
elif printf '%s' "$USER_INPUT" | grep -q '^https\?://'; then
  SUB_URL="$USER_INPUT"
  parse_subscription "$SUB_URL"
else
  fail "Введите корректный URL подписки (https://...) или VLESS URL (vless://...)"
fi

# 3. Установка
printf "\n"
sep
printf " ${W}Установка пакетов${N}\n"
sep
install_packages

# 4. Конфиг
printf "\n"
sep
printf " ${W}Конфигурация${N}\n"
sep
generate_config
setup_nat

# 5. Скачать CLI и бот
printf "\n"
sep
printf " ${W}Установка KOX инструментов${N}\n"
sep
download_scripts

# 6. Запуск
start_xray

# 7. Итог
show_result
