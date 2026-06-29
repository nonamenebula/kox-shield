#!/bin/sh
# ╔══════════════════════════════════════════════════════════════════╗
# ║   KOX Shield — Installer for Keenetic Router (Entware)            ║
# ║   https://kox.nonamenebula.ru | t.me/PrivateProxyKox           ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Запуск на роутере одной командой:
#   wget -O /tmp/kox-install.sh https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh && sh /tmp/kox-install.sh
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

read_tty() {
  # The installer is usually started as `wget -qO- ... | sh`, so stdin is the
  # script pipe, not the user's keyboard. Read interactive answers from TTY.
  if [ -r /dev/tty ]; then
    IFS= read -r "$1" </dev/tty
  else
    IFS= read -r "$1"
  fi
}

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
  read_tty CHOICE
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

  for PKG in xray-core curl jq cron iptables; do
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
ulimit -n 65535 2>/dev/null || true
. /opt/etc/init.d/rc.func
INITSCRIPT
    chmod +x "${INIT}/S24xray"
    ok "Xray init скрипт создан"
  else
    sed -i 's/^ENABLED=no/ENABLED=yes/' "${INIT}/S24xray" 2>/dev/null || true
    if ! grep -q 'ulimit.*65535' "${INIT}/S24xray" 2>/dev/null; then
      awk '
        BEGIN { inserted=0 }
        {
          if (!inserted && $0 ~ /^\. \/opt\/etc\/init\.d\/rc\.func/) {
            print "ulimit -n 65535 2>/dev/null || true"
            inserted=1
          }
          print
        }
        END { if (!inserted) print "ulimit -n 65535 2>/dev/null || true" }
      ' "${INIT}/S24xray" > /tmp/kox-s24xray.new 2>/dev/null && \
        mv /tmp/kox-s24xray.new "${INIT}/S24xray" && chmod +x "${INIT}/S24xray"
      ok "S24xray: добавлен ulimit -n 65535"
    fi
    ok "Xray init скрипт активирован"
  fi

  install_hysteria
}

# ── Установка Hysteria2 (для подписок с hysteria2://|hy2://) ───────────────────
# Xray остаётся прозрачным фронтом; hysteria поднимается как локальный
# SOCKS5-клиент (127.0.0.1:11888), на который указывает outbound kox-proxy
# при переключении на hysteria-сервер. На vless-серверах клиент не запускается.
install_hysteria() {
  HY_BIN="/opt/sbin/hysteria"
  if [ -x "$HY_BIN" ] && "$HY_BIN" version >/dev/null 2>&1; then
    ok "hysteria уже установлен"
  else
    info "Определяю архитектуру для hysteria..."
    # Предпочитаем opkg-арку (Entware), иначе uname -m
    OPKG_ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | grep -v '^all$\|^noarch$' | tail -1)
    RAW_ARCH="${OPKG_ARCH:-$(uname -m)}"
    case "$RAW_ARCH" in
      *aarch64*|*arm64*)            HY_ARCH="arm64" ;;
      *armv7*|*armv6*|*arm*)        HY_ARCH="arm" ;;
      *mipsel*|*mipsle*)            HY_ARCH="mipsle" ;;
      *mips64el*)                   HY_ARCH="mipsle" ;;
      *mips*)                       HY_ARCH="mips" ;;
      *x86_64*|*amd64*)             HY_ARCH="amd64" ;;
      *i?86*|*x86*)                 HY_ARCH="386" ;;
      *)                            HY_ARCH="" ;;
    esac
    if [ -z "$HY_ARCH" ]; then
      warn "Не удалось определить архитектуру ($RAW_ARCH) — hysteria пропущен (vless будет работать)"
    else
      info "Загружаю hysteria (linux-${HY_ARCH})..."
      HY_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}"
      if curl -fsSL --max-time 60 "$HY_URL" -o "$HY_BIN" 2>/dev/null && [ -s "$HY_BIN" ]; then
        chmod +x "$HY_BIN"
        if "$HY_BIN" version >/dev/null 2>&1; then
          ok "hysteria установлен (${HY_ARCH})"
        else
          # На MIPS без FPU помогает softfloat-вариант
          if [ "$HY_ARCH" = "mipsle" ] || [ "$HY_ARCH" = "mips" ]; then
            info "Пробую softfloat-вариант hysteria..."
            curl -fsSL --max-time 60 "${HY_URL}-sf" -o "$HY_BIN" 2>/dev/null && chmod +x "$HY_BIN"
          fi
          "$HY_BIN" version >/dev/null 2>&1 && ok "hysteria установлен (${HY_ARCH}-sf)" || \
            warn "hysteria не запускается на этом устройстве — vless будет работать"
        fi
      else
        warn "Не удалось загрузить hysteria — vless будет работать, hysteria-серверы недоступны"
      fi
    fi
  fi

  # init-скрипт S25hysteria: стартует клиент только когда KOX_PROTO=hysteria2
  if [ ! -f "${INIT}/S25hysteria" ]; then
    cat > "${INIT}/S25hysteria" << 'HYINIT'
#!/bin/sh
# S25hysteria — KOX Shield hysteria2 client (управляется kox)
# Запускается только если активный протокол — hysteria2.
BIN=/opt/sbin/hysteria
HCONF=/opt/etc/hysteria/client.yaml
KOXCONF=/opt/etc/xray/kox.conf
LOG=/opt/var/log/hysteria.log
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

hy_start() {
  [ "${KOX_PROTO:-vless}" = "hysteria2" ] || { echo "hysteria: KOX_PROTO!=hysteria2 — пропуск"; return 0; }
  [ -x "$BIN" ]   || { echo "hysteria: бинарник отсутствует"; return 1; }
  [ -f "$HCONF" ] || { echo "hysteria: нет client.yaml"; return 1; }
  killall hysteria 2>/dev/null; sleep 1
  ulimit -n 65535 2>/dev/null || true
  "$BIN" client -c "$HCONF" >> "$LOG" 2>&1 &
  echo "hysteria client запущен"
}
hy_stop() { killall hysteria 2>/dev/null; echo "hysteria остановлен"; }

case "$1" in
  start)   hy_start ;;
  stop)    hy_stop ;;
  restart) hy_stop; sleep 1; hy_start ;;
  *)       echo "usage: $0 {start|stop|restart}" ;;
esac
HYINIT
    chmod +x "${INIT}/S25hysteria"
    ok "S25hysteria init скрипт создан"
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
      {"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","224.0.0.0/4","240.0.0.0/4"],"outboundTag":"direct"},
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
KOX_PROTO="vless"
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

# Не применять если пользователь вручную выключил VPN
[ -f /tmp/kox-vpn-off ] && exit 0

# Не применять если Xray не запущен — иначе весь трафик уйдёт в никуда
pgrep xray >/dev/null 2>&1 || exit 0

$IPTS -t nat -N XRAY_REDIRECT 2>/dev/null || $IPTS -t nat -F XRAY_REDIRECT

# Пропустить приватные IP
for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
            172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$CIDR" -j RETURN 2>/dev/null || true
done

# Перенаправить только HTTP/HTTPS — только эти порты используют VPN
# Остальной трафик (игры, торренты, и т.д.) идёт напрямую
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 80  -j REDIRECT --to-ports 10808 2>/dev/null || true
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 443 -j REDIRECT --to-ports 10808 2>/dev/null || true

# Применить к трафику LAN
$IPTS -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -A PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
NATSCRIPT

  chmod +x "${NAT_DIR}/99-kox-nat.sh"
  ok "iptables правила настроены"

  # Watchdog: скачиваем актуальный watchdog v4 с GitHub (failover, Telegram, auto-return) (failover, Telegram, auto-return)
  info "Загружаю watchdog с GitHub..."
  if curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-watchdog.sh" -o /opt/etc/kox-watchdog.sh 2>/dev/null \
      && [ -s /opt/etc/kox-watchdog.sh ]; then
    chmod +x /opt/etc/kox-watchdog.sh
    ok "Watchdog загружен (/opt/etc/kox-watchdog.sh)"
  else
    warn "Не удалось загрузить watchdog с GitHub — используем встроенный"
    cat > /opt/etc/kox-watchdog.sh << 'WATCHDOG_FALLBACK'
#!/bin/sh
# KOX Watchdog (fallback) — минимальная версия
KOXCONF="/opt/etc/xray/kox.conf"
NAT_SCRIPT="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
LOGF="/opt/var/log/kox-watchdog.log"
[ -f /tmp/kox-vpn-off ] && exit 0
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGF"; }
if ! pgrep xray >/dev/null 2>&1; then
  log "Xray не работает — снимаю iptables"
  iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ulimit -n 65535 2>/dev/null || true
  /opt/etc/init.d/S24xray start 2>/dev/null; sleep 5
  if pgrep xray >/dev/null 2>&1; then
    sh "$NAT_SCRIPT" 2>/dev/null; log "Xray перезапущен"
  else
    log "Xray не запустился — интернет напрямую"
    iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
    iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
    iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  fi
  exit 0
fi
! netstat -ln 2>/dev/null | grep -q ':10808 ' && { killall xray 2>/dev/null; sleep 2; ulimit -n 65535 2>/dev/null || true; /opt/etc/init.d/S24xray start 2>/dev/null; }
! iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT && sh "$NAT_SCRIPT" 2>/dev/null
[ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 300 ] && tail -150 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
WATCHDOG_FALLBACK
    chmod +x /opt/etc/kox-watchdog.sh
  fi

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

  # Ежедневное обслуживание (hysteria + xray в 04:05)
  MAINT="/opt/etc/kox-maintenance.sh"
  if curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-maintenance.sh" -o "$MAINT" 2>/dev/null \
      && [ -s "$MAINT" ]; then
    chmod +x "$MAINT"
    ok "Maintenance-скрипт загружен ($MAINT)"
  fi
  CRON_MAINT="5 4 * * * ${MAINT} >> /opt/var/log/kox-maintenance.log 2>&1 # kox-maintenance"
  TMP=/tmp/kox-cron-install.$$
  crontab -l 2>/dev/null | grep -v 'kox-xray-refresh' | grep -v 'kox-maintenance' > "$TMP" 2>/dev/null || : > "$TMP"
  if ! grep -q kox-maintenance "$TMP" 2>/dev/null; then
    echo "$CRON_MAINT" >> "$TMP"
    crontab "$TMP" 2>/dev/null || echo "$CRON_MAINT" >> /opt/var/spool/cron/crontabs/root 2>/dev/null
    ok "Cron: ежедневное обслуживание в 04:05 (hysteria + xray)"
  fi
  rm -f "$TMP"

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
  # Остановить если уже запущен (BusyBox не имеет pkill)
  killall xray 2>/dev/null || true; sleep 1
  ulimit -n 65535 2>/dev/null || true
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
read_tty USER_INPUT
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
