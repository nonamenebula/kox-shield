#!/bin/sh
# KOX Watchdog v3
# — перезапускает xray при падении
# — считает минуты без VPN
# — после 10 мин переключается на резервный сервер из подписки
# — шлёт уведомление в Telegram-бот

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

# ── Отправить сообщение в Telegram ───────────────────────────────────
tg_notify() {
  local MSG="$1"
  [ ! -f "$KOXCONF" ] && return
  . "$KOXCONF" 2>/dev/null
  [ -z "${KOX_BOT_TOKEN:-}" ] || [ -z "${KOX_ADMIN_ID:-}" ] && return
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
      log "Xray не удалось перезапустить — интернет напрямую"
    fi
  fi
  exit 0
fi

# ── 2. Проверяем что порт 10808 слушает ──────────────────────────────
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

# ── 4. Проверяем реальный VPN-туннель ────────────────────────────────
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -x socks5h://127.0.0.1:10809 --max-time 6 \
  "https://api.telegram.org" 2>/dev/null)

case "$HTTP_CODE" in
  000|"")
    # Туннель не отвечает — увеличиваем счётчик
    COUNT=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    printf '%s\n' "$COUNT" > "$FAIL_COUNT_FILE"
    log "VPN-туннель не отвечает (HTTP=000) — счётчик: ${COUNT}/10"

    if [ "$COUNT" -ge 10 ]; then
      # ── Авто-переключение на резервный сервер ──────────────────────
      # Кулдаун: не чаще раза в 30 минут
      NOW=$(cat /proc/uptime 2>/dev/null | cut -d. -f1)
      LAST=$(cat "$LAST_SWITCH_FILE" 2>/dev/null || echo 0)
      ELAPSED=$((NOW - LAST))
      if [ "$ELAPSED" -lt 1800 ]; then
        log "Кулдаун авто-переключения: ещё $((1800 - ELAPSED)) сек"
        exit 0
      fi

      log "10 минут без VPN — запускаю авто-переключение на резервный сервер"
      touch "$SWITCHING_LOCK"

      . "$KOXCONF" 2>/dev/null
      CURRENT_HOST=$(grep -m1 '"address"' "$CONF" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')

      tg_notify "⚠️ <b>KOX Shield — VPN недоступен 10 мин</b>

Сервер: <code>${CURRENT_HOST}</code>
Запускаю поиск резервного сервера..."

      NEW_SERVER=$(/opt/bin/kox switch-auto --quiet 2>/dev/null)
      SWITCH_RC=$?

      rm -f "$SWITCHING_LOCK"

      if [ "$SWITCH_RC" = "0" ] && [ -n "$NEW_SERVER" ]; then
        printf '%s\n' "$NOW" > "$LAST_SWITCH_FILE"
        printf '0\n' > "$FAIL_COUNT_FILE"
        log "Авто-переключение успешно: $NEW_SERVER"
        tg_notify "✅ <b>KOX Shield — авто-переключение выполнено</b>

Предыдущий сервер недоступен: <code>${CURRENT_HOST}</code>
Новый сервер: <b>${NEW_SERVER}</b>

VPN восстановлен автоматически."
      else
        log "Авто-переключение не удалось — все серверы недоступны"
        tg_notify "❌ <b>KOX Shield — VPN недоступен</b>

Сервер: <code>${CURRENT_HOST}</code>
Все серверы из подписки проверены — ни один не отвечает.

Интернет работает напрямую (без VPN).
Проверьте вручную: /Серверы в боте или <code>kox servers</code>"
      fi
    fi
    ;;
  *)
    # Туннель работает — сбрасываем счётчик
    if [ "$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)" -gt 0 ]; then
      log "VPN-туннель восстановился (HTTP ${HTTP_CODE}) — сбрасываю счётчик"
      printf '0\n' > "$FAIL_COUNT_FILE"
    fi
    ;;
esac

# ── 5. Ротация лога ───────────────────────────────────────────────────
[ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 500 ] && \
  tail -250 "$LOGF" > "${LOGF}.tmp" && mv "${LOGF}.tmp" "$LOGF"
