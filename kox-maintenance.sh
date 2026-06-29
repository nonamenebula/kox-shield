#!/bin/sh
# KOX Shield — ежедневное обслуживание (kox-maintenance, cron 04:05)
# В режиме hysteria2 перезапускает и hysteria-клиент, и Xray.

KOXCONF="/opt/etc/xray/kox.conf"
XRAY_INIT="/opt/etc/init.d/S24xray"
HYSTERIA_INIT="/opt/etc/init.d/S25hysteria"
VPN_OFF_MARKER="/tmp/kox-vpn-off"
LOG="/opt/var/log/kox-maintenance.log"

[ -f "$VPN_OFF_MARKER" ] && exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

ulimit -n 65535 2>/dev/null || true
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

log "maintenance start proto=${KOX_PROTO:-vless}"

if [ "${KOX_PROTO:-vless}" = "hysteria2" ] && [ -x "$HYSTERIA_INIT" ]; then
  "$HYSTERIA_INIT" restart >> "$LOG" 2>&1
  log "hysteria restart done"
fi

if [ -x "$XRAY_INIT" ]; then
  "$XRAY_INIT" restart >> "$LOG" 2>&1
  log "xray restart done"
else
  log "S24xray missing"
fi

# После перезапуска Xray hysteria могла упасть — поднять снова
if [ "${KOX_PROTO:-vless}" = "hysteria2" ]; then
  sleep 2
  if ! pgrep -f hysteria >/dev/null 2>&1; then
    log "hysteria down after xray restart — starting"
    [ -x "$HYSTERIA_INIT" ] && "$HYSTERIA_INIT" start >> "$LOG" 2>&1
  fi
fi

log "maintenance done"
