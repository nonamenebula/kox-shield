#!/bin/sh
# KOX Shield Telegram Bot Daemon v3
# Bot API 9.4+: colored buttons, sticky menu, clean chat
# https://kox.nonamenebula.ru

KOX_VERSION="2026.05.02"

KOXCONF="/opt/etc/xray/kox.conf"
CONF="/opt/etc/xray/config.json"
ERRLOG="/opt/var/log/xray-err.log"
BOT_LOG="/opt/var/log/kox-bot.log"
# Persistent offset: survives reboots, prevents old callback replay
OFFSET_FILE="/opt/etc/xray/.kox-bot-offset"
LOCK_FILE="/tmp/kox-bot.lock"
WAIT_FILE="/tmp/kox-bot-wait"
# Sticky message: one message per chat, always edited in-place
STICKY_FILE="/opt/etc/xray/.kox-bot-sticky"
XRAY_INIT="/opt/etc/init.d/S24xray"
DOMAIN_MARKER="kox-custom-marker"
IP_MARKER="192.0.2.255/32"
PROXY="socks5h://127.0.0.1:10809"
GITHUB_LISTS="https://raw.githubusercontent.com/nonamenebula/kox-shield/main/lists"
GITHUB_RAW="https://raw.githubusercontent.com/nonamenebula/kox-shield/main"
KOX_LISTS_DIR="/opt/etc/xray/lists"
KOX_LASTCHECK_FILE="/opt/etc/xray/.kox-ver-lastcheck"
LISTS_LASTCHECK_FILE="/opt/etc/xray/.lists-lastcheck"
CHECK_INTERVAL=21600  # 6 hours

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

# ── Smart curl: proxy first, then direct fallback ─────────────────────────────
# Tracks which mode is working to avoid repeated fallback overhead
_CURL_MODE="proxy"  # proxy | direct

tg_curl() {
  local RESULT=""
  if [ "$_CURL_MODE" = "proxy" ]; then
    RESULT=$(curl -s "$@" -x "$PROXY" 2>/dev/null)
    if [ -z "$RESULT" ]; then
      # Proxy failed — try direct
      RESULT=$(curl -s "$@" 2>/dev/null)
      if [ -n "$RESULT" ]; then
        [ "$_CURL_MODE" != "direct" ] && log "WARN: proxy unavailable, using direct connection"
        _CURL_MODE="direct"
      fi
    fi
  else
    # Already in direct mode — try direct first, retry proxy periodically
    RESULT=$(curl -s "$@" 2>/dev/null)
    if [ -z "$RESULT" ]; then
      RESULT=$(curl -s "$@" -x "$PROXY" 2>/dev/null)
      [ -n "$RESULT" ] && _CURL_MODE="proxy" && log "INFO: proxy connection restored"
    fi
  fi
  printf '%s' "$RESULT"
}

# ── API Helpers ───────────────────────────────────────────────────────────────

# Build and POST to Telegram API, return response
api_call() {
  local METHOD="$1" PAYLOAD="$2"
  tg_curl -m 20 -X POST "${API}/${METHOD}" \
    -H "Content-Type: application/json" -d "$PAYLOAD"
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
  printf '%s' '{
    "inline_keyboard":[
      [{"text":"📊 Статус","callback_data":"status"},
       {"text":"🌐 Серверы →","callback_data":"servers_menu"}],
      [{"text":"✅ Вкл VPN","callback_data":"do_on"},
       {"text":"❌ Выкл VPN","callback_data":"confirm_off"}],
      [{"text":"🔄 Рестарт Xray","callback_data":"confirm_restart"},
       {"text":"🔧 Тест конфига","callback_data":"test_config"}],
      [{"text":"📋 Домены и IP  →","callback_data":"domains_menu"},
       {"text":"🛠 Инструменты  →","callback_data":"tools_menu"}],
      [{"text":"⚙️ Настройки","callback_data":"settings"},
       {"text":"❓ Помощь","callback_data":"help"}]
    ]
  }'
}

domains_keyboard() {
  printf '%s' '{
    "inline_keyboard":[
      [{"text":"📋 Список доменов","callback_data":"list"},
       {"text":"🔢 IP-список","callback_data":"list_ip"}],
      [{"text":"➕ Добавить домен","callback_data":"prompt_add"},
       {"text":"➖ Удалить домен","callback_data":"prompt_del"}],
      [{"text":"🔍 Проверить домен","callback_data":"prompt_check"},
       {"text":"➕ Добавить IP","callback_data":"prompt_add_ip"}],
      [{"text":"◀️ Главное меню","callback_data":"menu"}]
    ]
  }'
}

tools_keyboard() {
  printf '%s' '{
    "inline_keyboard":[
      [{"text":"📝 Логи Xray","callback_data":"log"},
       {"text":"📈 Трафик","callback_data":"stats"}],
      [{"text":"💾 Бэкап","callback_data":"do_backup"},
       {"text":"🗑️ Очистить логи","callback_data":"confirm_clearlog"}],
      [{"text":"◀️ Главное меню","callback_data":"menu"}]
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
  update_menu "$CHAT" "📊 <b>Статус KOX Shield</b>  <i>v${KOX_VERSION}</i>

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

# ── Server menu: current info + switch option ──────────────────────────────
h_servers_menu() {
  local CHAT="$1"
  local SRV PORT UUID SNI SUB_URL
  SRV=$(grep -m1 '"address"' "$CONF" | sed 's/.*"address": *"\([^"]*\)".*/\1/')
  PORT=$(grep -m1 '"port"' "$CONF" | sed 's/.*"port": *\([0-9]*\).*/\1/')
  UUID=$(grep -m1 '"id"' "$CONF" | sed 's/.*"id": *"\([^"]*\)".*/\1/')
  SNI=$(grep -m1 '"serverName"' "$CONF" | sed 's/.*"serverName": *"\([^"]*\)".*/\1/')
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
  SUB_URL="${KOX_SUB_URL:-}"

  local KBD
  if [ -n "$SUB_URL" ]; then
    KBD='{"inline_keyboard":[[{"text":"🔀 Сменить сервер из подписки","callback_data":"switch_list"}],[{"text":"◀️ Главное меню","callback_data":"menu"}]]}'
  else
    KBD='{"inline_keyboard":[[{"text":"◀️ Главное меню","callback_data":"menu"}]]}'
  fi

  update_menu "$CHAT" "🌐 <b>Текущий VLESS сервер:</b>

Адрес: <code>${SRV:-?}</code>
Порт:  <code>${PORT:-443}</code>
UUID:  <code>${UUID:-?}</code>
SNI:   <code>${SNI:-}</code>
Подписка: <code>${SUB_URL:-не задана}</code>" "$KBD"
}

# URL-decode %XX encoded string (handles UTF-8 / emoji, no python3 needed)
urldecode() {
  printf "%b" "$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')"
}

# Fetch subscription, show servers with names + ping
h_switch_list() {
  local CHAT="$1"
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
  local SUB_URL="${KOX_SUB_URL:-}"

  if [ -z "$SUB_URL" ]; then
    update_menu "$CHAT" "❌ <b>URL подписки не задан</b>

Задайте его через команду:
<code>/sub https://kox.nonamenebula.ru/c/TOKEN</code>" "$(back_keyboard)"
    return
  fi

  # Show loading message immediately
  update_menu "$CHAT" "⏳ <b>Загружаю список серверов...</b>

Измеряю пинг до каждого сервера, подождите ~5 сек."

  local RAW DECODED
  RAW=$(tg_curl -fsSL --max-time 15 "$SUB_URL" 2>/dev/null)
  if [ -z "$RAW" ]; then
    update_menu "$CHAT" "❌ Не удалось получить подписку

URL: <code>${SUB_URL}</code>" "$(back_keyboard)"
    return
  fi

  DECODED=$(printf '%s' "$RAW" | base64 -d 2>/dev/null || printf '%s' "$RAW")

  local SERVERS
  SERVERS=$(printf '%s' "$DECODED" | grep -o 'vless://[^ \t\r\n]*')
  if [ -z "$SERVERS" ]; then
    update_menu "$CHAT" "❌ Серверы не найдены в подписке." "$(back_keyboard)"
    return
  fi

  local CURRENT_SRV
  CURRENT_SRV=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')

  # Build server list with ping — save to file for callback use
  printf '' > /tmp/kox-servers.txt
  local IDX=0
  printf '%s\n' "$SERVERS" | while IFS= read -r VLINE; do
    [ -z "$VLINE" ] && continue
    local HOST PORT REMARK ENCODED_REMARK
    HOST=$(printf '%s' "$VLINE" | sed 's|vless://[^@]*@\([^:?/#]*\).*|\1|')
    PORT=$(printf '%s' "$VLINE" | sed 's|vless://[^@]*@[^:]*:\([0-9]*\).*|\1|')
    # Extract remark: everything after last '#' (avoid BusyBox grep \t\r\n issues)
    ENCODED_REMARK=$(printf '%s' "$VLINE" | sed 's/.*#//')
    REMARK=$(urldecode "$ENCODED_REMARK")
    [ -z "$REMARK" ] && REMARK="$HOST"
    # Measure ping (1 packet, 2s timeout)
    local PING_MS
    PING_MS=$(ping -c 1 -W 2 "$HOST" 2>/dev/null | grep 'time=' | sed 's/.*time=\([0-9.]*\).*/\1/' | head -1)
    [ -z "$PING_MS" ] && PING_MS="—"
    printf '%s\n' "${IDX}|${HOST}|${PORT}|${REMARK}|${PING_MS}|${VLINE}" >> /tmp/kox-servers.txt
    IDX=$((IDX+1))
  done

  local N
  N=$(wc -l < /tmp/kox-servers.txt 2>/dev/null | tr -d ' ')
  if [ "${N:-0}" -eq 0 ]; then
    update_menu "$CHAT" "❌ Не удалось разобрать серверы из подписки." "$(back_keyboard)"
    return
  fi

  # Build keyboard + info text
  local ROWS="" INFO_TEXT=""
  while IFS='|' read -r IDX HOST PORT REMARK PING_MS VLINE; do
    [ -z "$HOST" ] && continue
    local MARK="" PING_ICON=""
    [ "$HOST" = "$CURRENT_SRV" ] && MARK="✅ "
    # Ping icon by latency
    case "$PING_MS" in
      —) PING_ICON="⚫" ;;
      *)
        local P_INT
        P_INT=$(printf '%s' "$PING_MS" | cut -d. -f1)
        if   [ "$P_INT" -lt 50  ] 2>/dev/null; then PING_ICON="🟢"
        elif [ "$P_INT" -lt 120 ] 2>/dev/null; then PING_ICON="🟡"
        elif [ "$P_INT" -lt 250 ] 2>/dev/null; then PING_ICON="🟠"
        else PING_ICON="🔴"
        fi
        ;;
    esac
    local BTN_LABEL="${MARK}${REMARK}  ${PING_ICON} ${PING_MS} ms"
    ROWS="${ROWS},[{\"text\":\"${BTN_LABEL}\",\"callback_data\":\"switch_srv_${IDX}\"}]"
    INFO_TEXT="${INFO_TEXT}${MARK}${PING_ICON} <b>${REMARK}</b> — <code>${HOST}:${PORT}</code> — <code>${PING_MS} ms</code>
"
  done < /tmp/kox-servers.txt

  local KBD
  KBD="{\"inline_keyboard\":[${ROWS#,},[{\"text\":\"🔄 Обновить\",\"callback_data\":\"switch_list\"},{\"text\":\"◀️ Назад\",\"callback_data\":\"servers_menu\"}]]}"

  update_menu "$CHAT" "🔀 <b>Выберите сервер:</b>

${INFO_TEXT}
🟢&lt;50ms  🟡&lt;120ms  🟠&lt;250ms  🔴высокий  ⚫нет ответа
✅ — текущий сервер" "$KBD"
}

# Actually switch to the selected server (safe: backup + restore on failure)
h_do_switch() {
  local CHAT="$1" IDX="$2"

  if [ ! -f /tmp/kox-servers.txt ]; then
    update_menu "$CHAT" "❌ Список серверов устарел. Нажмите «Сменить сервер» снова." "$(back_keyboard)"
    return
  fi

  # Format: IDX|HOST|PORT|REMARK|PING|VLESS_URL
  local SRV_LINE
  SRV_LINE=$(grep "^${IDX}|" /tmp/kox-servers.txt | head -1)
  if [ -z "$SRV_LINE" ]; then
    update_menu "$CHAT" "❌ Сервер #${IDX} не найден. Нажмите «Сменить сервер» снова." "$(back_keyboard)"
    return
  fi

  local VLESS_URL HOST PORT REMARK
  HOST=$(printf '%s' "$SRV_LINE" | cut -d'|' -f2)
  PORT=$(printf '%s' "$SRV_LINE" | cut -d'|' -f3)
  REMARK=$(printf '%s' "$SRV_LINE" | cut -d'|' -f4)
  VLESS_URL=$(printf '%s' "$SRV_LINE" | cut -d'|' -f6-)

  # Parse VLESS URL for config fields
  local UUID PARAMS SNI FLOW
  UUID=$(printf '%s' "$VLESS_URL" | sed 's|vless://\([^@]*\)@.*|\1|')
  PARAMS=$(printf '%s' "$VLESS_URL" | grep -o '?[^#]*' | sed 's/^?//')
  SNI=$(printf '%s' "$PARAMS" | grep -o 'sni=[^&]*' | cut -d= -f2)
  FLOW=$(printf '%s' "$PARAMS" | grep -o 'flow=[^&]*' | cut -d= -f2)

  if [ -z "$UUID" ] || [ -z "$HOST" ]; then
    update_menu "$CHAT" "❌ Не удалось разобрать VLESS URL для сервера #${IDX}" "$(back_keyboard)"
    return
  fi

  send_typing "$CHAT"
  update_menu "$CHAT" "⏳ <b>Переключаю на сервер...</b>

<b>${REMARK}</b>
<code>${HOST}:${PORT:-443}</code>

Создаю резервную копию конфига..."

  # Backup current config and kox.conf
  cp "$CONF" /tmp/kox-config-backup.json 2>/dev/null
  cp "$KOXCONF" /tmp/kox-conf-backup 2>/dev/null

  # Update kox.conf
  conf_set KOX_SERVER "$HOST"
  conf_set KOX_PORT "${PORT:-443}"
  conf_set KOX_UUID "$UUID"
  conf_set KOX_SNI "${SNI:-www.google.com}"
  conf_set KOX_FLOW "${FLOW:-xtls-rprx-vision}"

  # Update config.json via jq (properly preserves inbound ports)
  local TMP_CONF=/tmp/kox-switch-tmp.json
  local P="${PORT:-443}"
  jq --arg addr "$HOST" --argjson port "$P" \
     --arg uuid "$UUID" --arg sni "${SNI:-www.google.com}" \
     --arg flow "${FLOW:-xtls-rprx-vision}" '
    .outbounds = [.outbounds[] |
      if .protocol == "vless" then
        .settings.vnext[0].address = $addr |
        .settings.vnext[0].port = ($port | tonumber) |
        .settings.vnext[0].users[0].id = $uuid |
        .settings.vnext[0].users[0].flow = $flow |
        (if $sni != "" then .streamSettings.realitySettings.serverName = $sni else . end)
      else . end
    ]
  ' "$CONF" > "$TMP_CONF" 2>/dev/null
  if [ -s "$TMP_CONF" ]; then
    mv "$TMP_CONF" "$CONF"
  fi

  # Restart xray
  if [ -x "$XRAY_INIT" ]; then
    "$XRAY_INIT" restart >/dev/null 2>&1
  else
    pkill xray 2>/dev/null; sleep 1
    /opt/sbin/xray -config "$CONF" >> /opt/var/log/xray-err.log 2>&1 &
  fi
  sleep 3

  # Check if xray is up
  if pgrep xray >/dev/null 2>&1 && nc -z 127.0.0.1 10808 2>/dev/null; then
    update_menu "$CHAT" "✅ <b>Переключено на сервер!</b>

<b>${REMARK}</b>
Адрес: <code>${HOST}</code>
Порт:  <code>${PORT:-443}</code>
UUID:  <code>${UUID}</code>
SNI:   <code>${SNI:-www.google.com}</code>

Xray запущен, порт 10808 активен." \
      "$(main_keyboard)"
  else
    # Auto-revert
    cp /tmp/kox-config-backup.json "$CONF" 2>/dev/null
    cp /tmp/kox-conf-backup "$KOXCONF" 2>/dev/null
    if [ -x "$XRAY_INIT" ]; then
      "$XRAY_INIT" restart >/dev/null 2>&1
    else
      pkill xray 2>/dev/null; sleep 1
      /opt/sbin/xray -config "$CONF" >> /opt/var/log/xray-err.log 2>&1 &
    fi
    sleep 2
    update_menu "$CHAT" "❌ <b>Переключение не удалось — откат!</b>

Xray не запустился с новым сервером.
Восстановлен предыдущий конфиг.

Попробуйте другой сервер или проверьте логи." \
      "$(main_keyboard)"
  fi
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
  update_menu "$CHAT" "❓ <b>KOX Shield Bot — справка</b>  <i>v${KOX_VERSION}</i>

<b>Меню кнопок:</b>
📊 Статус — Xray, iptables, VPN
🌐 Серверы — текущий сервер + переключение
🔀 Сменить сервер — список из подписки
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
<code>/update</code> — проверить и обновить KOX
<code>/sub URL</code> — задать URL подписки
<code>/start</code> — сбросить меню (если пропало)

<b>Безопасность:</b>
Бот работает через VPN, а при его отсутствии — напрямую.
При переключении сервера — автооткат если Xray не запустился.
При падении Xray — watchdog снимает iptables (интернет не пропадает).

🔗 <a href=\"https://t.me/PrivateProxyKox\">t.me/PrivateProxyKox</a>"
}

# ── List update notification helpers ──────────────────────────────────────────

# ── Conf helpers ──────────────────────────────────────────────────────────────

conf_get() { grep "^${1}=" "$KOXCONF" 2>/dev/null | sed 's/^[^=]*=//;s/^"//;s/"$//' ; }

conf_set() {
  KEY="$1"; VAL="$2"
  touch "$KOXCONF"
  if grep -q "^${KEY}=" "$KOXCONF" 2>/dev/null; then
    sed -i "s|^${KEY}=.*|${KEY}=\"${VAL}\"|" "$KOXCONF"
  else
    printf '%s="%s"\n' "$KEY" "$VAL" >> "$KOXCONF"
  fi
}

notify_allowed() {
  KEY_ON="$1"; KEY_SKIP="$2"
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
  VAL=$(conf_get "$KEY_ON"); [ "${VAL:-yes}" = "no" ] && return 1
  SKIP=$(conf_get "$KEY_SKIP"); NOW=$(date +%s 2>/dev/null || echo 0)
  [ "${SKIP:-0}" -gt "$NOW" ] 2>/dev/null && return 1
  return 0
}

lists_notify_allowed() { notify_allowed KOX_LIST_NOTIFY KOX_LIST_NOTIFY_SKIP_UNTIL; }
upgrade_notify_allowed() { notify_allowed KOX_UPGRADE_NOTIFY KOX_UPGRADE_NOTIFY_SKIP_UNTIL; }

snooze() {
  KEY="$1"; DAYS="$2"
  NOW=$(date +%s 2>/dev/null || echo 0)
  conf_set "$KEY" "$((NOW + DAYS * 86400))"
}

lists_set_snooze()   { snooze KOX_LIST_NOTIFY_SKIP_UNTIL "$1"; }
upgrade_set_snooze() { snooze KOX_UPGRADE_NOTIFY_SKIP_UNTIL "$1"; }

lists_disable_notify()   { conf_set KOX_LIST_NOTIFY no; }
upgrade_disable_notify() { conf_set KOX_UPGRADE_NOTIFY no; }
lists_enable_notify()    { conf_set KOX_LIST_NOTIFY yes; conf_set KOX_LIST_NOTIFY_SKIP_UNTIL 0; }
upgrade_enable_notify()  { conf_set KOX_UPGRADE_NOTIFY yes; conf_set KOX_UPGRADE_NOTIFY_SKIP_UNTIL 0; }

# ── KOX version update check ──────────────────────────────────────────────────

check_kox_update() {
  NOW=$(date +%s 2>/dev/null || echo 0)
  LAST=$(cat "$KOX_LASTCHECK_FILE" 2>/dev/null || echo 0)
  [ $((NOW - LAST)) -lt "$CHECK_INTERVAL" ] && return 0
  printf '%s' "$NOW" > "$KOX_LASTCHECK_FILE"

  [ -z "$ADMIN_ID" ] && return 0
  upgrade_notify_allowed || return 0

  REMOTE_VER=$(tg_curl -fsSL --max-time 10 "${GITHUB_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -z "$REMOTE_VER" ] && return 0
  printf '%s' "$REMOTE_VER" | grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}' || return 0

  LOCAL_VER="$KOX_VERSION"
  CUR_INT=$(printf '%s' "$LOCAL_VER" | tr -d '.'); REM_INT=$(printf '%s' "$REMOTE_VER" | tr -d '.')
  [ "$REM_INT" -le "$CUR_INT" ] 2>/dev/null && return 0

  # Fetch changelog for this version
  CHANGELOG=$(tg_curl -fsSL --max-time 10 "${GITHUB_RAW}/CHANGELOG.md" 2>/dev/null | \
    awk "/^## ${REMOTE_VER}/{found=1;next} found && /^## /{exit} found{print}" | \
    grep -v '^[[:space:]]*$' | head -6)

  # Auto-upgrade if enabled
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
  if [ "${KOX_AUTO_UPGRADE:-no}" = "yes" ]; then
    log "Auto-upgrading KOX to v${REMOTE_VER}..."
    send_info "$ADMIN_ID" "🔄 <b>KOX Shield обновляется автоматически</b>

Устанавливается версия: <b>v${REMOTE_VER}</b>
Текущая: <code>v${KOX_VERSION}</code>

Бот перезапустится через несколько секунд..."
    sleep 2
    /opt/bin/kox upgrade --force >/dev/null 2>&1 &
    return 0
  fi

  MSG="🔔 <b>Обновление KOX Shield!</b>

Доступна версия: <b>v${REMOTE_VER}</b>
Текущая: <code>v${KOX_VERSION}</code>"

  [ -n "$CHANGELOG" ] && MSG="${MSG}

📋 <b>Что нового:</b>
$(printf '%s' "$CHANGELOG" | sed 's/^/• /')"

  MSG="${MSG}

Обновить KOX Shield?"

  KBD='{"inline_keyboard":[[
    {"text":"✅ Обновить сейчас","callback_data":"kox_do_upgrade","style":"success"},
    {"text":"⏰ Не напоминать сегодня","callback_data":"kox_snooze_upgrade_1"}
  ],[
    {"text":"📅 Не напоминать месяц","callback_data":"kox_snooze_upgrade_30"},
    {"text":"🔕 Отключить","callback_data":"kox_upgrade_notify_off","style":"danger"}
  ]]}'

  PAYLOAD=$(jq -cn --argjson c "$ADMIN_ID" --arg t "$MSG" --argjson k "$KBD" \
    '{chat_id:$c,text:$t,parse_mode:"HTML",reply_markup:$k}')
  api_call "sendMessage" "$PAYLOAD" >/dev/null 2>&1
  log "KOX upgrade notification sent for v${REMOTE_VER}"
}

_lists_compute_diff() {
  # Compare loaded categories: find added AND removed domains
  # Outputs lines prefixed with ADD: or REM:
  LOADED=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null || echo "")
  [ -z "$LOADED" ] && return 0
  printf '%s\n' "$LOADED" | while IFS= read -r S; do
    [ -z "$S" ] && continue
    LOCAL_FILE="${KOX_LISTS_DIR}/${S}.txt"
    NEW_FILE="/tmp/kox-newlist-${S}.txt"
    # Fetch remote file if not already fetched
    [ -f "$NEW_FILE" ] || curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_LISTS}/${S}.txt" \
      -o "$NEW_FILE" 2>/dev/null || continue
    [ -f "$LOCAL_FILE" ] || continue

    # Find added: in new but not in old
    while IFS= read -r LINE; do
      case "$LINE" in '#'*|'') continue ;; esac
      grep -qxF "$LINE" "$LOCAL_FILE" 2>/dev/null || printf 'ADD:%s:%s\n' "$S" "$LINE"
    done < "$NEW_FILE"

    # Find removed: in old but not in new
    while IFS= read -r LINE; do
      case "$LINE" in '#'*|'') continue ;; esac
      grep -qxF "$LINE" "$NEW_FILE" 2>/dev/null || printf 'REM:%s:%s\n' "$S" "$LINE"
    done < "$LOCAL_FILE"
  done
}

_diff_to_msg() {
  # Takes diff lines, formats into human-readable message
  # $1 = prefix to use (e.g. "added" or "removed")
  DIFF="$1"; TYPE="$2"; ICON="$3"
  printf '%s' "$DIFF" | grep "^${TYPE}:" | \
    awk -F: -v icon="$ICON" '
      {cat=$2; dom=$3}
      cat != prev { if(prev!="") printf "\n"; printf "  %s <b>%s</b>: ", icon, cat; prev=cat }
      { printf dom", " }
      END { if(prev!="") printf "\n" }
    ' | sed 's/, *$//'
}

_lists_get_new_domains() {
  _lists_compute_diff | grep '^ADD:' | \
    awk -F: '{cat=$2; dom=$3; line[cat]=line[cat] dom", "} END{for(c in line){s=line[c]; sub(/, $/,"",s); print "  • <b>"c"</b>: +"s}}'
}

_lists_get_removed_domains() {
  _lists_compute_diff | grep '^REM:' | \
    awk -F: '{cat=$2; dom=$3; line[cat]=line[cat] dom", "} END{for(c in line){s=line[c]; sub(/, $/,"",s); print "  • <b>"c"</b>: -"s}}'
}

check_lists_update() {
  NOW=$(date +%s 2>/dev/null || echo 0)
  LAST=$(cat "$LISTS_LASTCHECK_FILE" 2>/dev/null || echo 0)
  [ $((NOW - LAST)) -lt "$CHECK_INTERVAL" ] && return 0
  printf '%s' "$NOW" > "$LISTS_LASTCHECK_FILE"

  [ -z "$ADMIN_ID" ] && return 0

  LOCAL_VER=$(cat "${KOX_LISTS_DIR}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  REMOTE_VER=$(tg_curl -fsSL --max-time 10 "${GITHUB_LISTS}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -z "$REMOTE_VER" ] && return 0
  printf '%s' "$REMOTE_VER" | grep -qE '^[0-9]' || return 0

  CUR_INT=$(printf '%s' "${LOCAL_VER:-0}" | tr -d '.'); REM_INT=$(printf '%s' "$REMOTE_VER" | tr -d '.')
  [ "$REM_INT" -le "${CUR_INT:-0}" ] 2>/dev/null && return 0

  # Load conf to check auto-update setting
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

  # Compute diff once (fetches remote files into /tmp/kox-newlist-*.txt)
  LOADED=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null || echo "")
  DIFF_ALL=$(_lists_compute_diff)
  NEW_DOMAINS=$(printf '%s\n' "$DIFF_ALL" | grep '^ADD:' | \
    awk -F: '{cat=$2; dom=$3; a[cat]=a[cat]""dom", "} END{for(c in a){s=a[c]; sub(/, $/,"",s); printf "  • <b>%s</b>: +%s\n",c,s}}')
  REM_DOMAINS=$(printf '%s\n' "$DIFF_ALL" | grep '^REM:' | \
    awk -F: '{cat=$2; dom=$3; a[cat]=a[cat]""dom", "} END{for(c in a){s=a[c]; sub(/, $/,"",s); printf "  • <b>%s</b>: -%s\n",c,s}}')

  # Auto-update if enabled
  if [ "${KOX_AUTO_LIST_UPDATE:-no}" = "yes" ]; then
    log "Auto-updating lists to v${REMOTE_VER}..."
    mkdir -p "$KOX_LISTS_DIR"
    curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_LISTS}/categories.json" \
      -o "${KOX_LISTS_DIR}/categories.json" 2>/dev/null
    if [ -n "$LOADED" ]; then
      printf '%s\n' "$LOADED" | while IFS= read -r S; do
        [ -z "$S" ] && continue
        [ -f "/tmp/kox-newlist-${S}.txt" ] && cp "/tmp/kox-newlist-${S}.txt" "${KOX_LISTS_DIR}/${S}.txt"
      done
    fi
    printf '%s\n' "$REMOTE_VER" > "${KOX_LISTS_DIR}/LISTS_VERSION"
    MSG="✅ <b>Списки доменов обновлены автоматически!</b>

Версия: <code>v${REMOTE_VER}</code>"
    [ -n "$NEW_DOMAINS" ] && MSG="${MSG}

➕ <b>Добавлено в туннель:</b>
${NEW_DOMAINS}"
    [ -n "$REM_DOMAINS" ] && MSG="${MSG}

➖ <b>Удалено из туннелей:</b>
${REM_DOMAINS}"
    MSG="${MSG}

Применить изменения на Xray?"
    KBD='{"inline_keyboard":[[{"text":"⚡ Применить сейчас","callback_data":"lists_apply_xray","style":"success"}]]}'
    PAYLOAD=$(jq -cn --argjson c "$ADMIN_ID" --arg t "$MSG" --argjson k "$KBD" \
      '{chat_id:$c,text:$t,parse_mode:"HTML",reply_markup:$k}')
    api_call "sendMessage" "$PAYLOAD" >/dev/null 2>&1
    return 0
  fi

  lists_notify_allowed || return 0

  HAS_DIFF=0
  [ -n "$NEW_DOMAINS" ] && HAS_DIFF=1
  [ -n "$REM_DOMAINS" ] && HAS_DIFF=1

  MSG="🔔 <b>Обновление списков доменов!</b>

Версия: <code>v${REMOTE_VER}</code> (текущая: <code>${LOCAL_VER:-нет}</code>)"

  if [ "$HAS_DIFF" -eq 1 ]; then
    [ -n "$NEW_DOMAINS" ] && MSG="${MSG}

➕ <b>Добавляются домены:</b>
${NEW_DOMAINS}"
    [ -n "$REM_DOMAINS" ] && MSG="${MSG}

➖ <b>Удаляются домены:</b>
${REM_DOMAINS}

Применить эти изменения у вас тоже?"
  elif [ -n "$LOADED" ]; then
    MSG="${MSG}

📂 Ваши категории: $(printf '%s' "$LOADED" | tr '\n' ' ')

Обновить списки?"
  else
    MSG="${MSG}

Обновить индекс категорий?"
  fi

  KBD='{"inline_keyboard":[[
    {"text":"✅ Применить изменения","callback_data":"lists_do_update","style":"success"},
    {"text":"⏰ Не сегодня","callback_data":"lists_snooze_1"}
  ],[
    {"text":"📅 Не этот месяц","callback_data":"lists_snooze_30"},
    {"text":"🔕 Отключить","callback_data":"lists_disable_notify","style":"danger"}
  ]]}'

  PAYLOAD=$(jq -cn --argjson c "$ADMIN_ID" --arg t "$MSG" --argjson k "$KBD" \
    '{chat_id:$c,text:$t,parse_mode:"HTML",reply_markup:$k}')
  api_call "sendMessage" "$PAYLOAD" >/dev/null 2>&1
  log "Lists update notification sent for v${REMOTE_VER} (add=${NEW_DOMAINS:+yes} rem=${REM_DOMAINS:+yes})"
}

h_lists_update() {
  local CHAT="$1"
  send_typing "$CHAT"
  REMOTE_VER=$(curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_LISTS}/LISTS_VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -z "$REMOTE_VER" ] && update_menu "$CHAT" "❌ Нет подключения к GitHub" && return

  mkdir -p "$KOX_LISTS_DIR"
  curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_LISTS}/categories.json" \
    -o "${KOX_LISTS_DIR}/categories.json" 2>/dev/null

  LOADED=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null || echo "")
  if [ -z "$LOADED" ]; then
    printf '%s\n' "$REMOTE_VER" > "${KOX_LISTS_DIR}/LISTS_VERSION"
    KBD='{"inline_keyboard":[[{"text":"📋 Загрузить категории","callback_data":"listcats","style":"primary"}]]}'
    PAYLOAD=$(jq -cn --argjson c "$CHAT" --arg t "✅ <b>Индекс категорий обновлён</b>

Версия: <code>v${REMOTE_VER}</code>
Загруженных категорий нет — выберите нужные:" --argjson k "$KBD" \
      '{chat_id:$c,text:$t,parse_mode:"HTML",reply_markup:$k}')
    api_call "sendMessage" "$PAYLOAD" >/dev/null 2>&1
    update_menu "$CHAT" "✅ Индекс обновлён. Выберите категории для загрузки."
    return
  fi

  # Apply update: use kox list-update for proper add/remove
  /opt/bin/kox list-update >/tmp/kox-list-update-out 2>&1
  printf '%s\n' "$REMOTE_VER" > "${KOX_LISTS_DIR}/LISTS_VERSION"
  UPDATE_OUT=$(cat /tmp/kox-list-update-out 2>/dev/null | \
    sed 's/\x1b\[[0-9;]*m//g' | grep -E '✓|✗|Обновлено|Xray' | head -10)

  update_menu "$CHAT" "✅ <b>Списки обновлены до v${REMOTE_VER}</b>

${UPDATE_OUT}

Изменения применены к Xray."
}

h_kox_do_upgrade() {
  local CHAT="$1"

  # Dismiss callback spinner immediately
  [ -n "$CB_ID" ] && api_call "answerCallbackQuery" \
    "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"Проверяю версию...\"}" >/dev/null 2>&1

  # Prevent double-upgrade via lock file
  UPGRADE_LOCK="/tmp/kox-upgrading"
  if [ -f "$UPGRADE_LOCK" ]; then
    update_menu "$CHAT" "⏳ <b>Обновление уже выполняется...</b>

Подождите, бот скоро перезапустится."
    return
  fi

  send_typing "$CHAT"
  REMOTE_VER=$(curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_RAW}/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -z "$REMOTE_VER" ] && update_menu "$CHAT" "❌ Нет подключения к GitHub" && return

  # CRITICAL: check if already up to date BEFORE doing anything
  # This handles replayed callbacks after bot restart
  CUR_INT=$(printf '%s' "$KOX_VERSION" | tr -d '.')
  REM_INT=$(printf '%s' "$REMOTE_VER" | tr -d '.')
  if [ "$REM_INT" -le "$CUR_INT" ] 2>/dev/null; then
    update_menu "$CHAT" "✅ <b>KOX Shield уже актуален!</b>

Версия: <code>v${KOX_VERSION}</code>
Обновление не требуется." "$(main_keyboard)"
    return
  fi

  # Set lock
  printf '%s' "$$" > "$UPGRADE_LOCK"

  LOADED_CNT=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')

  update_menu "$CHAT" "⏳ <b>Обновление KOX Shield v${KOX_VERSION} → v${REMOTE_VER}</b>

Загружаю файлы с GitHub...
Бот перезапустится через несколько секунд."

  # Save current offset BEFORE triggering restart so callback isn't replayed
  printf '%s' "$((UPDATE_ID+1))" > "$OFFSET_FILE"

  # Run upgrade and redirect to log
  /opt/bin/kox upgrade --force >> /opt/var/log/kox-bot.log 2>&1

  # If we reach here, upgrade failed or bot didn't restart
  rm -f "$UPGRADE_LOCK"
  update_menu "$CHAT" "⚠️ <b>Что-то пошло не так.</b>

Проверьте: <code>kox upgrade</code> в SSH.
Текущая версия: <code>v${KOX_VERSION}</code>"
}

h_settings() {
  local CHAT="$1"
  [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

  AUTO_UPG="${KOX_AUTO_UPGRADE:-no}";   [ "$AUTO_UPG" = "yes" ] && ICON_UPG="✅ Вкл" || ICON_UPG="❌ Выкл"
  AUTO_LST="${KOX_AUTO_LIST_UPDATE:-no}"; [ "$AUTO_LST" = "yes" ] && ICON_LST="✅ Вкл" || ICON_LST="❌ Выкл"
  NTFY_UPG="${KOX_UPGRADE_NOTIFY:-yes}"; [ "$NTFY_UPG" = "yes" ] && ICON_NUPG="🔔 Вкл" || ICON_NUPG="🔕 Выкл"
  NTFY_LST="${KOX_LIST_NOTIFY:-yes}";    [ "$NTFY_LST" = "yes" ] && ICON_NLST="🔔 Вкл" || ICON_NLST="🔕 Выкл"

  MSG="⚙️ <b>Настройки KOX Shield</b>

🔄 <b>Автообновление KOX</b>: ${ICON_UPG}
Когда выходит новая версия KOX Shield — устанавливать автоматически.

📋 <b>Автообновление списков</b>: ${ICON_LST}
Автоматически скачивать новые домены при обнаружении обновлений.

${ICON_NUPG} <b>Уведомления: KOX</b>: ${NTFY_UPG}
${ICON_NLST} <b>Уведомления: Списки</b>: ${NTFY_LST}"

  KBD=$(jq -cn \
    --arg iu "$ICON_UPG" --arg il "$ICON_LST" \
    --arg inu "$ICON_NUPG" --arg inl "$ICON_NLST" \
    '{"inline_keyboard":[
      [{"text":("🔄 Автообн. KOX: "+$iu),"callback_data":"toggle_auto_upg"}],
      [{"text":("📋 Автообн. списков: "+$il),"callback_data":"toggle_auto_lst"}],
      [{"text":($inu+" уведомл. KOX"),"callback_data":"toggle_notify_upg"},
       {"text":($inl+" уведомл. списков"),"callback_data":"toggle_notify_lst"}],
      [{"text":"◀️ Главное меню","callback_data":"menu"}]
    ]}')

  update_menu "$CHAT" "$MSG" "$KBD"
}

h_clean_legacy() {
  local CHAT="$1"
  answer_cb "$CB_ID" "Сканирую роутер..."
  send_typing "$CHAT"

  # Run detection
  FOUND_KVAS=false;   [ -f /opt/etc/init.d/S96kvas ] || [ -f /opt/bin/kvas ] || [ -d /opt/apps/kvas ] && FOUND_KVAS=true
  FOUND_SS=false;     { [ -f /opt/etc/init.d/S22shadowsocks ] || pgrep -x ss-redir >/dev/null 2>&1; } && FOUND_SS=true
  FOUND_SB=false;     { [ -f /opt/sbin/sing-box ] && pgrep -x sing-box >/dev/null 2>&1; } && FOUND_SB=true
  FOUND_IPT=false;    iptables -t nat -L PREROUTING -n 2>/dev/null | grep -qE 'REDIRECT.*:1(080|181|090)' && FOUND_IPT=true

  SOCKS_IFACES=""
  if command -v ndmc >/dev/null 2>&1; then
    SOCKS_IFACES=$(ndmc -c 'show interface' 2>/dev/null | awk '
      /^Interface, name =/ { iface=$4; gsub(/"/, "", iface) }
      /type: Socks/         { print iface }
    ')
  fi

  FOUND_ANY=false
  REPORT=""
  $FOUND_KVAS  && FOUND_ANY=true && REPORT="${REPORT}❌ Kvass (KVAS)\n"
  $FOUND_SS    && FOUND_ANY=true && REPORT="${REPORT}❌ Shadowsocks\n"
  $FOUND_SB    && FOUND_ANY=true && REPORT="${REPORT}❌ sing-box\n"
  $FOUND_IPT   && FOUND_ANY=true && REPORT="${REPORT}❌ Старые iptables SOCKS-правила\n"
  [ -n "$SOCKS_IFACES" ] && FOUND_ANY=true && REPORT="${REPORT}❌ SOCKS-интерфейсы Keenetic: $(printf '%s' "$SOCKS_IFACES" | tr '\n' ' ')\n"

  if ! $FOUND_ANY; then
    update_menu "$CHAT" "✅ <b>Роутер чистый!</b>

Устаревших VPN-решений (Kvass, Shadowsocks, SOCKS) не найдено."
    return
  fi

  KBD='{"inline_keyboard":[[
    {"text":"🗑 Удалить всё найденное","callback_data":"clean_legacy_confirm"},
    {"text":"❌ Отмена","callback_data":"settings"}
  ]]}'

  update_menu "$CHAT" "🔍 <b>Найдено устаревшее ПО:</b>

$(printf '%b' "$REPORT")
Удалить всё и очистить правила?" "$KBD"
}

h_clean_legacy_confirm() {
  local CHAT="$1"
  answer_cb "$CB_ID" "Удаляю..."
  update_menu "$CHAT" "⏳ <b>Выполняю очистку...</b>"

  OUT=$(/opt/bin/kox clean-legacy --force 2>&1 | tail -20)

  update_menu "$CHAT" "✅ <b>Очистка завершена!</b>

<pre>$(printf '%s' "$OUT" | sed 's/\x1B\[[0-9;]*m//g' | tail -10)</pre>

Рекомендуется перезагрузить роутер."
}

h_list_cats() {
  local CHAT="$1"
  send_typing "$CHAT"
  CATS_FILE="${KOX_LISTS_DIR}/categories.json"
  if [ ! -f "$CATS_FILE" ]; then
    mkdir -p "$KOX_LISTS_DIR"
    curl -fsSL -x "$PROXY" --max-time 10 "${GITHUB_LISTS}/categories.json" \
      -o "$CATS_FILE" 2>/dev/null
  fi
  [ ! -f "$CATS_FILE" ] && update_menu "$CHAT" "❌ Не удалось загрузить список категорий" && return

  LOADED=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null || echo "")
  CATS_TEXT=$(jq -r '.categories[] | "\(.emoji) \(.name) (\(.total)) — \(.slug)"' "$CATS_FILE" 2>/dev/null | \
    while IFS= read -r LINE; do
      SLUG=$(printf '%s' "$LINE" | awk -F' — ' '{print $NF}')
      if printf '%s' "$LOADED" | grep -qx "$SLUG"; then
        printf '✓ %s\n' "$LINE"
      else
        printf '  %s\n' "$LINE"
      fi
    done)

  send_info "$CHAT" "📋 <b>Категории доменов KOX Shield:</b>

<pre>${CATS_TEXT}</pre>

✓ — загружена на роутер

Для загрузки: <code>kox list-load &lt;slug&gt;</code>
Для всех:    <code>kox list-load all</code>"
  update_menu "$CHAT" "📋 Список категорий отправлен выше"
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

  RESPONSE=$(tg_curl -m 35 \
    "${API}/getUpdates?offset=${OFFSET}&timeout=30&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D")

  # Check for KOX Shield and list updates (throttled internally)
  check_kox_update
  check_lists_update

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
      update_menu "$CHAT_ID" "⚠️ <b>KOX Shield Bot не настроен</b>

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
      # Navigation — /start always sends a FRESH message (clears stale sticky)
      /start)
        sticky_clear
        update_menu "$CHAT_ID" \
          "🔑 <b>KOX Shield — управление роутером</b>
<i>v${KOX_VERSION}</i>

Выберите действие:" "$(main_keyboard)"
        ;;
      /menu|menu)
        update_menu "$CHAT_ID" \
          "🔑 <b>KOX Shield — управление роутером</b>
<i>v${KOX_VERSION}</i>

Выберите действие:" "$(main_keyboard)"
        ;;

      # Info
      status|/status)    h_status       "$CHAT_ID" ;;
      server|/server)    h_servers_menu "$CHAT_ID" ;;
      servers_menu)      h_servers_menu "$CHAT_ID" ;;
      switch_list)       h_switch_list  "$CHAT_ID" ;;
      stats|/stats)      h_stats        "$CHAT_ID" ;;
      test_config)       h_test         "$CHAT_ID" ;;

      # VPN control
      do_on)             h_on      "$CHAT_ID" ;;
      confirm_off)
        update_menu "$CHAT_ID" \
          "⚠️ <b>Выключить VPN?</b>

Трафик пойдёт напрямую, сайты с умным шифрованием станут недоступны." \
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

      # Submenus
      domains_menu)
        update_menu "$CHAT_ID" "📋 <b>Управление доменами и IP</b>" "$(domains_keyboard)" ;;
      tools_menu)
        update_menu "$CHAT_ID" "🛠 <b>Инструменты</b>" "$(tools_keyboard)" ;;

      # Settings screen
      /settings|settings) h_settings "$CHAT_ID" ;;

      toggle_auto_upg)
        [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
        if [ "${KOX_AUTO_UPGRADE:-no}" = "yes" ]; then conf_set KOX_AUTO_UPGRADE no
        else conf_set KOX_AUTO_UPGRADE yes; fi
        h_settings "$CHAT_ID" ;;
      toggle_auto_lst)
        [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
        if [ "${KOX_AUTO_LIST_UPDATE:-no}" = "yes" ]; then conf_set KOX_AUTO_LIST_UPDATE no
        else conf_set KOX_AUTO_LIST_UPDATE yes; fi
        h_settings "$CHAT_ID" ;;
      toggle_notify_upg)
        [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
        if [ "${KOX_UPGRADE_NOTIFY:-yes}" = "yes" ]; then upgrade_disable_notify
        else upgrade_enable_notify; fi
        h_settings "$CHAT_ID" ;;
      toggle_notify_lst)
        [ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null
        if [ "${KOX_LIST_NOTIFY:-yes}" = "yes" ]; then lists_disable_notify
        else lists_enable_notify; fi
        h_settings "$CHAT_ID" ;;

      # Server switching
      switch_srv_*)
        SRV_IDX=$(printf '%s' "$CMD" | sed 's/switch_srv_//')
        h_do_switch "$CHAT_ID" "$SRV_IDX"
        ;;

      # Set subscription URL manually
      /sub)
        if [ -n "$ARG" ]; then
          conf_set KOX_SUB_URL "$ARG"
          update_menu "$CHAT_ID" "✅ <b>URL подписки сохранён:</b>
<code>${ARG}</code>

Теперь доступно переключение серверов." "$(main_keyboard)"
        else
          update_menu "$CHAT_ID" "Использование: <code>/sub https://...</code>" "$(back_keyboard)"
        fi
        ;;

      # Legacy cleanup
      clean_legacy)         h_clean_legacy "$CHAT_ID" ;;
      clean_legacy_confirm) h_clean_legacy_confirm "$CHAT_ID" ;;

      # KOX upgrade notification callbacks
      kox_do_upgrade)  h_kox_do_upgrade "$CHAT_ID" ;;
      kox_snooze_upgrade_1)
        upgrade_set_snooze 1
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"⏰ Напомним завтра\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "⏰ <b>Напомним об обновлении KOX завтра</b>" ;;
      kox_snooze_upgrade_30)
        upgrade_set_snooze 30
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"📅 Напомним через месяц\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "📅 <b>Отложено на 30 дней</b>" ;;
      kox_upgrade_notify_off)
        upgrade_disable_notify
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"🔕 Уведомления отключены\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "🔕 <b>Уведомления об обновлении KOX отключены</b>

Включить: <code>/settings</code> → Уведомления KOX" ;;

      # Lists management
      /listcats|listcats) h_list_cats "$CHAT_ID" ;;
      /listupdate|listupdate) h_lists_update "$CHAT_ID" ;;

      lists_do_update)
        h_lists_update "$CHAT_ID" ;;
      lists_apply_xray)
        send_typing "$CHAT_ID"
        /opt/bin/kox list-update >/dev/null 2>&1 &
        update_menu "$CHAT_ID" "⚡ <b>Применяю обновления...</b>

Xray перезапустится через несколько секунд." ;;

      lists_load_all)
        send_typing "$CHAT_ID"
        update_menu "$CHAT_ID" "⏳ <b>Загружаю все категории...</b>

Это займёт ~30 секунд..."
        /opt/bin/kox list-load all >> /opt/var/log/kox-bot.log 2>&1 &
        sleep 5
        LOADED=$(cat "${KOX_LISTS_DIR}/kox-lists-loaded.conf" 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
        update_menu "$CHAT_ID" "✅ <b>Загружено ${LOADED} категорий!</b>

Все домены добавлены в туннель. Xray перезапущен." ;;
      lists_snooze_1)
        lists_set_snooze 1
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"⏰ Напомним завтра\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "⏰ <b>Отложено на 1 день</b>" ;;
      lists_snooze_30)
        lists_set_snooze 30
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"📅 Напомним через месяц\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "📅 <b>Отложено на 30 дней</b>" ;;
      lists_disable_notify)
        lists_disable_notify
        api_call "answerCallbackQuery" "{\"callback_query_id\":\"${CB_ID}\",\"text\":\"🔕 Уведомления отключены\"}" >/dev/null 2>&1
        update_menu "$CHAT_ID" "🔕 <b>Уведомления о списках отключены</b>

Включить: <code>/settings</code>" ;;
      /listnotify)
        if [ "$ARG" = "on" ]; then lists_enable_notify
          update_menu "$CHAT_ID" "🔔 <b>Уведомления о списках включены</b>"
        elif [ "$ARG" = "off" ]; then lists_disable_notify
          update_menu "$CHAT_ID" "🔕 <b>Уведомления о списках отключены</b>"
        else
          update_menu "$CHAT_ID" "Использование: <code>/listnotify on</code> или <code>/listnotify off</code>"
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

      # Update now (direct command without waiting for notification)
      /update)
        sticky_clear
        h_kox_do_upgrade "$CHAT_ID"
        ;;

      # "Back to menu" from confirm/prompt screens
      menu)
        rm -f "$WAIT_FILE"
        update_menu "$CHAT_ID" \
          "🔑 <b>KOX Shield — управление роутером</b>
<i>v${KOX_VERSION}</i>

Выберите действие:" "$(main_keyboard)"
        ;;

      *)
        update_menu "$CHAT_ID" "❓ Используйте кнопки меню:" "$(main_keyboard)"
        ;;
    esac

    i=$((i+1)); OFFSET=$((UPDATE_ID+1)); printf '%s' "$OFFSET" > "$OFFSET_FILE"
  done
done
