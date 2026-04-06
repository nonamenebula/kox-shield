#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║   KOX VPN — VLESS Installer for Keenetic                       ║
# ║   kox.nonamenebula.ru                                           ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Запуск: chmod +x xraykit.sh && ./xraykit.sh
# Сайт:   https://kox.nonamenebula.ru
# Автор:  KOX VPN

# ── Цвета и символы ─────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'
BOLD='\033[1m'; M='\033[0;35m'

ok()   { echo -e " ${G}✓${N}  $*"; }
fail() { echo -e " ${R}✗${N}  $*"; }
info() { echo -e " ${Y}→${N}  $*"; }
step() { echo -e "\n${BOLD}${B}[$1]${N} ${W}$2${N}"; }
ask()  { echo -e " ${C}?${N}  $*"; }
warn() { echo -e " ${Y}⚠${N}  $*"; }
kox()  { echo -e " ${M}★${N}  $*"; }
die()  { echo -e "\n ${R}ОШИБКА:${N} $*\n"; exit 1; }
sep()  { echo -e "  ${B}────────────────────────────────────────────────${N}"; }

# ── Баннер KOX VPN ──────────────────────────────────────────────────
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
  echo -e "  ${W}VLESS-туннель с раздельным трафиком для Keenetic${N}"
  echo -e "  ${M}★${N} ${C}https://kox.nonamenebula.ru${N}  ${M}★${N}  Автор: KOX VPN"
  echo -e "  ${M}★${N} Telegram: ${C}@PrivateProxyKox${N}  Бот: ${C}@kox_nonamenebula_bot${N}"
  sep
  echo ""
}

# ── SSH helper — использует переменную ROUTER_SSH_PORT ──────────────
router() {
  sshpass -p "$ROUTER_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -p "${ROUTER_SSH_PORT:-222}" "root@${ROUTER_IP}" "$@" 2>/dev/null
}

url_decode() {
  python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$1"
}

b64decode() {
  echo "$1" | base64 -d 2>/dev/null || echo "$1" | base64 -D 2>/dev/null || echo ""
}

get_param() {
  echo "$VLESS_PARAMS" | tr '&' '\n' | grep "^${1}=" | head -1 | cut -d'=' -f2-
}

spinner() {
  local pid=$1 msg=$2
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  while kill -0 "$pid" 2>/dev/null; do
    for i in $(seq 0 9); do
      echo -ne "\r ${C}${spin:$i:1}${N}  $msg   "
      sleep 0.1
    done
  done
  echo -ne "\r"
}

HTTP_PID=""
start_http_server() {
  cd /tmp
  python3 -m http.server 8765 --bind "$MY_LOCAL_IP" >/dev/null 2>&1 &
  HTTP_PID=$!
  sleep 1
}
stop_http_server() {
  [ -n "$HTTP_PID" ] && kill "$HTTP_PID" 2>/dev/null || true
  HTTP_PID=""
}

trap 'stop_http_server; echo -e "\n${Y}[KOX VPN] Прервано.${N}"; exit 1' INT TERM

# ══════════════════════════════════════════════════════════════════════
# ШАГ 0: Зависимости
# ══════════════════════════════════════════════════════════════════════
phase_deps() {
  step "0/10" "Проверка зависимостей"

  command -v curl    &>/dev/null && ok "curl найден"    || die "curl не найден. Установите: brew install curl"
  command -v python3 &>/dev/null && ok "python3 найден" || die "python3 не найден"

  if ! command -v sshpass &>/dev/null; then
    warn "sshpass не найден — нужен для автоматического SSH"
    ask "Установить sshpass через Homebrew? [Y/n]: "
    read -r REPLY
    if [[ "${REPLY,,}" != "n" ]]; then
      command -v brew &>/dev/null || die "Homebrew не найден. Установите sshpass вручную."
      brew install hudochenkov/sshpass/sshpass >/dev/null 2>&1 && ok "sshpass установлен" || die "Ошибка установки sshpass"
    else
      die "sshpass обязателен для KOX VPN Installer"
    fi
  else
    ok "sshpass найден"
  fi

  MY_LOCAL_IP=$(ipconfig getifaddr en0 2>/dev/null || \
               ipconfig getifaddr en1 2>/dev/null || \
               ifconfig 2>/dev/null | grep -Eo '192\.168\.[0-9]+\.[0-9]+' | head -1)
  [ -z "$MY_LOCAL_IP" ] && die "Не удалось определить ваш IP. Подключитесь к Wi-Fi роутера."
  ok "Ваш IP в сети: ${W}$MY_LOCAL_IP${N}"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 0.5: Режим установки
# ══════════════════════════════════════════════════════════════════════
phase_mode_select() {
  echo ""
  echo -e "  ${B}╔══════════════════════════════════════════════╗${N}"
  echo -e "  ${B}║${N}  ${W}Выберите режим установки KOX VPN:${N}          ${B}║${N}"
  echo -e "  ${B}╠══════════════════════════════════════════════╣${N}"
  echo -e "  ${B}║${N}  ${G}1${N}  Чистая установка (роутер без VPN)        ${B}║${N}"
  echo -e "  ${B}║${N}  ${Y}2${N}  Замена/обновление (Kvass, другой VPN)    ${B}║${N}"
  echo -e "  ${B}║${N}  ${C}3${N}  Только обновить конфиг (Xray уже стоит)  ${B}║${N}"
  echo -e "  ${B}╚══════════════════════════════════════════════╝${N}"
  echo ""
  ask "Ваш выбор [1/2/3], по умолчанию 1:"
  echo -ne " →  "
  read -r MODE_INPUT
  INSTALL_MODE="${MODE_INPUT:-1}"

  case "$INSTALL_MODE" in
    1) ok "Режим: ${G}Чистая установка${N}"; SKIP_DETECT=true;  SKIP_CLEANUP=true;  ONLY_CONFIG=false ;;
    2) ok "Режим: ${Y}Замена/обновление${N}";  SKIP_DETECT=false; SKIP_CLEANUP=false; ONLY_CONFIG=false ;;
    3) ok "Режим: ${C}Только обновить конфиг${N}"; SKIP_DETECT=true; SKIP_CLEANUP=true; ONLY_CONFIG=true ;;
    *) warn "Неверный выбор — используется режим 1"; SKIP_DETECT=true; SKIP_CLEANUP=true; ONLY_CONFIG=false ;;
  esac
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 1: Подписка + выбор сервера
# ══════════════════════════════════════════════════════════════════════
phase_subscription() {
  step "1/10" "Подписка KOX VPN / VLESS"
  echo ""
  kox "Ссылку на подписку получите на ${C}https://kox.nonamenebula.ru${N}"
  echo ""
  ask "Вставьте ссылку на подписку VLESS:"
  echo -e "    ${C}(пример: https://kox.nonamenebula.ru/c/jJDmhzjwMexD)${N}"
  echo -ne " →  "
  read -r SUB_URL
  echo ""
  [ -z "$SUB_URL" ] && die "Ссылка не может быть пустой"

  info "Получаю конфиг по ссылке..."
  SUB_RAW=$(curl -sSL --max-time 15 "$SUB_URL") || die "Не удалось получить данные: $SUB_URL"
  [ -z "$SUB_RAW" ] && die "Сервер вернул пустой ответ"

  # Попробовать base64, потом прямой текст
  DECODED=$(b64decode "$SUB_RAW" 2>/dev/null || echo "")
  if echo "$DECODED" | grep -q "^vless://"; then
    ALL_VLESS=$(echo "$DECODED" | grep "^vless://")
  elif echo "$SUB_RAW" | grep -q "^vless://"; then
    ALL_VLESS=$(echo "$SUB_RAW" | grep "^vless://")
  else
    die "VLESS URI не найден в ответе подписки. Проверьте ссылку."
  fi

  URI_COUNT=$(echo "$ALL_VLESS" | grep -c "^vless://" || echo "0")
  ok "Найдено серверов в подписке: ${W}$URI_COUNT${N}"

  # ── Выбор сервера если их несколько ───────────────────────────────
  if [ "$URI_COUNT" -gt 1 ]; then
    echo ""
    echo -e "  ${W}Доступные серверы KOX VPN:${N}"
    sep
    I=1
    while IFS= read -r URI; do
      RAW_NAME=$(echo "$URI" | sed 's/.*#//')
      SRV_NAME=$(python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))" "$RAW_NAME" 2>/dev/null || echo "Сервер $I")
      SRV_HOST=$(echo "$URI" | sed 's|vless://[^@]*@||' | cut -d'?' -f1 | cut -d':' -f1)
      SRV_PORT=$(echo "$URI" | sed 's|vless://[^@]*@||' | cut -d'?' -f1 | cut -d':' -f2)
      echo -e "  ${G}$I${N}  ${W}$SRV_NAME${N} — $SRV_HOST:$SRV_PORT"
      I=$((I+1))
    done <<< "$ALL_VLESS"
    sep
    echo ""
    ask "Выберите сервер [1-$URI_COUNT], по умолчанию 1:"
    echo -ne " →  "
    read -r SERVER_NUM
    SERVER_NUM="${SERVER_NUM:-1}"
    # Валидация
    if ! echo "$SERVER_NUM" | grep -qE '^[0-9]+$' || [ "$SERVER_NUM" -lt 1 ] || [ "$SERVER_NUM" -gt "$URI_COUNT" ]; then
      warn "Неверный выбор — используется сервер 1"
      SERVER_NUM=1
    fi
    VLESS_URI=$(echo "$ALL_VLESS" | sed -n "${SERVER_NUM}p")
    ok "Выбран сервер ${G}№${SERVER_NUM}${N}"
  else
    VLESS_URI=$(echo "$ALL_VLESS" | head -1)
    ok "Один сервер в подписке — используется автоматически"
  fi

  # ── Парсинг URI ────────────────────────────────────────────────────
  AFTER_PROTO="${VLESS_URI#vless://}"
  VLESS_UUID="${AFTER_PROTO%%@*}"
  HOST_AND_REST="${AFTER_PROTO#*@}"
  HOST_PORT="${HOST_AND_REST%%\?*}"
  VLESS_HOST="${HOST_PORT%%:*}"
  VLESS_PORT="${HOST_PORT##*:}"
  VLESS_PARAMS="${HOST_AND_REST#*\?}"
  VLESS_PARAMS="${VLESS_PARAMS%%#*}"

  VLESS_SNI=$(url_decode "$(get_param sni)");  [ -z "$VLESS_SNI" ] && VLESS_SNI="$VLESS_HOST"
  VLESS_FP=$(url_decode "$(get_param fp)");    VLESS_FP="${VLESS_FP:-chrome}"
  VLESS_PBK=$(url_decode "$(get_param pbk)")
  VLESS_SID=$(url_decode "$(get_param sid)")
  VLESS_FLOW=$(url_decode "$(get_param flow)"); VLESS_FLOW="${VLESS_FLOW:-xtls-rprx-vision}"

  for FIELD in VLESS_UUID VLESS_HOST VLESS_PORT VLESS_PBK VLESS_SID; do
    [ -z "${!FIELD}" ] && die "Не удалось извлечь $FIELD из VLESS URI"
  done

  echo ""
  echo -e "  ${W}Параметры KOX VPN:${N}"
  echo -e "  ${M}★${N} Сервер:    ${G}${VLESS_HOST}:${VLESS_PORT}${N}"
  echo -e "  ${M}★${N} UUID:      ${G}${VLESS_UUID}${N}"
  echo -e "  ${M}★${N} SNI:       ${G}${VLESS_SNI}${N}"
  echo -e "  ${M}★${N} Flow:      ${G}${VLESS_FLOW}${N}"
  echo -e "  ${M}★${N} PublicKey: ${G}${VLESS_PBK:0:24}...${N}"
  echo ""
  ask "Параметры верны? [Y/n]: "
  read -r REPLY
  [[ "${REPLY,,}" == "n" ]] && die "Отменено. Проверьте ссылку на kox.nonamenebula.ru"

  VLESS_IP=$(python3 -c "import socket; print(socket.gethostbyname('$VLESS_HOST'))" 2>/dev/null || echo "")
  [ -n "$VLESS_IP" ] && info "IP KOX VPN сервера: ${W}$VLESS_IP${N}"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 2: Параметры роутера (IP + SSH порт + пароль)
# ══════════════════════════════════════════════════════════════════════
phase_router_input() {
  step "2/10" "Параметры роутера Keenetic"
  echo ""

  # IP роутера
  ask "IP роутера [Enter = 192.168.1.1]:"
  echo -ne " →  "
  read -r INPUT_IP
  ROUTER_IP="${INPUT_IP:-192.168.1.1}"
  ok "Роутер: ${W}$ROUTER_IP${N}"

  # SSH порт
  echo ""
  warn "Entware использует Dropbear SSH (обычно порт ${W}222${N})"
  warn "Если вы меняли порт — укажите свой"
  ask "SSH порт Entware [Enter = 222]:"
  echo -ne " →  "
  read -r INPUT_PORT
  ROUTER_SSH_PORT="${INPUT_PORT:-222}"
  ok "SSH порт: ${W}$ROUTER_SSH_PORT${N}"

  # Пароль
  echo ""
  warn "Пользователь ${W}root${N}, пароль — тот же что у веб-интерфейса (логин admin)"
  ask "Введите пароль роутера (не отображается):"
  echo -ne " →  "
  read -rs ROUTER_PASS
  echo ""
  [ -z "$ROUTER_PASS" ] && die "Пароль не может быть пустым"
  ok "Пароль принят"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 3: Проверка SSH подключения
# ══════════════════════════════════════════════════════════════════════
phase_connect() {
  step "3/10" "Подключение к Keenetic"
  echo ""
  info "Подключаюсь: root@${ROUTER_IP}:${ROUTER_SSH_PORT}..."

  TEST=$(sshpass -p "$ROUTER_PASS" ssh \
    -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
    -p "${ROUTER_SSH_PORT}" "root@${ROUTER_IP}" "echo KOX_CONNECTED" 2>&1 || true)

  if [[ "$TEST" == *"KOX_CONNECTED"* ]]; then
    ok "SSH подключение успешно"
  elif [[ "$TEST" == *"Connection refused"* ]]; then
    die "Порт ${ROUTER_SSH_PORT} закрыт. Проверьте что Entware установлен и порт правильный."
  elif [[ "$TEST" == *"Authentication failed"* ]] || [[ "$TEST" == *"Permission denied"* ]]; then
    die "Неверный пароль."
  elif [[ "$TEST" == *"No route to host"* ]] || [[ "$TEST" == *"Network is unreachable"* ]]; then
    die "Роутер $ROUTER_IP недоступен. Подключитесь к его Wi-Fi."
  else
    die "Ошибка подключения: $TEST"
  fi

  ROUTER_INFO=$(router "cat /etc/ndm/version 2>/dev/null | head -2 || uname -a" || echo "")
  [ -n "$ROUTER_INFO" ] && ok "Прошивка: ${W}$(echo "$ROUTER_INFO" | head -1 | cut -c1-55)${N}"

  if ! router "ls /opt/bin/opkg" >/dev/null 2>&1; then
    fail "Entware (opkg) не найден!"
    echo ""
    echo -e "  ${Y}Для KOX VPN требуется Entware:${N}"
    echo "    1. Вставьте USB-флешку (EXT4/NTFS) в роутер"
    echo "    2. Откройте http://$ROUTER_IP → Приложения → Entware → Установить"
    echo "    3. Перезапустите этот скрипт"
    die "Entware не установлен"
  fi
  ok "Entware (opkg) доступен"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 4: Обнаружение ПО
# ══════════════════════════════════════════════════════════════════════
phase_detect() {
  step "4/10" "Обнаружение установленного ПО"
  echo ""
  FOUND_KVAS=false; FOUND_SS=false; FOUND_XRAY=false; FOUND_SINGBOX=false

  if router "ls /opt/etc/init.d/S96kvas" >/dev/null 2>&1 || \
     router "/opt/bin/opkg list-installed 2>/dev/null | grep -q kvas" >/dev/null 2>&1; then
    FOUND_KVAS=true; warn "Найден: ${R}Kvass${N} — будет удалён"
  else
    ok "Kvass: не установлен"
  fi

  if router "ls /opt/etc/init.d/S22shadowsocks" >/dev/null 2>&1; then
    FOUND_SS=true; warn "Найден: ${Y}Shadowsocks${N} — будет отключён"
  else
    ok "Shadowsocks: не установлен"
  fi

  if router "ls /opt/sbin/xray" >/dev/null 2>&1; then
    FOUND_XRAY=true
    XRAY_VER=$(router "/opt/sbin/xray version 2>/dev/null | head -1" || echo "")
    ok "Xray: ${G}найден${N} — $XRAY_VER"
  else
    info "Xray: не установлен (будет установлен)"
  fi

  if router "ls /opt/sbin/sing-box" >/dev/null 2>&1; then
    FOUND_SINGBOX=true; warn "Найден: ${Y}sing-box${N} — будет остановлен"
  else
    ok "sing-box: не установлен"
  fi

  echo ""
  if $FOUND_KVAS || $FOUND_SS || $FOUND_SINGBOX; then
    ask "Найдено стороннее ПО. Очистить и продолжить? [Y/n]: "
    read -r REPLY
    [[ "${REPLY,,}" == "n" ]] && die "Отменено"
  else
    kox "Конфликтующего ПО нет — чистая установка KOX VPN"
  fi
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 5: Очистка
# ══════════════════════════════════════════════════════════════════════
phase_cleanup() {
  step "5/10" "Очистка перед KOX VPN"
  echo ""

  if ${FOUND_KVAS:-false}; then
    info "Удаляю Kvass..."
    router "/opt/etc/init.d/S96kvas stop 2>/dev/null; sleep 1; /opt/bin/opkg remove kvas 2>/dev/null; true" || true
    router "rm -f /opt/etc/init.d/S96kvas /opt/etc/ndm/iflayerchanged.d/kvas-ips-reset \
      /opt/etc/ndm/ifdestroyed.d/kvas-iface-del /opt/etc/ndm/ifcreated.d/kvas-iface-add \
      /opt/etc/ndm/netfilter.d/kvas-nat.sh /opt/etc/cron.5mins/ipset.kvas \
      /opt/etc/dnsmasq.d/kvas.dnsmasq /opt/etc/kvas.dnsmasq /opt/bin/kvas \
      /opt/etc/kvas.conf /opt/etc/kvas.list 2>/dev/null; rm -rf /opt/apps/kvas /opt/etc/.kvas 2>/dev/null; true" || true
    router "iptables -t nat -D PREROUTING -i br0 -p tcp -m set --match-set unblock dst -j REDIRECT --to-ports 1181 2>/dev/null; \
      ipset destroy unblock 2>/dev/null; true" || true
    ok "Kvass удалён"
  fi

  if ${FOUND_SS:-false}; then
    router "sed -i 's/^ENABLED=yes/ENABLED=no/' /opt/etc/init.d/S22shadowsocks 2>/dev/null; \
      /opt/etc/init.d/S22shadowsocks stop 2>/dev/null; killall ss-redir 2>/dev/null; true" || true
    ok "Shadowsocks отключён"
  fi

  if ${FOUND_SINGBOX:-false}; then
    router "killall sing-box 2>/dev/null; true" || true
    ok "sing-box остановлен"
  fi

  if ${FOUND_XRAY:-false}; then
    router "/opt/etc/init.d/S24xray stop 2>/dev/null; rm -f /opt/etc/xray/config.json" || true
    ok "Старый конфиг Xray очищен"
  fi

  router "iptables  -t nat -F XRAY_REDIRECT 2>/dev/null; iptables  -t nat -X XRAY_REDIRECT 2>/dev/null
          ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null; ip6tables -t nat -X XRAY_REDIRECT 2>/dev/null; true" || true
  ok "Правила iptables очищены"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 6: Установка Xray + geofiles
# ══════════════════════════════════════════════════════════════════════
phase_install() {
  step "6/10" "Установка Xray (KOX VPN engine)"
  echo ""

  if $ONLY_CONFIG; then
    FOUND_XRAY=true; kox "Режим 'только конфиг' — Xray не переустанавливаю"
  else
    info "Обновляю opkg..."
    router "/opt/bin/opkg update >/dev/null 2>&1 || true"
    ok "opkg обновлён"

    if ! ${FOUND_XRAY:-false}; then
      info "Устанавливаю xray-core..."
      OUT=$(router "/opt/bin/opkg install xray-core 2>&1 || /opt/bin/opkg install xray 2>&1 || echo KOXFAIL")
      echo "$OUT" | grep -q "KOXFAIL" && die "Не удалось установить Xray. Проверьте интернет на роутере."
      router "ls /opt/sbin/xray" >/dev/null 2>&1 && ok "xray-core установлен" || die "xray не найден после установки"
      FOUND_XRAY=true
    else
      ok "Xray уже установлен"
    fi
  fi

  router "mkdir -p /opt/etc/xray /opt/usr/share/xray /opt/var/log"

  # geofiles
  if $ONLY_CONFIG && router "ls /opt/usr/share/xray/geoip.dat" >/dev/null 2>&1; then
    ok "geoip.dat уже есть — пропускаю"
  else
    info "Скачиваю geoip.dat и geosite.dat..."
    curl -sSL -o /tmp/geoip.dat   "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geoip.dat" &   C1=$!
    curl -sSL -o /tmp/geosite.dat "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat" & C2=$!
    spinner $C1 "geoip.dat...";   wait $C1 || die "Ошибка скачивания geoip.dat"
    spinner $C2 "geosite.dat..."; wait $C2 || die "Ошибка скачивания geosite.dat"
    ok "geoip.dat ($(du -sh /tmp/geoip.dat | cut -f1)) + geosite.dat ($(du -sh /tmp/geosite.dat | cut -f1))"
    start_http_server
    router "wget -q -O /opt/usr/share/xray/geoip.dat   http://${MY_LOCAL_IP}:8765/geoip.dat"   || die "Ошибка копирования geoip.dat"
    router "wget -q -O /opt/usr/share/xray/geosite.dat http://${MY_LOCAL_IP}:8765/geosite.dat" || die "Ошибка копирования geosite.dat"
    router "ln -sf /opt/usr/share/xray/geoip.dat /opt/sbin/geoip.dat; ln -sf /opt/usr/share/xray/geosite.dat /opt/sbin/geosite.dat"
    ok "geoip/geosite установлены"
  fi
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 7: config.json для KOX VPN (с маркером для kox CLI)
# ══════════════════════════════════════════════════════════════════════
phase_configure() {
  step "7/10" "Конфигурация KOX VPN"
  echo ""

  VLESS_IP_RULE=""
  [ -n "${VLESS_IP:-}" ] && \
    VLESS_IP_RULE=$(printf '      {"type":"field","ip":["%s"],"outboundTag":"direct"},' "$VLESS_IP")

  info "Генерирую config.json..."
  cat > /tmp/kox_config.json << CONF
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
      ${VLESS_IP_RULE}
      {"type":"field","network":"udp","port":"53","outboundTag":"direct"},
      {
        "type": "field",
        "domain": [
          "domain:youtube.com",       "domain:youtu.be",           "domain:googlevideo.com",
          "domain:ytimg.com",         "domain:ggpht.com",          "domain:youtube-nocookie.com",
          "domain:youtube.googleapis.com",
          "domain:whatsapp.com",      "domain:whatsapp.net",       "domain:wa.me",
          "domain:web.whatsapp.com",
          "domain:twitter.com",       "domain:x.com",              "domain:t.co",
          "domain:twimg.com",
          "domain:instagram.com",     "domain:cdninstagram.com",   "domain:threads.net",
          "domain:facebook.com",      "domain:fbcdn.net",          "domain:fb.com",
          "domain:fbsbx.com",         "domain:messenger.com",      "domain:facebook.net",
          "domain:discord.com",       "domain:discord.gg",         "domain:discordapp.com",
          "domain:discordapp.net",    "domain:discord.media",
          "domain:tiktok.com",        "domain:tiktokcdn.com",      "domain:musical.ly",
          "domain:spotify.com",       "domain:scdn.co",            "domain:spotifycdn.com",
          "domain:netflix.com",       "domain:nflxext.com",        "domain:nflximg.net",
          "domain:nflxvideo.net",     "domain:nflxso.net",         "domain:fast.com",
          "domain:openai.com",        "domain:chatgpt.com",        "domain:oaiusercontent.com",
          "domain:oaistatic.com",     "domain:claude.ai",          "domain:anthropic.com",
          "domain:gstatic.com",       "domain:googleusercontent.com",
          "domain:accounts.google.com",                            "domain:gemini.google.com",
          "domain:steampowered.com",  "domain:steamcommunity.com", "domain:steamstatic.com",
          "domain:steamcontent.com",  "domain:steamgames.com",
          "domain:reddit.com",        "domain:redd.it",            "domain:redditmedia.com",
          "domain:redditstatic.com",
          "domain:linkedin.com",      "domain:licdn.com",
          "domain:pornhub.com",       "domain:phncdn.com",         "domain:xvideos.com",
          "domain:xnxx.com",          "domain:xhamster.com",       "domain:xhcdn.com",
          "domain:canva.com",
          "domain:bing.com",          "domain:bingapis.com",       "domain:copilot.microsoft.com",
          "domain:medium.com",        "domain:notion.so",          "domain:notion.site",
          "domain:figma.com",         "domain:figmacdn.com",
          "domain:zoom.us",           "domain:zoom.com",
          "domain:twitch.tv",         "domain:twitchcdn.net",      "domain:jtvnw.net",
          "domain:ttvnw.net",
          "domain:github.com",        "domain:github.io",          "domain:githubusercontent.com",
          "domain:githubassets.com",
          "domain:npmjs.com",         "domain:docker.io",          "domain:docker.com",
          "domain:stackoverflow.com", "domain:stackexchange.com",  "domain:gitlab.com",
          "domain:soundcloud.com",    "domain:sndcdn.com",
          "domain:viber.com",         "domain:signal.org",
          "domain:wikipedia.org",     "domain:wikimedia.org",      "domain:archive.org",
          "domain:bbc.com",           "domain:cnn.com",            "domain:nytimes.com",
          "domain:reuters.com",
          "domain:proton.me",         "domain:protonmail.com",
          "domain:snapchat.com",      "domain:snap.com",
          "domain:rutracker.org",     "domain:rutor.info",         "domain:nnmclub.to",
          "domain:telegram.org",      "domain:t.me",               "domain:tdesktop.com",
          "domain:core.telegram.org", "domain:api.telegram.org",   "domain:cdn.telegram.org",
          "domain:web.telegram.org",  "domain:telegram.me",        "domain:telegra.ph",
          "domain:graph.org",
          "domain:2ip.ru",            "domain:2ip.io",
          "domain:kox.nonamenebula.ru",
          "domain:kox-custom-marker"
        ],
        "outboundTag": "kox-proxy"
      },
      {
        "type": "field",
        "ip": [
          "31.13.24.0/21",  "31.13.64.0/18",  "157.240.0.0/17",  "157.240.192.0/18",
          "163.70.128.0/17","102.132.96.0/20", "129.134.0.0/17",  "185.60.216.0/22",
          "185.89.218.0/23","204.15.20.0/22",  "149.154.160.0/20","91.108.4.0/22",
          "91.108.8.0/22",  "91.108.12.0/22",  "91.108.16.0/22",  "91.108.20.0/22",
          "91.108.56.0/22", "95.161.64.0/20",  "185.76.151.0/24",
          "192.0.2.255/32"
        ],
        "outboundTag": "kox-proxy"
      },
      {"type":"field","network":"udp","outboundTag":"direct"},
      {"type":"field","network":"tcp","outboundTag":"direct"}
    ]
  }
}
CONF

  ok "config.json сгенерирован"

  # Сохранить параметры сервера для kox CLI
  cat > /tmp/kox.conf << KOXCONF
# KOX VPN — сохранённые параметры
# https://kox.nonamenebula.ru | t.me/PrivateProxyKox
KOX_SERVER="${VLESS_HOST}"
KOX_PORT="${VLESS_PORT}"
KOX_UUID="${VLESS_UUID}"
KOX_SNI="${VLESS_SNI}"
KOX_FLOW="${VLESS_FLOW}"
KOX_SUB_URL="${SUB_URL}"
KOX_INSTALLED="$(date '+%Y-%m-%d %H:%M')"
KOX_BOT_TOKEN=""
KOX_ADMIN_ID=""
KOXCONF
  cp /tmp/kox.conf /tmp/kox_conf_http.conf
  ok "kox.conf с параметрами сервера создан"

  cp /tmp/kox_config.json /tmp/kox_config_http.json

  if [ -z "$HTTP_PID" ] || ! kill -0 "$HTTP_PID" 2>/dev/null; then start_http_server; fi

  router "wget -q -O /opt/etc/xray/config.json http://${MY_LOCAL_IP}:8765/kox_config_http.json" || \
    die "Ошибка загрузки config.json на роутер"
  ok "config.json → /opt/etc/xray/config.json"

  router "wget -q -O /opt/etc/xray/kox.conf http://${MY_LOCAL_IP}:8765/kox_conf_http.conf" || true
  ok "kox.conf → /opt/etc/xray/kox.conf"

  info "Проверяю конфиг..."
  TEST_OUT=$(router "/opt/sbin/xray run -test -c /opt/etc/xray/config.json 2>&1" || echo "FAIL")
  echo "$TEST_OUT" | grep -q "Configuration OK" && ok "Конфиг KOX VPN — ${G}Configuration OK${N}" || \
    { echo "$TEST_OUT" | grep -qi "error\|fail" && { fail "Ошибка: $TEST_OUT"; die "config.json невалиден"; } || ok "Конфиг принят"; }
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 8: iptables
# ══════════════════════════════════════════════════════════════════════
phase_iptables() {
  step "8/10" "Правила iptables — KOX VPN прозрачный прокси"
  echo ""

  cat > /tmp/99-kox-nat.sh << 'NATSCRIPT'
#!/bin/sh
# KOX VPN — LAN трафик → Xray 10808 | kox.nonamenebula.ru
PATH=/opt/sbin:/opt/bin:/sbin:/usr/sbin:/usr/bin:/bin; export PATH
apply_v4() {
  iptables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null
  iptables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null
  iptables -t nat -F XRAY_REDIRECT 2>/dev/null; iptables -t nat -X XRAY_REDIRECT 2>/dev/null
  iptables -t nat -N XRAY_REDIRECT
  for NET in 0.0.0.0/8 127.0.0.0/8 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 224.0.0.0/4; do
    iptables -t nat -A XRAY_REDIRECT -d $NET -j RETURN
  done
  iptables -t nat -A XRAY_REDIRECT -p udp --dport 443 -j REDIRECT --to-ports 10808
  iptables -t nat -A XRAY_REDIRECT -p tcp -j REDIRECT --to-ports 10808
  iptables -t nat -I PREROUTING 1 -i br0 -p tcp -j XRAY_REDIRECT
  iptables -t nat -I PREROUTING 1 -i br0 -p udp --dport 443 -j XRAY_REDIRECT
}
apply_v6() {
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null
  ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null; ip6tables -t nat -X XRAY_REDIRECT 2>/dev/null
  ip6tables -t nat -N XRAY_REDIRECT
  for NET6 in ::1/128 fe80::/10 fc00::/7 ff00::/8; do
    ip6tables -t nat -A XRAY_REDIRECT -d $NET6 -j RETURN
  done
  ip6tables -t nat -A XRAY_REDIRECT -p udp --dport 443 -j REDIRECT --to-ports 10808
  ip6tables -t nat -A XRAY_REDIRECT -p tcp -j REDIRECT --to-ports 10808
  ip6tables -t nat -I PREROUTING 1 -i br0 -p tcp -j XRAY_REDIRECT
  ip6tables -t nat -I PREROUTING 1 -i br0 -p udp --dport 443 -j XRAY_REDIRECT
}
if [ -z "${table:-}" ] && [ -z "${type:-}" ]; then apply_v4; apply_v6 2>/dev/null || true; exit 0; fi
[ "${table:-}" != "nat" ] && exit 0
[ "${type:-}" = "iptables"  ] && apply_v4 && exit 0
[ "${type:-}" = "ip6tables" ] && { apply_v6 2>/dev/null || true; exit 0; }
exit 0
NATSCRIPT

  cat > /tmp/99-kox-wan.sh << 'WANSCRIPT'
#!/bin/sh
# KOX VPN — применить NAT после WAN | kox.nonamenebula.ru
[ "${1:-}" = "start" ] || exit 0; sleep 3
sh /opt/etc/ndm/netfilter.d/99-kox-nat.sh 2>/dev/null; exit 0
WANSCRIPT

  if [ -z "$HTTP_PID" ] || ! kill -0 "$HTTP_PID" 2>/dev/null; then start_http_server; fi

  router "mkdir -p /opt/etc/ndm/netfilter.d /opt/etc/ndm/wan.d"
  router "wget -q -O /opt/etc/ndm/netfilter.d/99-kox-nat.sh http://${MY_LOCAL_IP}:8765/99-kox-nat.sh && \
          chmod +x /opt/etc/ndm/netfilter.d/99-kox-nat.sh" || die "Ошибка загрузки netfilter-скрипта"
  ok "netfilter.d/99-kox-nat.sh установлен"
  router "wget -q -O /opt/etc/ndm/wan.d/99-kox-nat.sh http://${MY_LOCAL_IP}:8765/99-kox-wan.sh && \
          chmod +x /opt/etc/ndm/wan.d/99-kox-nat.sh" || die "Ошибка загрузки wan.d-скрипта"
  ok "wan.d/99-kox-nat.sh установлен"

  stop_http_server

  router "sh /opt/etc/ndm/netfilter.d/99-kox-nat.sh 2>/dev/null || true"
  CC=$(router "iptables -t nat -L XRAY_REDIRECT -n 2>/dev/null | grep -c REDIRECT || echo 0")
  [ "${CC:-0}" -ge 1 ] 2>/dev/null && ok "iptables XRAY_REDIRECT активна (${CC} правил)" || \
    warn "iptables не применились сейчас — применятся после перезагрузки"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 9: Установка kox CLI на роутер
# ══════════════════════════════════════════════════════════════════════
phase_install_kox_cli() {
  step "9/10" "Установка KOX VPN CLI на роутер (/opt/bin/kox)"
  echo ""
  info "Генерирую kox CLI..."

  # ── Генерируем скрипт /opt/bin/kox ─────────────────────────────────
  cat > /tmp/kox-cli.sh << 'KOXCLI'
#!#!/bin/sh
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
  printf "  ${C}🌐 $(hyperlink 'https://kox.nonamenebula.ru' 'kox.nonamenebula.ru')${N}\n"
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
KOXCLI

  cp /tmp/kox-cli.sh /tmp/kox-cli-http.sh

  if [ -z "$HTTP_PID" ] || ! kill -0 "$HTTP_PID" 2>/dev/null; then start_http_server; fi

  router "wget -q -O /opt/bin/kox http://${MY_LOCAL_IP}:8765/kox-cli-http.sh && chmod +x /opt/bin/kox" || \
    die "Ошибка установки kox CLI на роутер"

  stop_http_server

  # Проверить
  KOX_CHECK=$(router "/opt/bin/kox help 2>&1 | head -3" || echo "")
  echo "$KOX_CHECK" | grep -qi "kox\|vpn\|management" && \
    ok "kox CLI установлен и работает — ${W}/opt/bin/kox${N}" || \
    warn "kox CLI установлен, но проверка вернула неожиданный вывод"

  kox "На роутере теперь доступна команда ${C}kox${N}"
  kox "Введите ${G}kox help${N} для списка команд"
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 9.5: Telegram Bot (опционально)
# ══════════════════════════════════════════════════════════════════════
phase_telegram_bot() {
  step "9.5/10" "Telegram Bot KOX VPN (опционально)"
  echo ""
  echo -e "  ${M}★${N} Уникальная функция: управление роутером прямо из Telegram!"
  echo -e "  ${M}★${N} Канал: ${C}https://t.me/PrivateProxyKox${N}"
  echo -e "  ${M}★${N} Бот:   ${C}@kox_nonamenebula_bot${N}"
  echo ""
  warn "Для бота нужен токен от @BotFather и ваш Telegram ID"
  echo ""
  ask "Настроить Telegram бот? [y/N]: "
  echo -ne " →  "
  read -r TG_REPLY
  if [[ "${TG_REPLY,,}" != "y" ]]; then
    info "Пропускаю установку бота. Можно настроить позже через kox.conf"
    return 0
  fi

  # ── Получить токен бота ──────────────────────────────────────────
  echo ""
  echo -e "  ${W}Как получить токен:${N}"
  echo "    1. Откройте Telegram → @BotFather"
  echo "    2. Отправьте /newbot"
  echo "    3. Придумайте имя и username для бота"
  echo "    4. Скопируйте токен вида: 1234567890:AAF..."
  echo ""
  ask "Вставьте токен вашего бота:"
  echo -ne " →  "
  read -r TG_TOKEN
  [ -z "$TG_TOKEN" ] && warn "Токен не введён — пропускаю" && return 0
  echo "$TG_TOKEN" | grep -qE '^[0-9]+:AA[A-Za-z0-9_-]{30,}$' || { warn "Токен похож на неверный, но продолжаю..."; }

  # ── Получить Admin ID ────────────────────────────────────────────
  echo ""
  echo -e "  ${W}Как узнать ваш Telegram ID:${N}"
  echo "    Откройте Telegram → @userinfobot → нажмите /start"
  echo "    ID выглядит как число: 123456789"
  echo ""
  ask "Введите ваш Telegram ID (числовой):"
  echo -ne " →  "
  read -r TG_ADMIN_ID
  [ -z "$TG_ADMIN_ID" ] && warn "Admin ID не введён — пропускаю" && return 0
  echo "$TG_ADMIN_ID" | grep -qE '^[0-9]+$' || { warn "ID должен быть числом — пропускаю"; return 0; }

  ok "Токен: ...${TG_TOKEN: -8}"
  ok "Admin ID: ${TG_ADMIN_ID}"

  # ── Проверить токен через API ────────────────────────────────────
  info "Проверяю токен через Telegram API..."
  TG_ME=$(curl -sSL --max-time 10 "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null || echo "")
  if echo "$TG_ME" | grep -q '"ok":true'; then
    BOT_NAME=$(echo "$TG_ME" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    ok "Бот валиден: ${G}@${BOT_NAME}${N}"
  else
    warn "Не удалось проверить токен через API. Продолжаю..."
  fi

  # ── Установить curl и jq на роутере (нужны для бота) ────────────
  info "Проверяю curl на роутере..."
  if ! router "ls /opt/bin/curl" >/dev/null 2>&1; then
    info "Устанавливаю curl на роутере..."
    router "/opt/bin/opkg install curl >/dev/null 2>&1" || warn "Не удалось установить curl"
  fi
  router "ls /opt/bin/curl" >/dev/null 2>&1 && ok "curl доступен" || { warn "curl не найден — бот может не работать"; }

  info "Проверяю jq на роутере..."
  if ! router "ls /opt/bin/jq" >/dev/null 2>&1; then
    info "Устанавливаю jq (нужен для JSON в боте)..."
    router "/opt/bin/opkg install jq >/dev/null 2>&1" || warn "Не удалось установить jq — бот может работать некорректно"
  fi
  router "ls /opt/bin/jq" >/dev/null 2>&1 && ok "jq доступен" || warn "jq не найден — бот требует jq для корректной работы"

  # ── Обновить kox.conf с токеном ──────────────────────────────────
  router "sed -i 's|^KOX_BOT_TOKEN=.*|KOX_BOT_TOKEN=\"${TG_TOKEN}\"|' /opt/etc/xray/kox.conf 2>/dev/null || true"
  router "sed -i 's|^KOX_ADMIN_ID=.*|KOX_ADMIN_ID=\"${TG_ADMIN_ID}\"|' /opt/etc/xray/kox.conf 2>/dev/null || true"
  ok "kox.conf обновлён с токеном бота"

  # ── Создать скрипт бота ──────────────────────────────────────────
  info "Создаю Telegram бот скрипт..."

  cat > /tmp/kox-bot.sh << 'BOTSCRIPT'
##!/bin/sh
# KOX VPN Telegram Bot Daemon v3
# Bot API 9.4+: colored buttons, sticky menu, clean chat
# https://kox.nonamenebula.ru

KOXCONF="/opt/etc/xray/kox.conf"
CONF="/opt/etc/xray/config.json"
ERRLOG="/opt/var/log/xray-err.log"
BOT_LOG="/opt/var/log/kox-bot.log"
OFFSET_FILE="/tmp/kox-bot-offset"
LOCK_FILE="/tmp/kox-bot.lock"
WAIT_FILE="/tmp/kox-bot-wait"
# Sticky message: one message per chat, always edited in-place
STICKY_FILE="/tmp/kox-bot-sticky"
XRAY_INIT="/opt/etc/init.d/S24xray"
DOMAIN_MARKER="kox-custom-marker"
IP_MARKER="192.0.2.255/32"
PROXY="socks5h://127.0.0.1:10809"

PATH=/opt/sbin:/opt/bin:/sbin:/usr/sbin:/usr/bin:/bin
export PATH

# ── Lock ──────────────────────────────────────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
  OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then exit 1; fi
  rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE $WAIT_FILE; exit 0" INT TERM EXIT

# ── Config ────────────────────────────────────────────────────────────────────
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
BOT_TOKEN="${KOX_BOT_TOKEN:-}"; ADMIN_ID="${KOX_ADMIN_ID:-}"
[ -z "$BOT_TOKEN" ] && exit 1
API="https://api.telegram.org/bot${BOT_TOKEN}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$BOT_LOG"; }
log "Bot v3 started. Admin=${ADMIN_ID:-NONE}"

# ── Sticky message helpers ─────────────────────────────────────────────────────
sticky_save() { printf '%s' "$1" > "$STICKY_FILE"; }
sticky_load() { cat "$STICKY_FILE" 2>/dev/null || echo ""; }
sticky_clear() { rm -f "$STICKY_FILE"; }

# ── API Helpers ───────────────────────────────────────────────────────────────

# Build and POST to Telegram API, return response
api_call() {
  local METHOD="$1" PAYLOAD="$2"
  curl -s -m 20 -x "$PROXY" -X POST "${API}/${METHOD}" \
    -H "Content-Type: application/json" -d "$PAYLOAD" 2>/dev/null
}

answer_cb() {
  api_call "answerCallbackQuery" \
    "$(jq -cn --arg i "$1" --arg t "${2:- }" '{callback_query_id:$i,text:$t}')" \
    > /dev/null
}

send_typing() {
  api_call "sendChatAction" \
    "{\"chat_id\":${1},\"action\":\"typing\"}" > /dev/null
}

delete_msg() {
  local CHAT="$1" MID="$2"
  [ -z "$MID" ] || [ "$MID" = "null" ] && return
  api_call "deleteMessage" \
    "{\"chat_id\":${CHAT},\"message_id\":${MID}}" > /dev/null
}

# Edit the sticky message OR send new (and save as sticky)
update_menu() {
  local CHAT="$1" TEXT="$2" KBD="${3:-$(main_keyboard)}"
  local STICKY MID
  STICKY=$(sticky_load)

  # Try edit first
  if [ -n "$STICKY" ]; then
    local PAYLOAD
    PAYLOAD=$(jq -cn --argjson c "$CHAT" --argjson m "$STICKY" \
      --arg t "$TEXT" --argjson k "$KBD" \
      '{chat_id:$c,message_id:$m,text:$t,parse_mode:"HTML",reply_markup:$k}')
    local RES
    RES=$(api_call "editMessageText" "$PAYLOAD")
    if echo "$RES" | jq -e '.ok == true' >/dev/null 2>&1; then
      return  # Edited in-place — clean!
    fi
  fi

  # Fallback: send new message, save as sticky
  local PAYLOAD RES
  PAYLOAD=$(jq -cn --argjson c "$CHAT" --arg t "$TEXT" --argjson k "$KBD" \
    '{chat_id:$c,text:$t,parse_mode:"HTML",reply_markup:$k}')
  RES=$(api_call "sendMessage" "$PAYLOAD")
  MID=$(echo "$RES" | jq -r '.result.message_id // ""')
  [ -n "$MID" ] && sticky_save "$MID"
}

# Send informational message (long text, no keyboard) — separate from sticky
send_info() {
  local CHAT="$1" TEXT="$2"
  local PAYLOAD
  PAYLOAD=$(jq -cn --argjson c "$CHAT" --arg t "$TEXT" \
    '{chat_id:$c,text:$t,parse_mode:"HTML"}')
  api_call "sendMessage" "$PAYLOAD" > /dev/null
}

# ── Register bot commands (shows "/" menu in Telegram input) ──────────────────
setup_commands() {
  local CMDS
  CMDS=$(jq -cn '[
    {"command":"menu",    "description":"🔑 Главное меню управления VPN"},
    {"command":"status",  "description":"📊 Статус Xray и туннеля"},
    {"command":"on",      "description":"✅ Включить VPN туннель"},
    {"command":"off",     "description":"❌ Выключить VPN туннель"},
    {"command":"restart", "description":"🔄 Перезапустить Xray"},
    {"command":"add",     "description":"➕ Добавить домен в туннель"},
    {"command":"del",     "description":"➖ Удалить домен из туннеля"},
    {"command":"check",   "description":"🔍 Проверить маршрут домена"},
    {"command":"list",    "description":"📋 Список доменов в туннеле"},
    {"command":"log",     "description":"📝 Последние ошибки Xray"},
    {"command":"help",    "description":"❓ Справка по всем командам"}
  ]')
  local RES
  RES=$(api_call "setMyCommands" "{\"commands\":${CMDS}}")
  log "setMyCommands: $(echo "$RES" | jq -r '.ok')"
}

# ── Keyboard layouts (Bot API 9.4 colored buttons) ────────────────────────────
main_keyboard() {
  # style: "primary"=blue, "success"=green, "danger"=red
  printf '%s' '{
    "inline_keyboard":[
      [{"text":"📊 Статус","callback_data":"status","style":"primary"},
       {"text":"🌐 Сервер","callback_data":"server"}],
      [{"text":"✅ Вкл VPN","callback_data":"do_on","style":"success"},
       {"text":"❌ Выкл VPN","callback_data":"confirm_off","style":"danger"}],
      [{"text":"🔄 Рестарт Xray","callback_data":"confirm_restart","style":"danger"},
       {"text":"🔧 Тест конфига","callback_data":"test_config","style":"primary"}],
      [{"text":"📋 Домены","callback_data":"list"},
       {"text":"🔢 IP-список","callback_data":"list_ip"}],
      [{"text":"➕ Добавить домен","callback_data":"prompt_add","style":"success"},
       {"text":"➖ Удалить домен","callback_data":"prompt_del","style":"danger"}],
      [{"text":"🔍 Проверить домен","callback_data":"prompt_check"},
       {"text":"➕ Добавить IP","callback_data":"prompt_add_ip","style":"success"}],
      [{"text":"📝 Логи Xray","callback_data":"log"},
       {"text":"📈 Трафик","callback_data":"stats"}],
      [{"text":"💾 Бэкап","callback_data":"do_backup","style":"primary"},
       {"text":"🗑️ Очистить логи","callback_data":"confirm_clearlog","style":"danger"}],
      [{"text":"❓ Помощь","callback_data":"help"}]
    ]
  }'
}

confirm_keyboard() {
  printf '{"inline_keyboard":[[{"text":"✅ Да, подтверждаю","callback_data":"do_%s","style":"success"},{"text":"❌ Отмена","callback_data":"menu","style":"danger"}]]}' "$1"
}

back_keyboard() {
  printf '{"inline_keyboard":[[{"text":"◀️ Назад в меню","callback_data":"menu","style":"primary"}]]}'
}

# ── Handlers ──────────────────────────────────────────────────────────────────

h_status() {
  local CHAT="$1"
  send_typing "$CHAT"
  local XRAY_OK PORT_OK IPT_OK VPN_ST SRV CONN
  XRAY_OK=$(pgrep xray >/dev/null 2>&1 && echo "✅ запущен" || echo "❌ остановлен")
  PORT_OK=$(netstat -tlnp 2>/dev/null | grep -q 10808 && echo "✅" || echo "❌")
  IPT_OK=$(iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT && echo "✅" || echo "❌")
  VPN_ST=$([ -f /tmp/kox-vpn-off ] && echo "❌ ВЫКЛЮЧЕН" || echo "✅ ВКЛЮЧЕН")
  SRV=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')
  CONN=$(netstat -tn 2>/dev/null | grep -c :10808 2>/dev/null || echo 0)
  update_menu "$CHAT" "📊 <b>Статус KOX VPN</b>

Xray:         ${XRAY_OK}
Порт 10808:   ${PORT_OK}
iptables:     ${IPT_OK}
VPN туннель:  ${VPN_ST}
Сервер:       <code>${SRV:-?}</code>
Соединений:   <code>${CONN}</code>"
}

h_server() {
  local CHAT="$1"
  local SRV PORT UUID SNI FLOW
  SRV=$(grep -m1 '"address"' "$CONF" | sed 's/.*"address": *"\([^"]*\)".*/\1/')
  PORT=$(grep -m1 '"port"' "$CONF" | sed 's/.*"port": *\([0-9]*\).*/\1/')
  UUID=$(grep -m1 '"id"' "$CONF" | sed 's/.*"id": *"\([^"]*\)".*/\1/')
  SNI=$(grep -m1 '"serverName"' "$CONF" | sed 's/.*"serverName": *"\([^"]*\)".*/\1/')
  FLOW=$(grep -m1 '"flow"' "$CONF" | sed 's/.*"flow": *"\([^"]*\)".*/\1/')
  update_menu "$CHAT" "🌐 <b>VLESS сервер:</b>

Адрес: <code>${SRV:-?}</code>
Порт:  <code>${PORT:-443}</code>
UUID:  <code>${UUID:-?}</code>
SNI:   <code>${SNI:-}</code>
Flow:  <code>${FLOW:-}</code>"
}

h_on() {
  local CHAT="$1"
  NAT=$(ls /opt/etc/ndm/netfilter.d/*nat.sh 2>/dev/null | head -1)
  rm -f /tmp/kox-vpn-off
  if [ -n "$NAT" ] && sh "$NAT" 2>/dev/null; then
    update_menu "$CHAT" "✅ <b>VPN включён</b>

iptables правила применены.
Трафик идёт через VLESS туннель."
  else
    update_menu "$CHAT" "❌ Ошибка применения iptables правил"
  fi
}

h_off() {
  local CHAT="$1"
  touch /tmp/kox-vpn-off
  iptables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  iptables -t nat -X XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -X XRAY_REDIRECT 2>/dev/null || true
  update_menu "$CHAT" "❌ <b>VPN выключен</b>

Xray работает, но трафик идёт напрямую."
}

h_restart() {
  local CHAT="$1"
  send_typing "$CHAT"
  "$XRAY_INIT" restart >/dev/null 2>&1
  sleep 2
  if pgrep xray >/dev/null 2>&1; then
    update_menu "$CHAT" "🔄 <b>Xray перезапущен успешно</b>"
  else
    update_menu "$CHAT" "❌ <b>Xray не запустился!</b>
Нажмите 📝 Логи для диагностики."
  fi
}

h_test() {
  local CHAT="$1"
  send_typing "$CHAT"
  local RESULT
  RESULT=$(/opt/sbin/xray -test -config "$CONF" 2>&1 | tail -3)
  if echo "$RESULT" | grep -q "Configuration OK"; then
    update_menu "$CHAT" "🔧 <b>Тест конфига</b>

✅ Конфигурация корректна"
  else
    update_menu "$CHAT" "🔧 <b>Тест конфига</b>

❌ Ошибка:
<code>${RESULT}</code>"
  fi
}

h_list() {
  local CHAT="$1"
  send_typing "$CHAT"
  local COUNT
  COUNT=$(grep '"domain:' "$CONF" 2>/dev/null | grep -v 'kox-custom-marker' | wc -l | tr -d ' ')
  local DOMAINS
  DOMAINS=$(grep '"domain:' "$CONF" 2>/dev/null | grep -v 'kox-custom-marker' | \
    sed 's/.*"domain:\([^"]*\)".*/\1/' | sort | head -50)
  local NOTE=""
  [ "$COUNT" -gt 50 ] && NOTE="
<i>...первые 50 из ${COUNT}</i>"
  # Long content: send as separate info message, then update menu
  send_info "$CHAT" "📋 <b>Домены в туннеле (${COUNT}):</b>

<pre>${DOMAINS}</pre>${NOTE}"
  update_menu "$CHAT" "📋 Список доменов отправлен выше (${COUNT} шт.)"
}

h_list_ip() {
  local CHAT="$1"
  local IPS IPV6
  IPS=$(grep -E '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+"' "$CONF" 2>/dev/null | \
    grep -v '192\.0\.2\.255' | sed 's/.*"\([0-9./]*\)".*/\1/')
  IPV6=$(grep -E '"[0-9a-f:]+/[0-9]+"' "$CONF" 2>/dev/null | \
    sed 's/.*"\([0-9a-f:./]*\)".*/\1/')
  send_info "$CHAT" "🔢 <b>IP/подсети в туннеле:</b>

<b>IPv4:</b>
<pre>${IPS:-пусто}</pre>
<b>IPv6:</b>
<pre>${IPV6:-пусто}</pre>"
  update_menu "$CHAT" "🔢 Список IP отправлен выше"
}

h_log() {
  local CHAT="$1"
  send_typing "$CHAT"
  local LOGS
  LOGS=$(tail -25 "$ERRLOG" 2>/dev/null | grep -v "^$" | tail -c 3000)
  [ -z "$LOGS" ] && LOGS="Лог пуст — ошибок нет"
  send_info "$CHAT" "📝 <b>Последние ошибки Xray:</b>

<pre>${LOGS}</pre>"
  update_menu "$CHAT" "📝 Логи отправлены выше"
}

h_stats() {
  local CHAT="$1"
  send_typing "$CHAT"
  local CONN ERRSIZE ACCSIZE IPT_TCP IPT_UDP
  CONN=$(netstat -tn 2>/dev/null | grep -c :10808 2>/dev/null || echo 0)
  ERRSIZE=$(ls -lh "$ERRLOG" 2>/dev/null | awk '{print $5}' || echo "0B")
  ACCSIZE=$(ls -lh /opt/var/log/xray-acc.log 2>/dev/null | awk '{print $5}' || echo "0B")
  IPT_TCP=$(iptables -t nat -vL XRAY_REDIRECT 2>/dev/null | \
    grep "REDIRECT.*tcp" | awk '{print $1" пак / "$2}')
  IPT_UDP=$(iptables -t nat -vL XRAY_REDIRECT 2>/dev/null | \
    grep "REDIRECT.*udp" | awk '{print $1" пак / "$2}')
  update_menu "$CHAT" "📈 <b>Статистика трафика:</b>

Соединений через Xray: <code>${CONN}</code>

iptables TCP: <code>${IPT_TCP:-?}</code>
iptables UDP: <code>${IPT_UDP:-?}</code>

err.log:  <code>${ERRSIZE}</code>
acc.log:  <code>${ACCSIZE}</code>"
}

h_backup() {
  local CHAT="$1"
  send_typing "$CHAT"
  mkdir -p /opt/etc/xray/backups
  local TS
  TS=$(date +%Y%m%d_%H%M%S)
  cp "$CONF" "/opt/etc/xray/backups/config_${TS}.json"
  update_menu "$CHAT" "💾 <b>Бэкап создан</b>

<code>config_${TS}.json</code>"
}

h_clearlog() {
  local CHAT="$1"
  printf '' > "$ERRLOG" 2>/dev/null || true
  printf '' > "/opt/var/log/xray-acc.log" 2>/dev/null || true
  printf '' > "$BOT_LOG" 2>/dev/null || true
  update_menu "$CHAT" "🗑️ <b>Логи очищены</b>

xray-err.log, xray-acc.log, kox-bot.log обнулены."
}

h_add_domain() {
  local CHAT="$1" DOM="$2"
  if grep -qF "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    update_menu "$CHAT" "⚠️ Домен <code>${DOM}</code> уже в списке"
  elif grep -q "$DOMAIN_MARKER" "$CONF"; then
    awk -v d="$DOM" -v m="$DOMAIN_MARKER" \
      'index($0,m)>0{print "          \"domain:"d"\","}{print}' \
      "$CONF" > /tmp/kox-tmp.json && mv /tmp/kox-tmp.json "$CONF"
    "$XRAY_INIT" restart >/dev/null 2>&1
    update_menu "$CHAT" "✅ <code>${DOM}</code> добавлен, Xray перезапущен"
  else
    update_menu "$CHAT" "❌ Маркер не найден в конфиге"
  fi
}

h_del_domain() {
  local CHAT="$1" DOM="$2"
  if grep -qF "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    grep -vF "\"domain:${DOM}\"" "$CONF" > /tmp/kox-tmp.json && \
      mv /tmp/kox-tmp.json "$CONF"
    "$XRAY_INIT" restart >/dev/null 2>&1
    update_menu "$CHAT" "✅ <code>${DOM}</code> удалён, Xray перезапущен"
  else
    update_menu "$CHAT" "⚠️ Домен <code>${DOM}</code> не найден"
  fi
}

h_check_domain() {
  local CHAT="$1" DOM="$2"
  if grep -qF "\"domain:${DOM}\"" "$CONF" 2>/dev/null; then
    update_menu "$CHAT" "✅ <code>${DOM}</code> → через туннель VPN"
  else
    update_menu "$CHAT" "ℹ️ <code>${DOM}</code> → прямое соединение"
  fi
}

h_add_ip() {
  local CHAT="$1" IP="$2"
  if grep -qF "\"${IP}\"" "$CONF" 2>/dev/null; then
    update_menu "$CHAT" "⚠️ IP <code>${IP}</code> уже в конфиге"
  elif grep -q "$IP_MARKER" "$CONF"; then
    awk -v ip="$IP" -v m="$IP_MARKER" \
      'index($0,m)>0{print "          \""ip"\","}{print}' \
      "$CONF" > /tmp/kox-tmp.json && mv /tmp/kox-tmp.json "$CONF"
    "$XRAY_INIT" restart >/dev/null 2>&1
    update_menu "$CHAT" "✅ IP <code>${IP}</code> добавлен, Xray перезапущен"
  else
    update_menu "$CHAT" "❌ IP маркер не найден в конфиге"
  fi
}

h_help() {
  local CHAT="$1"
  update_menu "$CHAT" "❓ <b>KOX VPN Bot — справка</b>

<b>Меню кнопок:</b>
📊 Статус — Xray, iptables, VPN
🌐 Сервер — параметры VLESS
✅ Вкл / ❌ Выкл — туннель
🔄 Рестарт — перезапуск Xray <i>(с подтверждением)</i>
🔧 Тест — проверка config.json
📋 Домены — полный список
🔢 IP-список — IP/CIDR подсети
➕/➖ Домен, IP — управление маршрутами
🔍 Проверить — маршрут домена
📝 Логи — ошибки Xray
📈 Трафик — iptables счётчики
💾 Бэкап — сохранить конфиг
🗑️ Очистить — обнулить логи

<b>Команды (набрать вручную):</b>
<code>/add example.com</code>
<code>/del example.com</code>
<code>/check example.com</code>
<code>/status</code>  <code>/on</code>  <code>/off</code>

🔗 <a href=\"https://t.me/PrivateProxyKox\">t.me/PrivateProxyKox</a>"
}

# ── Main polling loop ─────────────────────────────────────────────────────────
# Register bot commands on start (shows "/" menu in Telegram)
setup_commands

OFFSET=0
[ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)

while true; do
  # Reload config each cycle
  if [ -f "$KOXCONF" ]; then
    . "$KOXCONF" 2>/dev/null
    ADMIN_ID="${KOX_ADMIN_ID:-}"
    [ -n "$KOX_BOT_TOKEN" ] && API="https://api.telegram.org/bot${KOX_BOT_TOKEN}"
  fi

  RESPONSE=$(curl -s -m 35 -x "$PROXY" \
    "${API}/getUpdates?offset=${OFFSET}&timeout=30&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D" \
    2>/dev/null)

  [ -z "$RESPONSE" ] && sleep 5 && continue

  if ! echo "$RESPONSE" | jq -e '.ok == true' >/dev/null 2>&1; then
    log "API error: $(echo "$RESPONSE" | jq -r '.description // "?"' 2>/dev/null)"
    sleep 15; continue
  fi

  COUNT=$(echo "$RESPONSE" | jq '.result | length' 2>/dev/null || echo 0)
  [ "$COUNT" = "0" ] && continue

  i=0
  while [ "$i" -lt "$COUNT" ]; do
    UPDATE=$(echo "$RESPONSE" | jq ".result[$i]" 2>/dev/null)
    UPDATE_ID=$(echo "$UPDATE" | jq -r '.update_id')

    IS_CB=0; CB_ID=""; MSG_ID=""; USER_MSG_ID=""
    if echo "$UPDATE" | jq -e '.callback_query' >/dev/null 2>&1; then
      CB_ID=$(echo "$UPDATE"   | jq -r '.callback_query.id')
      FROM_ID=$(echo "$UPDATE" | jq -r '.callback_query.from.id')
      CHAT_ID=$(echo "$UPDATE" | jq -r '.callback_query.message.chat.id')
      MSG_ID=$(echo "$UPDATE"  | jq -r '.callback_query.message.message_id')
      TEXT=$(echo "$UPDATE"    | jq -r '.callback_query.data // ""')
      IS_CB=1
      # The callback message IS our sticky menu
      sticky_save "$MSG_ID"
    elif echo "$UPDATE" | jq -e '.message' >/dev/null 2>&1; then
      FROM_ID=$(echo "$UPDATE"    | jq -r '.message.from.id')
      CHAT_ID=$(echo "$UPDATE"    | jq -r '.message.chat.id')
      TEXT=$(echo "$UPDATE"       | jq -r '.message.text // ""')
      USER_MSG_ID=$(echo "$UPDATE"| jq -r '.message.message_id')
    else
      i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"; continue
    fi

    log "From=$FROM_ID CB=$IS_CB '$(printf '%s' "$TEXT" | cut -c1-40)'"

    # ── No admin: respond to everyone with their ID ────────────────────
    if [ -z "$ADMIN_ID" ]; then
      [ "$IS_CB" = "1" ] && answer_cb "$CB_ID" "Настройте администратора"
      # Delete user message for clean chat
      [ -n "$USER_MSG_ID" ] && delete_msg "$CHAT_ID" "$USER_MSG_ID"
      sticky_clear
      update_menu "$CHAT_ID" "⚠️ <b>KOX VPN Bot не настроен</b>

Ваш Telegram ID: <code>${FROM_ID}</code>

Введите на роутере:
<code>kox admin set ${FROM_ID}</code>

После этого бот будет отвечать только вам." \
        '{"inline_keyboard":[]}'
      i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"; continue
    fi

    # ── Admin-only ────────────────────────────────────────────────────────
    if [ "$FROM_ID" != "$ADMIN_ID" ]; then
      log "Ignored non-admin $FROM_ID"
      i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"; continue
    fi

    # ── ACK callback ──────────────────────────────────────────────────────
    [ "$IS_CB" = "1" ] && answer_cb "$CB_ID" "⏳"

    # ── Delete user text messages for clean chat ──────────────────────────
    [ "$IS_CB" = "0" ] && [ -n "$USER_MSG_ID" ] && delete_msg "$CHAT_ID" "$USER_MSG_ID"

    # ── Wait for domain/IP input ──────────────────────────────────────────
    if [ "$IS_CB" = "0" ] && [ -f "$WAIT_FILE" ]; then
      WAIT_DATA=$(cat "$WAIT_FILE")
      WAIT_CMD=$(printf '%s' "$WAIT_DATA" | cut -d'|' -f1)
      WAIT_CHAT=$(printf '%s' "$WAIT_DATA" | cut -d'|' -f2)
      if [ "$CHAT_ID" = "$WAIT_CHAT" ] && [ -n "$TEXT" ] \
          && ! printf '%s' "$TEXT" | grep -q '^/'; then
        rm -f "$WAIT_FILE"
        case "$WAIT_CMD" in
          add)    h_add_domain   "$CHAT_ID" "$TEXT" ;;
          del)    h_del_domain   "$CHAT_ID" "$TEXT" ;;
          check)  h_check_domain "$CHAT_ID" "$TEXT" ;;
          add_ip) h_add_ip       "$CHAT_ID" "$TEXT" ;;
        esac
        i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"; continue
      fi
    fi

    # ── Command dispatch ──────────────────────────────────────────────────
    CMD=$(printf '%s' "$TEXT" | awk '{print $1}')
    ARG=$(printf '%s' "$TEXT" | sed 's/^[^ ]* *//')

    case "$CMD" in
      # Navigation
      /start|/menu|menu)
        update_menu "$CHAT_ID" \
          "🔑 <b>KOX VPN — управление роутером</b>

Выберите действие:" "$(main_keyboard)"
        ;;

      # Info
      status|/status)    h_status "$CHAT_ID" ;;
      server|/server)    h_server "$CHAT_ID" ;;
      stats|/stats)      h_stats  "$CHAT_ID" ;;
      test_config)       h_test   "$CHAT_ID" ;;

      # VPN control
      do_on)             h_on      "$CHAT_ID" ;;
      confirm_off)
        update_menu "$CHAT_ID" \
          "⚠️ <b>Выключить VPN?</b>

Трафик пойдёт напрямую, заблокированные сайты станут недоступны." \
          "$(confirm_keyboard off)"
        ;;
      do_off)            h_off     "$CHAT_ID" ;;
      /on)               h_on      "$CHAT_ID" ;;
      /off)              h_off     "$CHAT_ID" ;;

      confirm_restart)
        update_menu "$CHAT_ID" \
          "⚠️ <b>Перезапустить Xray?</b>

VPN прервётся примерно на 2 секунды." \
          "$(confirm_keyboard restart)"
        ;;
      do_restart)        h_restart "$CHAT_ID" ;;
      /restart)          h_restart "$CHAT_ID" ;;

      # Domains
      list|/list)        h_list       "$CHAT_ID" ;;
      list_ip)           h_list_ip    "$CHAT_ID" ;;
      log|/log)          h_log        "$CHAT_ID" ;;

      prompt_add)
        printf '%s' "add|${CHAT_ID}" > "$WAIT_FILE"
        update_menu "$CHAT_ID" \
          "➕ <b>Добавить домен в туннель</b>

Введите домен (например: <code>example.com</code>):" \
          "$(back_keyboard)"
        ;;
      prompt_del)
        printf '%s' "del|${CHAT_ID}" > "$WAIT_FILE"
        update_menu "$CHAT_ID" "➖ <b>Удалить домен</b>

Введите домен для удаления из туннеля:" "$(back_keyboard)"
        ;;
      prompt_check)
        printf '%s' "check|${CHAT_ID}" > "$WAIT_FILE"
        update_menu "$CHAT_ID" "🔍 <b>Проверить маршрут</b>

Введите домен для проверки:" "$(back_keyboard)"
        ;;
      prompt_add_ip)
        printf '%s' "add_ip|${CHAT_ID}" > "$WAIT_FILE"
        update_menu "$CHAT_ID" \
          "➕ <b>Добавить IP/подсеть</b>

Введите IP или CIDR (например: <code>1.2.3.0/24</code>):" \
          "$(back_keyboard)"
        ;;

      add|/add)
        if [ -n "$ARG" ]; then h_add_domain "$CHAT_ID" "$ARG"
        else
          printf '%s' "add|${CHAT_ID}" > "$WAIT_FILE"
          update_menu "$CHAT_ID" "➕ Введите домен для добавления:" "$(back_keyboard)"
        fi ;;
      del|/del)
        if [ -n "$ARG" ]; then h_del_domain "$CHAT_ID" "$ARG"
        else
          printf '%s' "del|${CHAT_ID}" > "$WAIT_FILE"
          update_menu "$CHAT_ID" "➖ Введите домен для удаления:" "$(back_keyboard)"
        fi ;;
      check|/check)
        if [ -n "$ARG" ]; then h_check_domain "$CHAT_ID" "$ARG"
        else
          printf '%s' "check|${CHAT_ID}" > "$WAIT_FILE"
          update_menu "$CHAT_ID" "🔍 Введите домен для проверки:" "$(back_keyboard)"
        fi ;;

      # Maintenance
      do_backup)         h_backup   "$CHAT_ID" ;;
      confirm_clearlog)
        update_menu "$CHAT_ID" \
          "⚠️ <b>Очистить все логи?</b>

Будут обнулены: xray-err.log, xray-acc.log, kox-bot.log" \
          "$(confirm_keyboard clearlog)"
        ;;
      do_clearlog)       h_clearlog "$CHAT_ID" ;;

      help|/help)        h_help     "$CHAT_ID" ;;

      # "Back to menu" from confirm/prompt screens
      menu)
        rm -f "$WAIT_FILE"
        update_menu "$CHAT_ID" \
          "🔑 <b>KOX VPN — управление роутером</b>

Выберите действие:" "$(main_keyboard)"
        ;;

      *)
        update_menu "$CHAT_ID" "❓ Используйте кнопки меню:" "$(main_keyboard)"
        ;;
    esac

    i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"
  done
done
BOTSCRIPT

  # ── Создать init.d сервис для бота ──────────────────────────────
  cat > /tmp/S90kox-bot.sh << 'BOTSVC'
##!/bin/sh
# KOX VPN Telegram Bot — Entware init.d service

PATH=/opt/sbin:/opt/bin:/sbin:/usr/sbin:/usr/bin:/bin
export PATH

DAEMON=/opt/bin/kox-bot
PID_FILE=/tmp/kox-bot.lock
LOG_FILE=/opt/var/log/kox-bot.log
DESC="KOX Telegram Bot"

start() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "$DESC already running (PID $(cat "$PID_FILE"))"
    return 0
  fi
  rm -f "$PID_FILE"
  echo "Starting $DESC..."
  $DAEMON >> "$LOG_FILE" 2>&1 &
  sleep 2
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "$DESC started (PID $(cat "$PID_FILE"))"
  else
    echo "$DESC FAILED to start! Check $LOG_FILE"
    return 1
  fi
}

stop() {
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null
      sleep 1
      kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    echo "$DESC stopped"
  else
    echo "$DESC is not running"
  fi
}

restart() {
  stop
  sleep 1
  start
}

status() {
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "$DESC is running (PID $(cat "$PID_FILE"))"
    echo "Last log:"
    tail -3 "$LOG_FILE" 2>/dev/null | sed 's/^/  /'
    return 0
  else
    echo "$DESC is NOT running"
    return 1
  fi
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) restart ;;
  status)  status ;;
  *)       echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
BOTSVC

  # Загрузить на роутер
  cp /tmp/kox-bot.sh /tmp/kox-bot-http.sh
  cp /tmp/S90kox-bot.sh /tmp/S90kox-bot-http.sh

  if [ -z "$HTTP_PID" ] || ! kill -0 "$HTTP_PID" 2>/dev/null; then start_http_server; fi

  router "wget -q -O /opt/bin/kox-bot http://${MY_LOCAL_IP}:8765/kox-bot-http.sh && chmod +x /opt/bin/kox-bot" || \
    { warn "Ошибка загрузки бота на роутер"; return 1; }
  ok "kox-bot → /opt/bin/kox-bot"

  router "wget -q -O /opt/etc/init.d/S90kox-bot http://${MY_LOCAL_IP}:8765/S90kox-bot-http.sh && chmod +x /opt/etc/init.d/S90kox-bot" || \
    { warn "Ошибка загрузки init.d сервиса"; return 1; }
  ok "S90kox-bot → /opt/etc/init.d/S90kox-bot"

  stop_http_server

  # Запустить бота
  info "Запускаю Telegram бот..."
  router "/opt/etc/init.d/S90kox-bot start 2>/dev/null || true"
  sleep 3

  BOT_RUN=$(router "pgrep -f kox-bot >/dev/null 2>&1 && echo RUNNING || echo STOPPED")
  if [[ "${BOT_RUN:-}" == *"RUNNING"* ]]; then
    ok "Telegram бот запущен!"
    kox "Проверьте: напишите боту ${C}@${BOT_NAME:-kox_nonamenebula_bot}${N} в Telegram"
    kox "Отправьте ${G}/start${N} — бот ответит только вам (Admin ID: $TG_ADMIN_ID)"
  else
    warn "Бот не запустился сразу. Проверьте: /opt/etc/init.d/S90kox-bot status"
  fi
}

# ══════════════════════════════════════════════════════════════════════
# ШАГ 10: Запуск и финальная проверка
# ══════════════════════════════════════════════════════════════════════
phase_start_and_verify() {
  step "10/10" "Запуск и проверка KOX VPN"
  echo ""

  router "sed -i 's/^ENABLED=no/ENABLED=yes/' /opt/etc/init.d/S24xray 2>/dev/null || true"
  info "Перезапускаю Xray..."
  router "/opt/etc/init.d/S24xray stop 2>/dev/null; sleep 2; /opt/etc/init.d/S24xray start 2>/dev/null || true"
  sleep 4

  echo -e "\n  ${W}Результаты проверки:${N}"
  sep

  PORT_CHECK=$(router "netstat -ln 2>/dev/null | grep ':10808' | head -1" || echo "")
  [ -n "$PORT_CHECK" ] && ok "1/4  Xray слушает порт 10808" || { fail "1/4  Порт 10808 не занят"; warn "     kox log — для диагностики"; }

  CC=$(router "iptables -t nat -L XRAY_REDIRECT -n 2>/dev/null | grep -c REDIRECT || echo 0")
  [ "${CC:-0}" -ge 1 ] 2>/dev/null && ok "2/4  iptables XRAY_REDIRECT активна (${CC} правил)" || fail "2/4  iptables правила не найдены"

  if [ -n "${VLESS_IP:-}" ]; then
    TCP=$(router "nc -z -w 5 $VLESS_HOST $VLESS_PORT 2>/dev/null && echo OK || echo FAIL" || echo "FAIL")
    [[ "$TCP" == *"OK"* ]] && ok "3/4  KOX VPN сервер ${VLESS_HOST}:${VLESS_PORT} — доступен" || fail "3/4  Сервер недоступен с роутера"
  else
    info "3/4  IP сервера неизвестен — пропускаю"
  fi

  sleep 3
  LOG=$(router "tail -15 /opt/var/log/kox-err.log 2>/dev/null || echo NOLOG")
  if echo "$LOG" | grep -q "tunneling request"; then
    ok "4/4  KOX VPN активен — туннелированный трафик обнаружен ✓"
  elif echo "$LOG" | grep -q "NOLOG"; then
    warn "4/4  Лог пуст — откройте youtube.com в браузере для теста"
  elif echo "$LOG" | grep -qi "error\|failed"; then
    fail "4/4  Ошибки в логе: $(echo "$LOG" | grep -i "error\|failed" | tail -2)"
  else
    ok "4/4  Xray работает, ошибок нет"
  fi
  sep
}

# ══════════════════════════════════════════════════════════════════════
# ИТОГ
# ══════════════════════════════════════════════════════════════════════
show_summary() {
  echo ""
  echo -e "${B}"
  echo '  ╔══════════════════════════════════════════════════════╗'
  echo '  ║                                                      ║'
  echo '  ║   ★  KOX VPN успешно установлен!  ★                 ║'
  echo '  ║      kox.nonamenebula.ru                             ║'
  echo '  ╚══════════════════════════════════════════════════════╝'
  echo -e "${N}"
  echo -e "  ${M}★${N} Сайт:         ${C}https://kox.nonamenebula.ru${N}"
  echo -e "  ${M}★${N} Роутер:       ${W}$ROUTER_IP${N}"
  echo -e "  ${M}★${N} KOX сервер:   ${W}$VLESS_HOST:$VLESS_PORT${N}"
  echo -e "  ${M}★${N} Xray порт:    ${W}10808${N}"
  echo ""
  sep
  echo -e "  ${W}Проверка туннеля:${N}"
  echo -e "  1. Откройте ${C}https://2ip.ru${N} — IP должен быть не домашний"
  echo -e "  2. YouTube, Instagram, Telegram — работают"
  echo -e "  3. gosuslugi.ru, sber.ru — идут через домашний IP"
  sep
  echo -e "  ${W}Управление KOX VPN (SSH на роутер):${N}"
  echo -e "  ${C}ssh root@$ROUTER_IP -p ${ROUTER_SSH_PORT}${N}"
  echo ""
  echo -e "  ${G}kox${N}                      — показать все команды"
  echo -e "  ${G}kox status${N}               — статус: Xray, iptables, сервер"
  echo -e "  ${G}kox on${N} / ${G}kox off${N}        — включить / выключить VPN"
  echo -e "  ${G}kox add${N} ${Y}example.com${N}     — добавить домен (работает сразу)"
  echo -e "  ${G}kox del${N} ${Y}example.com${N}     — убрать домен"
  echo -e "  ${G}kox check${N} ${Y}example.com${N}   — в туннеле или нет?"
  echo -e "  ${G}kox list${N}                 — все домены"
  echo -e "  ${G}kox add-ip${N} ${Y}1.2.3.0/24${N}  — добавить IP-сеть"
  echo -e "  ${G}kox server${N}               — инфо о VLESS-сервере"
  echo -e "  ${G}kox log${N} / ${G}kox log-live${N}  — логи"
  echo -e "  ${G}kox clear-log${N}            — очистить логи"
  echo -e "  ${G}kox restart${N}              — перезапуск Xray"
  sep
  echo -e "  ${G}kox cron-on${N}              — автообновление списка"
  echo -e "  ${G}kox backup${N} / ${G}kox restore${N}  — резервная копия"
  echo -e "  ${G}kox stats${N}                — статистика трафика"
  sep
  echo -e "  ${M}★${N} Подписки и поддержка: ${C}https://kox.nonamenebula.ru${N}"
  echo -e "  ${M}★${N} Канал: ${C}https://t.me/PrivateProxyKox${N}"
  echo -e "  ${M}★${N} Бот:   ${C}@kox_nonamenebula_bot${N}"
  echo ""
}

# ══════════════════════════════════════════════════════════════════════
# ТОЧКА ВХОДА
# ══════════════════════════════════════════════════════════════════════
main() {
  banner
  phase_deps
  phase_mode_select
  phase_subscription
  phase_router_input
  phase_connect

  if ! ${SKIP_DETECT:-false}; then
    phase_detect
  else
    FOUND_KVAS=false; FOUND_SS=false; FOUND_SINGBOX=false
    FOUND_XRAY=$(router "ls /opt/sbin/xray" >/dev/null 2>&1 && echo true || echo false)
  fi

  ${SKIP_CLEANUP:-false} || phase_cleanup

  phase_install
  phase_configure
  phase_iptables
  phase_install_kox_cli
  phase_telegram_bot
  phase_start_and_verify
  show_summary
}

main "$@"
