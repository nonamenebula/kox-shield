#!/bin/sh
# KOX Shield — shared library (URI, validation, kox.conf helpers)
# Sourced by: kox-cli.sh, kox-bot.sh, kox-watchdog.sh

KOX_URI_GREP='^(vless|hysteria2|hy2)://'
KOX_RELAY_HOST="${KOX_RELAY_HOST:-kox.nonamenebula.ru}"
KOX_CDN_IP="${KOX_CDN_IP:-185.154.193.130}"
KOX_CDN="${KOX_CDN:-https://kox.nonamenebula.ru/static/kox-shield}"
GITHUB_RAW="${GITHUB_RAW:-https://raw.githubusercontent.com/nonamenebula/kox-shield/main}"
KOX_LISTS_CDN="${KOX_LISTS_CDN:-${KOX_CDN}/lists}"
GITHUB_LISTS="${GITHUB_LISTS:-${GITHUB_RAW}/lists}"

# Скачать URL → файл (IPv4, CA bundle). Для скриптов и списков доменов.
kox_fetch_url_to_file() {
  _url="$1"
  _dest="$2"
  _max="${3:-30}"
  _curl=""
  if [ -x /opt/bin/curl ]; then _curl=/opt/bin/curl
  elif command -v curl >/dev/null 2>&1; then _curl=curl
  fi
  _ca="${CURL_CA_BUNDLE:-}"
  [ -z "$_ca" ] && [ -f /opt/etc/ssl/certs/ca-certificates.crt ] && _ca=/opt/etc/ssl/certs/ca-certificates.crt

  _try_curl() {
    [ -n "$_curl" ] || return 1
    if [ -n "$_ca" ] && "$_curl" -fsSL -4 --max-time "$_max" --cacert "$_ca" "$1" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
      return 0
    fi
    if "$_curl" -fsSL -4 --max-time "$_max" "$1" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
      return 0
    fi
    if "$_curl" -fsSL --max-time "$_max" "$1" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
      return 0
    fi
    return 1
  }

  _try_wget() {
    [ -x /opt/bin/wget ] || return 1
    /opt/bin/wget -qO "$_dest" -4 -T "$_max" "$1" 2>/dev/null && [ -s "$_dest" ] && return 0
    return 1
  }

  _try_curl "$_url" && return 0
  _try_wget "$_url" && return 0

  # DNS на роутере часто не резолвит kox.nonamenebula.ru — пробуем по IP + Host
  case "$_url" in
    https://kox.nonamenebula.ru/*|http://kox.nonamenebula.ru/*)
      _path=${_url#*kox.nonamenebula.ru}
      _ipurl="https://${KOX_CDN_IP}${_path}"
      if [ -n "$_curl" ]; then
        if [ -n "$_ca" ] && "$_curl" -fsSL -4 --max-time "$_max" --cacert "$_ca" \
            -H "Host: kox.nonamenebula.ru" --resolve "kox.nonamenebula.ru:443:${KOX_CDN_IP}" \
            "https://kox.nonamenebula.ru${_path}" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
          return 0
        fi
        if "$_curl" -fsSL -4 --max-time "$_max" -k \
            -H "Host: kox.nonamenebula.ru" "$_ipurl" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
          return 0
        fi
      fi
      if [ -x /opt/bin/wget ]; then
        if /opt/bin/wget -qO "$_dest" -4 -T "$_max" --no-check-certificate \
            --header="Host: kox.nonamenebula.ru" "$_ipurl" 2>/dev/null && [ -s "$_dest" ]; then
          return 0
        fi
      fi
      ;;
  esac
  return 1
}

# Файл из lists/ (categories.json, youtube.txt, LISTS_VERSION, …).
# Сначала GitHub (источник), при недоступности — зеркало KOX CDN.
kox_fetch_list_rel() {
  _rel="$1"
  _dest="$2"
  _max="${3:-25}"
  kox_fetch_url_to_file "${GITHUB_LISTS}/${_rel}" "$_dest" "$_max" && return 0
  kox_fetch_url_to_file "${KOX_LISTS_CDN}/${_rel}" "$_dest" "$_max" && return 0
  return 1
}

kox_fetch_list_text() {
  _rel="$1"
  _max="${2:-15}"
  _tmp="/tmp/kox-list-fetch.$$"
  if kox_fetch_list_rel "$_rel" "$_tmp" "$_max"; then
    cat "$_tmp"
    rm -f "$_tmp"
    return 0
  fi
  rm -f "$_tmp"
  return 1
}

# Файл из корня репозитория (kox-cli.sh, VERSION, …).
# Сначала GitHub, при недоступности — зеркало KOX CDN.
kox_fetch_repo_file() {
  _rel="$1"
  _dest="$2"
  _max="${3:-30}"
  kox_fetch_url_to_file "${GITHUB_RAW}/${_rel}" "$_dest" "$_max" && return 0
  kox_fetch_url_to_file "${KOX_CDN}/${_rel}" "$_dest" "$_max" && return 0
  return 1
}

# Активен ли QUIC-блок (UDP/443 → DROP на LAN).
kox_quic_block_active() {
  iptables -t mangle -C PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null && return 0
  ip6tables -t mangle -C PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null && return 0
  return 1
}

# Скачать и установить 99-kox-nat.sh (CDN / GitHub).
kox_install_nat_script() {
  _dest="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
  mkdir -p /opt/etc/ndm/netfilter.d
  if kox_fetch_repo_file "99-kox-nat.sh" "$_dest" 15 && [ -s "$_dest" ]; then
    chmod +x "$_dest"
    return 0
  fi
  return 1
}

# Применить NAT + QUIC-блок (IPv4 и IPv6).
kox_apply_nat_rules() {
  _nat="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
  [ -f "$_nat" ] || return 1
  sh "$_nat" 2>/dev/null || return 1
  sh "$_nat" ip6tables 2>/dev/null || true
  return 0
}

# Интерактивный ввод (stdin может быть pipe, читаем с TTY).
kox_read_tty() {
  _var="$1"
  if [ -r /dev/tty ]; then
    IFS= read -r _line </dev/tty 2>/dev/null || IFS= read -r _line
  else
    IFS= read -r _line
  fi
  eval "$_var=\$_line"
}

# y / yes / д / да / 1 — с учётом пробелов и регистра.
kox_confirm_yes() {
  _ans=$(printf '%s' "$1" | tr -d '\r\n\t ' | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')
  case "$_ans" in
    y|yes|ye|1|d|da|д|да) return 0 ;;
  esac
  return 1
}
  _text="$1"
  _pat="$2"
  _n=$(printf '%s\n' "$_text" | grep -E "$_pat" 2>/dev/null | wc -l | tr -d ' \n\r')
  case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
  printf '%d' "$_n"
}

kox_normalize_sub_url() {
  _url="$1"
  case "$_url" in
    */u/*)
      _base=${_url%%/u/*}
      _token=${_url#*/u/}
      _token=${_token%%/*}
      _token=${_token%%\?*}
      _token=${_token%%#*}
      if [ -n "$_base" ] && [ -n "$_token" ]; then
        printf '%s/c/%s' "$_base" "$_token"
        return 0
      fi
      ;;
  esac
  printf '%s' "$_url"
}

kox_is_html_payload() {
  case "$1" in
    *'<!DOCTYPE'*|*'<!doctype'*|*'<html'*|*'<HTML'*|*'<head'*|*'<HEAD'*)
      return 0
      ;;
  esac
  return 1
}

kox_decode_subscription_body() {
  _in="$1"
  _out=$(printf '%s' "$_in" | base64 -d 2>/dev/null) && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
  _out=$(printf '%s' "$_in" | base64 -D 2>/dev/null) && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
  if command -v openssl >/dev/null 2>&1; then
    _out=$(printf '%s' "$_in" | openssl base64 -d -A 2>/dev/null) && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
  fi
  printf '%s' "$_in"
}

# Список серверов для меню: VLESS relay → другие VLESS → Hysteria2.
kox_build_sub_server_list() {
  _raw="$1"
  _outfile="$2"
  : > "$_outfile"
  _relay=$(printf '%s\n' "$_raw" | grep -E '^vless://' | grep "@${KOX_RELAY_HOST}:" || true)
  _vother=$(printf '%s\n' "$_raw" | grep -E '^vless://' | grep -v "@${KOX_RELAY_HOST}:" || true)
  _hy2=$(printf '%s\n' "$_raw" | grep -E '^(hysteria2|hy2)://' || true)
  if [ -n "$_relay" ]; then printf '%s\n' "$_relay" >> "$_outfile"; fi
  if [ -n "$_vother" ]; then printf '%s\n' "$_vother" >> "$_outfile"; fi
  if [ -n "$_hy2" ]; then printf '%s\n' "$_hy2" >> "$_outfile"; fi
}

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
