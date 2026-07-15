#!/bin/sh
# KOX Shield — ежедневное обслуживание (kox-maintenance, cron 04:05)
PATH=/opt/sbin:/opt/bin:/sbin:/usr/sbin:/usr/bin:/bin
export PATH

KOX_LIB="/opt/etc/kox-lib.sh"
[ -f "$KOX_LIB" ] && . "$KOX_LIB"

KOXCONF="/opt/etc/xray/kox.conf"
XRAY_INIT="/opt/etc/init.d/S24xray"
HYSTERIA_INIT="/opt/etc/init.d/S25hysteria"
HYSTERIA_SOCKS_PORT="11888"
VPN_OFF_MARKER="/tmp/kox-vpn-off"
LOG="/opt/var/log/kox-maintenance.log"
LOG_DIR="/opt/var/log"

[ -f "$VPN_OFF_MARKER" ] && exit 0

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

rotate_log() {
  _f="$1"; _max_kb="$2"; _keep_kb="${3:-$2}"
  [ -f "$_f" ] || return 0
  _sz=$(wc -c < "$_f" 2>/dev/null | tr -d ' ')
  [ -z "$_sz" ] && return 0
  [ "$_sz" -le $((_max_kb * 1024)) ] && return 0
  tail -c $((_keep_kb * 1024)) "$_f" > "${_f}.rot" 2>/dev/null \
    && mv "${_f}.rot" "$_f" \
    && log "rotated $(basename "$_f") (${_sz}B -> ~$((_keep_kb * 1024))B)"
}

hysteria_ok() {
  pgrep -f hysteria >/dev/null 2>&1 && \
    netstat -ln 2>/dev/null | grep -q ":${HYSTERIA_SOCKS_PORT} "
}

ulimit -n 65535 2>/dev/null || true
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

rotate_log "${LOG_DIR}/xray-acc.log" 2048 512
rotate_log "${LOG_DIR}/xray-err.log" 512 256
rotate_log "${LOG_DIR}/hysteria.log" 512 256
rotate_log "${LOG_DIR}/kox-bot.log" 512 256
rotate_log "${LOG_DIR}/kox-update.log" 256 128
rotate_log "${LOG_DIR}/xray-err.last-crash.log" 256 128
rotate_log "$LOG" 256 64

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

if [ "${KOX_PROTO:-vless}" = "hysteria2" ]; then
  sleep 2
  if ! hysteria_ok; then
    log "hysteria down after xray restart — starting"
    [ -x "$HYSTERIA_INIT" ] && "$HYSTERIA_INIT" start >> "$LOG" 2>&1
    sleep 2
    hysteria_ok && log "hysteria recovered" || log "hysteria still down"
  fi
fi

if pgrep xray >/dev/null 2>&1 && [ ! -f "$VPN_OFF_MARKER" ]; then
  if type kox_apply_nat_rules >/dev/null 2>&1 && kox_apply_nat_rules; then
    log "iptables NAT восстановлен после maintenance"
  else
    log "WARN: не удалось восстановить iptables NAT после maintenance"
  fi
fi

log "maintenance done"
