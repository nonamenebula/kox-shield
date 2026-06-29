#!/bin/sh
# KOX Shield — shared library (URI, validation, kox.conf helpers)
# Sourced by: kox-cli.sh, kox-bot.sh, kox-watchdog.sh

KOX_URI_GREP='^(vless|hysteria2|hy2)://'

uri_is_hy() { case "$1" in hysteria2://*|hy2://*) return 0 ;; *) return 1 ;; esac; }
uri_proto() { uri_is_hy "$1" && printf 'hysteria2' || printf 'vless'; }
uri_host()  { printf '%s' "$1" | sed 's|^[a-z0-9]*://[^@]*@\([^:/?#]*\).*|\1|'; }
uri_port()  { printf '%s' "$1" | sed -n 's|^[a-z0-9]*://[^@]*@[^:/?#]*:\([0-9]*\).*|\1|p'; }
uri_userinfo() { printf '%s' "$1" | sed 's|^[a-z0-9]*://\([^@]*\)@.*|\1|'; }
uri_remark() { printf '%s' "$1" | sed -n 's/.*#//p'; }
uri_qparam() {
  _p="$2"
  printf '%s' "$1" | sed 's/^[^?]*?//; s/#.*//' | tr '&' '\n' | grep "^${_p}=" | head -1 | cut -d= -f2-
}

kox_url_decode() {
  printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9]*\)/\\x\1/g')"
}

kox_decode_remark() {
  kox_url_decode "$1"
}

# Домен: буквы, цифры, точки, дефис; минимум одна точка
kox_validate_domain() {
  _d="$1"
  [ -n "$_d" ] || return 1
  case "$_d" in
    *[\"\\\'\ \	\|\&\;]*|*..*) return 1 ;;
  esac
  printf '%s' "$_d" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'
}

# IPv4 или IPv4/CIDR (упрощённая проверка)
kox_validate_ip_cidr() {
  _ip="$1"
  [ -n "$_ip" ] || return 1
  case "$_ip" in
    *[\"\\\'\ \	]*|*[\|\&\;]*) return 1 ;;
  esac
  case "$_ip" in
    */*)
      _base=${_ip%%/*}
      _pfx=${_ip##*/}
      case "$_pfx" in
        ''|*[!0-9]*) return 1 ;;
      esac
      [ "$_pfx" -ge 0 ] 2>/dev/null && [ "$_pfx" -le 32 ] 2>/dev/null || return 1
      _ip="$_base"
      ;;
  esac
  printf '%s' "$_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

# Безопасная запись kox.conf (без sed-инъекций)
kox_conf_set() {
  _k="$1"
  _v="$2"
  _f="${3:-/opt/etc/xray/kox.conf}"
  [ -n "$_k" ] || return 1
  if [ ! -f "$_f" ]; then
    printf '%s="%s"\n' "$_k" "$_v" > "$_f"
  elif grep -q "^${_k}=" "$_f" 2>/dev/null; then
    _tmp="/tmp/kox-conf-set.$$"
    while IFS= read -r _line; do
      case "$_line" in
        "${_k}="*) printf '%s="%s"\n' "$_k" "$_v" ;;
        *) printf '%s\n' "$_line" ;;
      esac
    done < "$_f" > "$_tmp" && mv "$_tmp" "$_f"
  else
    printf '%s="%s"\n' "$_k" "$_v" >> "$_f"
  fi
}

kox_hysteria_write_conf() {
  _uri="$1"
  _hconf="${HYSTERIA_CONF:-/opt/etc/hysteria/client.yaml}"
  _hport="${HYSTERIA_SOCKS_PORT:-11888}"
  _auth=$(uri_userinfo "$_uri")
  _host=$(uri_host "$_uri")
  _port=$(uri_port "$_uri"); [ -z "$_port" ] && _port=443
  _sni=$(uri_qparam "$_uri" sni)
  _obfs=$(uri_qparam "$_uri" obfs)
  _obfsp=$(uri_qparam "$_uri" obfs-password)
  _insec=$(uri_qparam "$_uri" insecure)
  mkdir -p "$(dirname "$_hconf")"
  {
    printf 'server: %s:%s\n' "$_host" "$_port"
    printf 'auth: %s\n' "$_auth"
    printf 'tls:\n'
    [ -n "$_sni" ] && printf '  sni: %s\n' "$_sni"
    { [ "$_insec" = "1" ] || [ "$_insec" = "true" ]; } && printf '  insecure: true\n'
    if [ -n "$_obfs" ]; then
      printf 'obfs:\n  type: %s\n  %s:\n    password: %s\n' "$_obfs" "$_obfs" "$_obfsp"
    fi
    printf 'socks5:\n  listen: 127.0.0.1:%s\n' "$_hport"
    printf 'fastOpen: true\n'
  } > "$_hconf"
}

kox_show_server_info() {
  _koxconf="${1:-/opt/etc/xray/kox.conf}"
  _conf="${2:-/opt/etc/xray/config.json}"
  if [ -f "$_koxconf" ]; then
    # shellcheck disable=SC1090
    . "$_koxconf" 2>/dev/null
  fi
  _proto="${KOX_PROTO:-vless}"
  _srv="${KOX_SERVER:-}"
  _port="${KOX_PORT:-443}"
  _auth="${KOX_UUID:-}"
  _sni="${KOX_SNI:-}"
  _flow="${KOX_FLOW:-}"
  if [ -z "$_srv" ]; then
    _srv=$(grep -m1 '"address"' "$_conf" 2>/dev/null | sed 's/.*"address": *"\([^"]*\)".*/\1/')
    _port=$(grep -m1 '"port"' "$_conf" 2>/dev/null | sed 's/.*"port": *\([0-9]*\).*/\1/')
    _auth=$(grep -m1 '"id"' "$_conf" 2>/dev/null | sed 's/.*"id": *"\([^"]*\)".*/\1/')
    _sni=$(grep -m1 '"serverName"' "$_conf" 2>/dev/null | sed 's/.*"serverName": *"\([^"]*\)".*/\1/')
  fi
  printf 'PROTO=%s\nSRV=%s\nPORT=%s\nAUTH=%s\nSNI=%s\nFLOW=%s\nSUB=%s\n' \
    "$_proto" "$_srv" "$_port" "$_auth" "$_sni" "$_flow" "${KOX_SUB_URL:-}"
}
