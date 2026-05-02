#!/bin/sh
# KOX Watchdog v4
# — перезапускает xray при падении
# — считает минуты без VPN (порог: KOX_FAILOVER_MINUTES, default 10)
# — переключается на резервный сервер после N минут
# — возвращает на основной сервер когда тот появляется (KOX_AUTO_RETURN=yes)
# — отправляет уведомления в Telegram

KOXCONF="/opt/etc/xray/kox.conf"
CONF="/opt/etc/xray/config.json"
NAT_SCRIPT="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
LOGF="/opt/var/log/kox-watchdog.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')
VPN_OFF_MARKER="/tmp/kox-vpn-off"
FAIL_COUNT_FILE="/tmp/kox-vpn-fail-count"
LAST_SWITCH_FILE="/tmp/kox-last-auto-switch"
SWITCHING_LOCK="/tmp/kox-autoswitch.lock"

# Если юзер вручную выключил VPN — не трогать
[ -f "$VPN_OFF_MARKER" ] && exit 0

# Если уже идёт авто-переключение — не запускать снова
[ -f "$SWITCHING_LOCK" ] && exit 0

log() { printf '%s %s\n' "$TS" "$*" >> "$LOGF"; }

# Загрузить конфиг
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

FAILOVER_MINUTES="${KOX_FAILOVER_MINUTES:-10}"
AUTO_RETURN="${KOX_AUTO_RETURN:-yes}"
PREF_HOST="${KOX_PREFERRED_HOST:-}"
PREF_REMARK="${KOX_PREFERRED_REMARK:-основной сервер}"

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
  log "Xray не работает — снимаю iptables"
  iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  if [ -f /opt/etc/init.d/S24xray ]; then
    /opt/etc/init.d/S24xray start 2>/dev/null
    sleep 5
    if pgrep xray >/dev/null 2>&1; then
      sh "$NAT_SCRIPT" 2>/dev/null
      log "Xray перезапущен, iptables восстановлен"
    else
      log "Xray не удалось перезапустить"
    fi
  fi
  exit 0
fi

# ── 2. Проверяем порт 10808 ───────────────────────────────────────────
if ! netstat -ln 2>/dev/null | grep -q ':10808 '; then
  log "Xray порт 10808 не слушает — перезапуск"
  killall xray 2>/dev/null; sleep 2
  /opt/etc/init.d/S24xray start 2>/dev/null &
  exit 0
fi

# ── 3. Восстановить iptables если пропали ────────────────────────────
if ! iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT; then
  log "iptables правила пропали — восстанавливаю"
  sh "$NAT_SCRIPT" 2>/dev/null
fi

# ── 4. Получить текущий сервер ────────────────────────────────────────
CURRENT_HOST=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')

# ── 5. Проверка автовозврата на основной сервер ───────────────────────
# Выполняем ПЕРЕД тестом туннеля чтобы работало даже когда резервный работает
if [ "$AUTO_RETURN" = "yes" ] && [ -n "$PREF_HOST" ] && [ "$CURRENT_HOST" != "$PREF_HOST" ]; then
  # Мы на резервном — проверяем вернулся ли основной (только pre-flight, быстро)
  PREF_BACK=0
  curl -s -o /dev/null -k --connect-timeout 3 --max-time 5 \
    "https://${PREF_HOST}/" 2>/dev/null && PREF_BACK=1
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
      VLINE=$(printf '%s\n' "$DECODED" | grep "^vless://" | grep "@${PREF_HOST}:" | head -1)
      [ -z "$VLINE" ] && return 1

      UUID=$(printf '%s' "$VLINE" | sed 's|vless://\([^@]*\)@.*|\1|')
      PORT=$(printf '%s' "$VLINE" | sed 's|vless://[^@]*@[^:]*:\([0-9]*\).*|\1|')
      PARAMS=$(printf '%s' "$VLINE" | sed 's/.*?\(.*\)#.*/\1/; s/.*?\(.*\)/\1/')
      SNI=$(printf '%s'  "$PARAMS" | grep -o 'sni=[^&]*'  | cut -d= -f2)
      FLOW=$(printf '%s' "$PARAMS" | grep -o 'flow=[^&]*' | cut -d= -f2)
      PBKEY=$(printf '%s' "$PARAMS"| grep -o 'pbk=[^&]*'  | cut -d= -f2)
      SID=$(printf '%s'  "$PARAMS" | grep -o 'sid=[^&]*'  | cut -d= -f2)
      FP=$(printf '%s'   "$PARAMS" | grep -o 'fp=[^&]*'   | cut -d= -f2)
      SPX=$(printf '%s'  "$PARAMS" | grep -o 'spx=[^&]*'  | cut -d= -f2 | sed 's/%2[Ff]/\//g')
      [ -z "$SPX" ] && SPX="/"
      P="${PORT:-443}"

      cp "$CONF" /tmp/kox-wd-backup.json 2>/dev/null

      jq --arg addr "$PREF_HOST" --argjson port "$P" \
         --arg uuid "$UUID" --arg sni "${SNI:-www.google.com}" \
         --arg flow "$FLOW" --arg pbkey "$PBKEY" \
         --arg sid "$SID" --arg fp "${FP:-chrome}" --arg spx "$SPX" '
        .outbounds = [.outbounds[] |
          if .protocol == "vless" then
            .settings.vnext[0].address = $addr |
            .settings.vnext[0].port = ($port | tonumber) |
            .settings.vnext[0].users[0].id = $uuid |
            .settings.vnext[0].users[0].flow = $flow |
            .streamSettings.realitySettings.serverName = $sni |
            (if $pbkey != "" then .streamSettings.realitySettings.publicKey  = $pbkey else . end) |
            (if $sid   != "" then .streamSettings.realitySettings.shortId    = $sid   else . end) |
            (if $fp    != "" then .streamSettings.realitySettings.fingerprint = $fp   else . end) |
            .streamSettings.realitySettings.spiderX = $spx
          else . end
        ]
      ' "$CONF" > /tmp/kox-wd-new.json 2>/dev/null
      [ -s /tmp/kox-wd-new.json ] && mv /tmp/kox-wd-new.json "$CONF" || return 1

      # Update kox.conf
      sed -i "s|^KOX_SERVER=.*|KOX_SERVER=\"${PREF_HOST}\"|" "$KOXCONF" 2>/dev/null
      sed -i "s|^KOX_PORT=.*|KOX_PORT=\"${P}\"|" "$KOXCONF" 2>/dev/null
      sed -i "s|^KOX_UUID=.*|KOX_UUID=\"${UUID}\"|" "$KOXCONF" 2>/dev/null

      killall xray 2>/dev/null; sleep 2
      [ -x /opt/etc/init.d/S24xray ] && /opt/etc/init.d/S24xray start >/dev/null 2>&1 || \
        /opt/sbin/xray -config "$CONF" >> /opt/var/log/xray-err.log 2>&1 &

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
      # Tunnel failed — restore
      cp /tmp/kox-wd-backup.json "$CONF" 2>/dev/null
      killall xray 2>/dev/null; sleep 2
      [ -x /opt/etc/init.d/S24xray ] && /opt/etc/init.d/S24xray start >/dev/null 2>&1
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
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -x socks5h://127.0.0.1:10809 --max-time 6 \
  "https://api.telegram.org" 2>/dev/null)

case "$HTTP_CODE" in
  000|"")
    COUNT=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    printf '%s\n' "$COUNT" > "$FAIL_COUNT_FILE"
    log "VPN-туннель не отвечает (HTTP=000) — счётчик: ${COUNT}/${FAILOVER_MINUTES}"

    if [ "$COUNT" -ge "$FAILOVER_MINUTES" ]; then
      # Кулдаун: не чаще 1 раза в 30 мин
      NOW=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
      LAST=$(cat "$LAST_SWITCH_FILE" 2>/dev/null || echo 0)
      ELAPSED=$((NOW - LAST))
      if [ "$ELAPSED" -lt 1800 ]; then
        log "Кулдаун авто-переключения: ещё $((1800 - ELAPSED)) сек"
        exit 0
      fi

      log "${FAILOVER_MINUTES} минут без VPN — запускаю авто-переключение"
      touch "$SWITCHING_LOCK"

      tg_notify "⚠️ <b>KOX Shield — VPN недоступен ${FAILOVER_MINUTES} мин</b>

Сервер: <code>${CURRENT_HOST}</code>
Ищу рабочий резервный сервер..."

      NEW_SERVER=$(/opt/bin/kox switch-auto --quiet 2>/dev/null)
      SWITCH_RC=$?
      rm -f "$SWITCHING_LOCK"

      if [ "$SWITCH_RC" = "0" ] && [ -n "$NEW_SERVER" ]; then
        printf '%s\n' "$NOW" > "$LAST_SWITCH_FILE"
        printf '0\n' > "$FAIL_COUNT_FILE"
        log "Авто-переключение успешно: $NEW_SERVER"

        RETURN_NOTE=""
        [ "$AUTO_RETURN" = "yes" ] && [ -n "$PREF_HOST" ] && \
          RETURN_NOTE="

🔄 Когда основной сервер (<b>${PREF_REMARK}</b>) восстановится — автоматически вернусь на него."

        tg_notify "✅ <b>KOX Shield — переключился на резервный сервер</b>

Предыдущий: <code>${CURRENT_HOST}</code>
Новый: <b>${NEW_SERVER}</b>

VPN восстановлен.${RETURN_NOTE}"
      else
        log "Авто-переключение не удалось — все серверы проверены"
        tg_notify "❌ <b>KOX Shield — VPN недоступен</b>

Сервер: <code>${CURRENT_HOST}</code>
Все серверы из подписки проверены — ни один не работает.

Интернет работает напрямую (без VPN).
Проверьте серверы: /Серверы в боте или <code>kox servers</code>"
      fi
    fi
    ;;
  *)
    # Туннель работает — сбрасываем счётчик
    COUNT=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    if [ "$COUNT" -gt 0 ]; then
      log "VPN-туннель восстановился (HTTP ${HTTP_CODE}) — сброс счётчика"
      printf '0\n' > "$FAIL_COUNT_FILE"
    fi
    ;;
esac

# ── 7. Ротация лога ───────────────────────────────────────────────────
[ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 500 ] && \
  tail -250 "$LOGF" > "${LOGF}.tmp" && mv "${LOGF}.tmp" "$LOGF"
