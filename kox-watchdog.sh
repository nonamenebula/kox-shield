#!/bin/sh
# KOX Watchdog v9
# — перезапускает xray при падении; при сбое — switch-auto на другой сервер
# — считает минуты без VPN (KOX_FAILOVER_MINUTES, default 3)
# — после падения Xray — переключение без ожидания N минут
# — switch-auto использует кэш серверов если подписка недоступна
# — возврат на основной сервер (KOX_PREFERRED_HOST + KOX_AUTO_RETURN)

KOXCONF="/opt/etc/xray/kox.conf"
CONF="/opt/etc/xray/config.json"
NAT_SCRIPT="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
LOGF="/opt/var/log/kox-watchdog.log"
ERRLOG="/opt/var/log/xray-err.log"
ACCLOG="/opt/var/log/xray-acc.log"
CRASHLOG="/opt/var/log/xray-err.last-crash.log"
VPN_OFF_MARKER="/tmp/kox-vpn-off"
FAIL_COUNT_FILE="/tmp/kox-vpn-fail-count"
LAST_SWITCH_FILE="/tmp/kox-last-auto-switch"
SWITCHING_LOCK="/tmp/kox-autoswitch.lock"
XRAY_WAS_DOWN="/tmp/kox-wd-xray-was-down"
XRAY_START_FAIL_FILE="/tmp/kox-xray-start-fail-count"
XRAY_INIT="/opt/etc/init.d/S24xray"
HYSTERIA_BIN="/opt/sbin/hysteria"
HYSTERIA_CONF="/opt/etc/hysteria/client.yaml"
HYSTERIA_INIT="/opt/etc/init.d/S25hysteria"
HYSTERIA_SOCKS_PORT="11888"
PROXY_TAG="kox-proxy"
KOX_URI_GREP='^(vless|hysteria2|hy2)://'

# Если юзер вручную выключил VPN — не трогать
[ -f "$VPN_OFF_MARKER" ] && exit 0

# Если уже идёт авто-переключение — не запускать снова
[ -f "$SWITCHING_LOCK" ] && exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGF"; }

kox_xray_ulimit() { ulimit -n 65535 2>/dev/null || true; }

kox_xray_start() {
  kox_xray_ulimit
  if [ -x "$XRAY_INIT" ]; then
    "$XRAY_INIT" start 2>/dev/null
  else
    /opt/sbin/xray -config "$CONF" >> "$ERRLOG" 2>&1 &
  fi
}

kox_xray_restart() {
  kox_save_crash_log
  kox_xray_ulimit
  killall xray 2>/dev/null || true
  sleep 2
  kox_xray_start
  if [ "${KOX_PROTO:-vless}" = "hysteria2" ]; then
    sleep 1
    wd_hysteria_start
  fi
}

kox_hysteria_ok() {
  pgrep -f hysteria >/dev/null 2>&1 && \
    netstat -ln 2>/dev/null | grep -q ":${HYSTERIA_SOCKS_PORT} "
}

kox_save_crash_log() {
  [ -s "$ERRLOG" ] || return 0
  printf '\n--- %s watchdog ---\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$CRASHLOG"
  tail -25 "$ERRLOG" >> "$CRASHLOG" 2>/dev/null
}

# ── Protocol-agnostic URI helpers (mirrors kox-cli.sh) ────────────────
uri_is_hy() { case "$1" in hysteria2://*|hy2://*) return 0 ;; *) return 1 ;; esac; }
uri_proto() { uri_is_hy "$1" && printf 'hysteria2' || printf 'vless'; }
uri_host()  { printf '%s' "$1" | sed 's|^[a-z0-9]*://[^@]*@\([^:/?#]*\).*|\1|'; }
uri_port()  { printf '%s' "$1" | sed -n 's|^[a-z0-9]*://[^@]*@[^:/?#]*:\([0-9]*\).*|\1|p'; }
uri_userinfo() { printf '%s' "$1" | sed 's|^[a-z0-9]*://\([^@]*\)@.*|\1|'; }
uri_qparam() { printf '%s' "$1" | sed 's/^[^?]*?//; s/#.*//' | tr '&' '\n' | grep "^$2=" | head -1 | cut -d= -f2-; }

wd_conf_set() {
  K="$1"; V="$2"
  if grep -q "^${K}=" "$KOXCONF" 2>/dev/null; then
    sed -i "s|^${K}=.*|${K}=\"${V}\"|" "$KOXCONF"
  else
    printf '%s="%s"\n' "$K" "$V" >> "$KOXCONF"
  fi
}

wd_hysteria_write_conf() {
  URI="$1"
  H_AUTH=$(uri_userinfo "$URI"); H_HOST=$(uri_host "$URI")
  H_PORT=$(uri_port "$URI"); [ -z "$H_PORT" ] && H_PORT=443
  H_SNI=$(uri_qparam "$URI" sni); H_OBFS=$(uri_qparam "$URI" obfs)
  H_OBFSP=$(uri_qparam "$URI" obfs-password); H_INSEC=$(uri_qparam "$URI" insecure)
  mkdir -p "$(dirname "$HYSTERIA_CONF")"
  {
    printf 'server: %s:%s\n' "$H_HOST" "$H_PORT"
    printf 'auth: %s\n' "$H_AUTH"
    printf 'tls:\n'
    [ -n "$H_SNI" ] && printf '  sni: %s\n' "$H_SNI"
    { [ "$H_INSEC" = "1" ] || [ "$H_INSEC" = "true" ]; } && printf '  insecure: true\n'
    [ -n "$H_OBFS" ] && printf 'obfs:\n  type: %s\n  %s:\n    password: %s\n' "$H_OBFS" "$H_OBFS" "$H_OBFSP"
    printf 'socks5:\n  listen: 127.0.0.1:%s\n' "$HYSTERIA_SOCKS_PORT"
    printf 'fastOpen: true\n'
  } > "$HYSTERIA_CONF"
}

wd_hysteria_start() {
  if [ -x "$HYSTERIA_INIT" ]; then "$HYSTERIA_INIT" restart >/dev/null 2>&1
  else killall hysteria 2>/dev/null; sleep 1; "$HYSTERIA_BIN" client -c "$HYSTERIA_CONF" >> /opt/var/log/hysteria.log 2>&1 & fi
}
wd_hysteria_stop() { [ -x "$HYSTERIA_INIT" ] && "$HYSTERIA_INIT" stop >/dev/null 2>&1; killall hysteria 2>/dev/null; }

wd_proxy_set_socks() {
  TMP=/tmp/kox-wd-socks.json
  jq --argjson port "$HYSTERIA_SOCKS_PORT" --arg tag "$PROXY_TAG" '
    .outbounds = [.outbounds[] | if .tag == $tag then
      {tag: $tag, protocol: "socks", settings: {servers: [{address: "127.0.0.1", port: ($port|tonumber)}]}}
      else . end ]' "$CONF" > "$TMP" 2>/dev/null
  [ -s "$TMP" ] && jq -e . "$TMP" >/dev/null 2>&1 && mv "$TMP" "$CONF" || { rm -f "$TMP"; return 1; }
}

wd_proxy_set_vless() {
  P_ADDR="$1"; P_PORT="$2"; P_UUID="$3"; P_FLOW="$4"; P_SNI="$5"; P_PBK="$6"; P_SID="$7"; P_FP="$8"; P_SPX="$9"
  TMP=/tmp/kox-wd-vless.json
  jq --arg tag "$PROXY_TAG" --arg addr "$P_ADDR" --argjson port "${P_PORT:-443}" \
     --arg uuid "$P_UUID" --arg flow "$P_FLOW" --arg sni "${P_SNI:-www.google.com}" \
     --arg pbk "$P_PBK" --arg sid "$P_SID" --arg fp "${P_FP:-chrome}" --arg spx "${P_SPX:-/}" '
    .outbounds = [.outbounds[] | if .tag == $tag then
      {tag: $tag, protocol: "vless",
       settings: {vnext: [{address: $addr, port: ($port|tonumber),
         users: [{id: $uuid, encryption: "none", flow: $flow}]}]},
       streamSettings: {network: "tcp", security: "reality",
         realitySettings: {show: false, serverName: $sni, publicKey: $pbk,
           shortId: $sid, fingerprint: $fp, spiderX: $spx}}}
      else . end ]' "$CONF" > "$TMP" 2>/dev/null
  [ -s "$TMP" ] && jq -e . "$TMP" >/dev/null 2>&1 && mv "$TMP" "$CONF" || { rm -f "$TMP"; return 1; }
}

# Загрузить конфиг
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

FAILOVER_MINUTES="${KOX_FAILOVER_MINUTES:-3}"
AUTO_RETURN="${KOX_AUTO_RETURN:-yes}"
PREF_HOST="${KOX_PREFERRED_HOST:-}"
PREF_PORT="${KOX_PREFERRED_PORT:-443}"
PREF_REMARK="${KOX_PREFERRED_REMARK:-основной сервер}"
FD_WARN="${KOX_FD_WARN:-800}"
ACC_STALE_MINUTES="${KOX_ACC_STALE_MINUTES:-5}"

kox_acc_log_stale() {
  [ -f "$ACCLOG" ] || return 1
  local NOW MTIME AGE
  NOW=$(date +%s 2>/dev/null) || return 1
  MTIME=$(stat -c %Y "$ACCLOG" 2>/dev/null)
  [ -z "$MTIME" ] && return 1
  AGE=$((NOW - MTIME))
  [ "$AGE" -ge $((ACC_STALE_MINUTES * 60)) ]
}

kox_tunnel_ok() {
  local HTTP
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    -x socks5h://127.0.0.1:10809 --max-time 6 \
    "https://api.telegram.org" 2>/dev/null)
  case "$HTTP" in
    000|"") return 1 ;;
    *) return 0 ;;
  esac
}

kox_watchdog_switch_auto() {
  local REASON="${1:-сбой VPN}"
  local CURRENT_HOST NEW_SERVER SWITCH_RC NOW LAST ELAPSED

  CURRENT_HOST="${KOX_SERVER:-}"
  [ -z "$CURRENT_HOST" ] && CURRENT_HOST=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')
  NOW=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
  LAST=$(cat "$LAST_SWITCH_FILE" 2>/dev/null || echo 0)
  ELAPSED=$((NOW - LAST))
  if [ "$ELAPSED" -lt 1800 ] && [ -f "$LAST_SWITCH_FILE" ]; then
    log "Кулдаун switch-auto (${REASON}): ещё $((1800 - ELAPSED)) сек"
    return 1
  fi

  log "switch-auto: ${REASON} (текущий сервер: ${CURRENT_HOST:-?})"
  touch "$SWITCHING_LOCK"
  tg_notify "⚠️ <b>KOX Shield — переключаю сервер</b>

Причина: ${REASON}
Текущий: <code>${CURRENT_HOST:-?}</code>
Ищу рабочий сервер из подписки..."

  NEW_SERVER=$(/opt/bin/kox switch-auto --quiet 2>/dev/null)
  SWITCH_RC=$?
  rm -f "$SWITCHING_LOCK"

  if [ "$SWITCH_RC" = "0" ] && [ -n "$NEW_SERVER" ]; then
    printf '%s\n' "$NOW" > "$LAST_SWITCH_FILE"
    printf '0\n' > "$FAIL_COUNT_FILE"
    printf '0\n' > "$XRAY_START_FAIL_FILE"
    rm -f "$XRAY_WAS_DOWN"
    sh "$NAT_SCRIPT" 2>/dev/null
    log "switch-auto успешно: $NEW_SERVER"
    RETURN_NOTE=""
    [ "$AUTO_RETURN" = "yes" ] && [ -n "$PREF_HOST" ] && \
      RETURN_NOTE="

🔄 Когда основной (<b>${PREF_REMARK}</b>) восстановится — вернусь автоматически."
    tg_notify "✅ <b>KOX Shield — сервер переключён</b>

Было: <code>${CURRENT_HOST}</code>
Стало: <b>${NEW_SERVER}</b>
VPN восстановлен.${RETURN_NOTE}"
    return 0
  fi

  log "switch-auto не удался (код $SWITCH_RC)"
  tg_notify "❌ <b>KOX Shield — не удалось переключить сервер</b>

Причина: ${REASON}
Проверьте: <code>kox servers</code> или подписку."
  return 1
}

# ── Отправить сообщение в Telegram ───────────────────────────────────
tg_notify() {
  local MSG="$1"
  [ -z "${KOX_BOT_TOKEN:-}" ] || [ -z "${KOX_ADMIN_ID:-}" ] && return
  # Через VPN прокси сначала, потом напрямую
  curl -s -o /dev/null --max-time 8 \
    -x socks5h://127.0.0.1:10809 \
    "https://api.telegram.org/bot${KOX_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${KOX_ADMIN_ID}" \
    --data-urlencode "text=${MSG}" \
    -d "parse_mode=HTML" 2>/dev/null || \
  curl -s -o /dev/null --max-time 8 \
    "https://api.telegram.org/bot${KOX_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${KOX_ADMIN_ID}" \
    --data-urlencode "text=${MSG}" \
    -d "parse_mode=HTML" 2>/dev/null
}

# ── 1. Проверяем что xray работает ───────────────────────────────────
if ! pgrep xray >/dev/null 2>&1; then
  touch "$XRAY_WAS_DOWN"
  log "Xray не работает — снимаю iptables"
  iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  kox_save_crash_log
  if [ -f "$XRAY_INIT" ] || [ -x /opt/sbin/xray ]; then
    kox_xray_start
    sleep 5
    if pgrep xray >/dev/null 2>&1; then
      sh "$NAT_SCRIPT" 2>/dev/null
      log "Xray перезапущен, iptables восстановлен"
      if ! kox_tunnel_ok; then
        log "Xray запущен, но туннель не отвечает — пробую switch-auto"
        kox_watchdog_switch_auto "Xray поднялся, туннель мёртв" || true
      else
        printf '0\n' > "$XRAY_START_FAIL_FILE"
        rm -f "$XRAY_WAS_DOWN"
      fi
    else
      SF=$(cat "$XRAY_START_FAIL_FILE" 2>/dev/null || echo 0)
      SF=$((SF + 1))
      printf '%s\n' "$SF" > "$XRAY_START_FAIL_FILE"
      log "Xray не запустился (попытка ${SF})"
      if [ "$SF" -ge 2 ]; then
        kox_watchdog_switch_auto "Xray не запускается на текущем сервере" || true
      fi
      if ! pgrep xray >/dev/null 2>&1; then
        iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
        iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
        iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
        ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
        ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
        ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
        tg_notify "❌ <b>KOX Shield — Xray не запускается</b>

Перезапуск и смена сервера не помогли.
Iptables сняты — интернет напрямую.

<code>kox log</code> · <code>kox watchdog-log</code>"
        exit 0
      fi
    fi
  fi
fi

# ── 1b. Hysteria2-клиент (режим KOX_PROTO=hysteria2) ─────────────────
if [ "${KOX_PROTO:-vless}" = "hysteria2" ] && ! kox_hysteria_ok; then
  log "Hysteria2-клиент не работает — перезапускаю"
  wd_hysteria_start
  sleep 3
  if kox_hysteria_ok; then
    log "Hysteria2-клиент восстановлен"
    if pgrep xray >/dev/null 2>&1 && ! kox_tunnel_ok; then
      log "Hysteria OK, туннель нет — перезапуск Xray"
      kox_xray_restart
      sleep 3
      sh "$NAT_SCRIPT" 2>/dev/null
    fi
  else
    log "Hysteria2 не удалось запустить — switch-auto"
    kox_watchdog_switch_auto "Hysteria2-клиент не запускается" || true
  fi
fi

# ── 2. Проверяем порт 10808 ───────────────────────────────────────────
if ! netstat -ln 2>/dev/null | grep -q ':10808 '; then
  touch "$XRAY_WAS_DOWN"
  log "Xray порт 10808 не слушает — перезапуск"
  kox_xray_restart
  sleep 5
  if pgrep xray >/dev/null 2>&1 && netstat -ln 2>/dev/null | grep -q ':10808 '; then
    sh "$NAT_SCRIPT" 2>/dev/null
    log "Xray перезапущен после сбоя порта 10808"
    if ! kox_tunnel_ok; then
      log "Порт 10808 OK, туннель нет — switch-auto"
      kox_watchdog_switch_auto "порт 10808 без туннеля" || true
    fi
  else
    log "Порт 10808 не восстановился — switch-auto"
    kox_watchdog_switch_auto "порт 10808 не слушает" || true
  fi
fi

# ── 2b. Зависший Xray: процесс есть, но access-лог не пишется ─────────
if pgrep xray >/dev/null 2>&1 && \
   iptables -t nat -L PREROUTING 2>/dev/null | grep -q XRAY_REDIRECT && \
   kox_acc_log_stale; then
  STALE_SEC=$(( $(date +%s 2>/dev/null || echo 0) - $(stat -c %Y "$ACCLOG" 2>/dev/null || echo 0) ))
  log "Access-лог молчит ${STALE_SEC}s при активном VPN — Xray завис, перезапуск"
  touch "$XRAY_WAS_DOWN"
  tg_notify "⚠️ <b>KOX Shield — Xray завис</b>

Трафик через VPN не идёт (~${STALE_SEC} сек без записей в логе).
Перезапускаю Xray..."
  kox_xray_restart
  sleep 5
  sh "$NAT_SCRIPT" 2>/dev/null
  if kox_acc_log_stale; then
    log "После перезапуска access-лог всё ещё молчит — switch-auto"
    kox_watchdog_switch_auto "Xray завис (access-лог)" || true
  else
    log "Xray восстановлен после зависания (access-лог ожил)"
    rm -f "$XRAY_WAS_DOWN"
    printf '0\n' > "$FAIL_COUNT_FILE"
  fi
fi

# ── 3. Восстановить iptables если пропали ────────────────────────────
if ! iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT; then
  log "iptables правила пропали — восстанавливаю"
  sh "$NAT_SCRIPT" 2>/dev/null
fi

# ── 4. Получить текущий сервер ────────────────────────────────────────
CURRENT_HOST="${KOX_SERVER:-}"
[ -z "$CURRENT_HOST" ] && CURRENT_HOST=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')

# ── 5. Проверка автовозврата на основной сервер ───────────────────────
# Выполняем ПЕРЕД тестом туннеля чтобы работало даже когда резервный работает
if [ "$AUTO_RETURN" = "yes" ] && [ -n "$PREF_HOST" ] && [ "$CURRENT_HOST" != "$PREF_HOST" ]; then
  # Мы на резервном — проверяем вернулся ли основной (только pre-flight, быстро)
  PREF_BACK=0
  curl -s -o /dev/null -k --connect-timeout 3 --max-time 5 \
    "https://${PREF_HOST}:${PREF_PORT}/" 2>/dev/null && PREF_BACK=1
  [ "$PREF_BACK" = "0" ] && ping -c 1 -W 2 "$PREF_HOST" >/dev/null 2>&1 && PREF_BACK=1

  if [ "$PREF_BACK" = "1" ]; then
    log "Основной сервер ${PREF_HOST} снова доступен — переключаюсь обратно"
    tg_notify "🔄 <b>KOX Shield — основной сервер вернулся</b>

Основной сервер <b>${PREF_REMARK}</b> снова доступен.
Переключаюсь с резервного обратно на основной..."

    touch "$SWITCHING_LOCK"
    # Найти VLESS строку для основного сервера и переключиться
    local_sub_switch_pref() {
      [ -z "${KOX_SUB_URL:-}" ] && return 1
      RAW=$(curl -fsSL --max-time 10 "$KOX_SUB_URL" 2>/dev/null)
      DECODED=$(printf '%s' "$RAW" | base64 -d 2>/dev/null || printf '%s' "$RAW")
      # Match the preferred host across vless:// and hysteria2://|hy2://
      VLINE=$(printf '%s\n' "$DECODED" | grep -E "$KOX_URI_GREP" | grep "@${PREF_HOST}:" | head -1)
      [ -z "$VLINE" ] && return 1

      PROTO=$(uri_proto "$VLINE")
      PORT=$(uri_port "$VLINE"); P="${PORT:-443}"

      cp "$CONF" /tmp/kox-wd-backup.json 2>/dev/null
      cp "$KOXCONF" /tmp/kox-wd-conf-backup 2>/dev/null

      if [ "$PROTO" = "hysteria2" ]; then
        AUTH=$(uri_userinfo "$VLINE"); SNI=$(uri_qparam "$VLINE" sni)
        wd_hysteria_write_conf "$VLINE"
        # Set KOX_PROTO BEFORE start — S25hysteria gates on it.
        wd_conf_set KOX_PROTO hysteria2
        wd_hysteria_start
        wd_proxy_set_socks || return 1
        wd_conf_set KOX_SERVER "$PREF_HOST"
        wd_conf_set KOX_PORT "$P"
        wd_conf_set KOX_UUID "$AUTH"
        [ -n "$SNI" ] && wd_conf_set KOX_SNI "$SNI"
        wd_conf_set KOX_FLOW ""
      else
        UUID=$(uri_userinfo "$VLINE")
        PARAMS=$(printf '%s' "$VLINE" | sed 's/.*?\(.*\)#.*/\1/; s/.*?\(.*\)/\1/')
        SNI=$(printf '%s'  "$PARAMS" | grep -o 'sni=[^&]*'  | cut -d= -f2)
        FLOW=$(printf '%s' "$PARAMS" | grep -o 'flow=[^&]*' | cut -d= -f2)
        PBKEY=$(printf '%s' "$PARAMS"| grep -o 'pbk=[^&]*'  | cut -d= -f2)
        SID=$(printf '%s'  "$PARAMS" | grep -o 'sid=[^&]*'  | cut -d= -f2)
        FP=$(printf '%s'   "$PARAMS" | grep -o 'fp=[^&]*'   | cut -d= -f2)
        SPX=$(printf '%s'  "$PARAMS" | grep -o 'spx=[^&]*'  | cut -d= -f2 | sed 's/%2[Ff]/\//g')
        [ -z "$SPX" ] && SPX="/"
        wd_hysteria_stop
        wd_proxy_set_vless "$PREF_HOST" "$P" "$UUID" "$FLOW" "${SNI:-www.google.com}" "$PBKEY" "$SID" "${FP:-chrome}" "$SPX" || return 1
        wd_conf_set KOX_PROTO vless
        wd_conf_set KOX_SERVER "$PREF_HOST"
        wd_conf_set KOX_PORT "$P"
        wd_conf_set KOX_UUID "$UUID"
        wd_conf_set KOX_SNI "${SNI:-www.google.com}"
        wd_conf_set KOX_FLOW "$FLOW"
      fi

      kox_xray_restart

      # Poll xray
      for i in 1 2 3 4 5 6 7 8 9 10; do
        pgrep xray >/dev/null 2>&1 && netstat -ln 2>/dev/null | grep -q ':10808 ' && break
        sleep 1
      done

      # Test tunnel
      for i in 1 2 3 4; do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
          -x socks5h://127.0.0.1:10809 --max-time 5 "https://api.telegram.org" 2>/dev/null)
        case "$HTTP" in 000|"") sleep 1 ;; *) echo "$HTTP"; return 0 ;; esac
      done
      # Tunnel failed — restore config + kox.conf + hysteria state
      cp /tmp/kox-wd-backup.json "$CONF" 2>/dev/null
      cp /tmp/kox-wd-conf-backup "$KOXCONF" 2>/dev/null
      PREV_PROTO=$(grep -m1 '^KOX_PROTO=' "$KOXCONF" 2>/dev/null | cut -d'"' -f2)
      if [ "$PREV_PROTO" = "hysteria2" ]; then wd_hysteria_start; else wd_hysteria_stop; fi
      kox_xray_start
      return 1
    }

    HTTP_RET=$(local_sub_switch_pref 2>/dev/null)
    SWITCH_RC=$?
    rm -f "$SWITCHING_LOCK"

    if [ "$SWITCH_RC" = "0" ]; then
      log "Автовозврат на основной сервер выполнен: $PREF_HOST (HTTP $HTTP_RET)"
      printf '0\n' > "$FAIL_COUNT_FILE"
      tg_notify "✅ <b>KOX Shield — возврат на основной сервер</b>

Переключился обратно на: <b>${PREF_REMARK}</b>
<code>${PREF_HOST}</code>

VPN работает в штатном режиме."
    else
      log "Автовозврат не удался (туннель не прошёл) — остаюсь на резервном"
      tg_notify "⚠️ <b>KOX Shield — автовозврат не удался</b>

Основной сервер <b>${PREF_REMARK}</b> отвечает на ping, но VPN-туннель не прошёл.
Остаюсь на резервном сервере. Попробую снова через минуту."
    fi
    exit 0
  else
    log "На резервном сервере (${CURRENT_HOST}). Основной ${PREF_HOST} ещё недоступен."
  fi
fi

# ── 6. Тест реального VPN-туннеля ─────────────────────────────────────
FAST_SWITCH=0
if [ -f "$XRAY_WAS_DOWN" ]; then
  FAST_SWITCH=1
  rm -f "$XRAY_WAS_DOWN"
fi

if kox_tunnel_ok; then
  COUNT=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
  if [ "$COUNT" -gt 0 ]; then
    log "VPN-туннель восстановился — сброс счётчика"
    printf '0\n' > "$FAIL_COUNT_FILE"
  fi
  printf '0\n' > "$XRAY_START_FAIL_FILE"
else
  COUNT=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  printf '%s\n' "$COUNT" > "$FAIL_COUNT_FILE"
  log "VPN-туннель не отвечает — счётчик ${COUNT}/${FAILOVER_MINUTES} (быстрый=${FAST_SWITCH})"

  if [ "$FAST_SWITCH" = "1" ] || [ "$COUNT" -ge "$FAILOVER_MINUTES" ]; then
    if [ "$FAST_SWITCH" = "1" ]; then
      kox_watchdog_switch_auto "туннель упал после перезапуска Xray"
    else
      kox_watchdog_switch_auto "${FAILOVER_MINUTES} мин без VPN"
    fi
  fi
fi

# ── 7. Профилактика: слишком много открытых файловых дескрипторов ─────
XPID=$(pgrep xray 2>/dev/null | head -1)
if [ -n "$XPID" ] && [ -d "/proc/$XPID/fd" ]; then
  FD_COUNT=$(ls "/proc/$XPID/fd" 2>/dev/null | wc -l | tr -d ' ')
  case "$FD_COUNT" in
    ''|*[!0-9]*) FD_COUNT=0 ;;
  esac
  if [ "$FD_COUNT" -ge "$FD_WARN" ] 2>/dev/null; then
    log "Xray: ${FD_COUNT} открытых fd (порог ${FD_WARN}) — профилактический перезапуск"
    tg_notify "⚠️ <b>KOX Shield — профилактический перезапуск Xray</b>

Открыто файловых дескрипторов: <b>${FD_COUNT}</b> (порог ${FD_WARN}).
Перезапускаю Xray, чтобы избежать падения VPN."
    kox_xray_restart
    sleep 5
    if pgrep xray >/dev/null 2>&1; then
      sh "$NAT_SCRIPT" 2>/dev/null
      log "Профилактический перезапуск Xray выполнен (fd было ${FD_COUNT})"
    else
      log "Профилактический перезапуск не удался"
    fi
  fi
fi

# ── 8. Проверка и авто-восстановление Telegram бота ──────────────────
# Решает проблему когда бот падает (например после самообновления).
# Watchdog крутится каждую минуту — бот поднимется без SSH и без ребута.
BOT_INIT="/opt/etc/init.d/S90kox-bot"
BOT_LOCK="/tmp/kox-bot.lock"
if [ -f "$BOT_INIT" ]; then
  BOT_RUNNING=0
  if [ -f "$BOT_LOCK" ]; then
    BOT_PID=$(cat "$BOT_LOCK" 2>/dev/null)
    kill -0 "$BOT_PID" 2>/dev/null && BOT_RUNNING=1
  fi
  if [ "$BOT_RUNNING" = "0" ]; then
    log "Telegram бот не работает — перезапускаю"
    rm -f "$BOT_LOCK" 2>/dev/null
    "$BOT_INIT" start >/dev/null 2>&1
    sleep 2
    if [ -f "$BOT_LOCK" ] && kill -0 "$(cat "$BOT_LOCK" 2>/dev/null)" 2>/dev/null; then
      log "Telegram бот восстановлен"
    else
      log "Telegram бот не удалось запустить"
    fi
  fi
fi

# ── 9. Ротация лога ───────────────────────────────────────────────────
[ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 500 ] && \
  tail -250 "$LOGF" > "${LOGF}.tmp" && mv "${LOGF}.tmp" "$LOGF"
