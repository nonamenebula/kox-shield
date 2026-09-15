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
    case "$1" in
      https://*) return 1 ;;
    esac
    if [ -x /opt/bin/wget ]; then
      /opt/bin/wget -qO "$_dest" -4 -T "$_max" "$1" 2>/dev/null && [ -s "$_dest" ] && return 0
    fi
    return 1
  }

  _try_cdn_ip() {
    case "$_url" in
      https://kox.nonamenebula.ru/*|http://kox.nonamenebula.ru/*)
        _path=${_url#*kox.nonamenebula.ru}
        ;;
      *) return 1 ;;
    esac
    [ -n "$_curl" ] || return 1
    _ipurl="https://${KOX_CDN_IP}${_path}"
    if [ -n "$_ca" ] && "$_curl" -fsSL -4 --max-time "$_max" --cacert "$_ca" \
        -H "Host: kox.nonamenebula.ru" --resolve "kox.nonamenebula.ru:443:${KOX_CDN_IP}" \
        "https://kox.nonamenebula.ru${_path}" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
      return 0
    fi
    if "$_curl" -fsSL -4 --max-time "$_max" -k \
        -H "Host: kox.nonamenebula.ru" "$_ipurl" -o "$_dest" 2>/dev/null && [ -s "$_dest" ]; then
      return 0
    fi
    return 1
  }

  _try_curl "$_url" && return 0
  _try_cdn_ip && return 0
  _try_wget "$_url" && return 0
  return 1
}

# Файл из lists/ (categories.json, youtube.txt, LISTS_VERSION, …).
# Сначала CDN (без кэша raw.githubusercontent.com), затем GitHub.
kox_fetch_list_rel() {
  _rel="$1"
  _dest="$2"
  _max="${3:-25}"
  kox_fetch_url_to_file "${KOX_LISTS_CDN}/${_rel}" "$_dest" "$_max" && return 0
  kox_fetch_url_to_file "${GITHUB_LISTS}/${_rel}" "$_dest" "$_max" && return 0
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

# VERSION / CHANGELOG — сначала CDN (быстро), затем GitHub (короткий таймаут).
kox_fetch_repo_meta() {
  _rel="$1"
  _dest="$2"
  _max="${3:-12}"
  kox_fetch_url_to_file "${KOX_CDN}/${_rel}" "$_dest" "$_max" && return 0
  kox_fetch_url_to_file "${GITHUB_RAW}/${_rel}" "$_dest" 8 && return 0
  return 1
}

# Скрипты при kox upgrade — CDN первым (быстро), GitHub fallback 6 с.
kox_fetch_repo_upgrade() {
  _rel="$1"
  _dest="$2"
  kox_fetch_url_to_file "${KOX_CDN}/${_rel}" "$_dest" 12 && return 0
  kox_fetch_url_to_file "${GITHUB_RAW}/${_rel}" "$_dest" 6 && return 0
  return 1
}

# curl + ca-certificates (BusyBox wget не умеет https://).
kox_ensure_https_tools() {
  if [ -x /opt/bin/opkg ]; then
    command -v curl >/dev/null 2>&1 || [ -x /opt/bin/curl ] || \
      /opt/bin/opkg install curl >/dev/null 2>&1
    /opt/bin/opkg list-installed 2>/dev/null | grep -q '^ca-certificates ' || \
      /opt/bin/opkg install ca-certificates >/dev/null 2>&1
  fi
  if [ -f /opt/etc/ssl/certs/ca-certificates.crt ]; then
    export CURL_CA_BUNDLE=/opt/etc/ssl/certs/ca-certificates.crt
  fi
}

KOX_BYPASS_IPS_FILE="${KOX_BYPASS_IPS_FILE:-/opt/etc/xray/bypass-ips.txt}"
KOX_BYPASS_IPS_AUTO="${KOX_BYPASS_IPS_AUTO:-/opt/etc/xray/bypass-ips.auto}"
KOX_BYPASS_LAN_FILE="${KOX_BYPASS_LAN_FILE:-/opt/etc/xray/bypass-lan.txt}"
KOX_BYPASS_MARKER="192.0.2.254/32"

# Активен ли QUIC-блок (UDP/443 → DROP на LAN).
kox_quic_block_active() {
  iptables -t mangle -C PREROUTING -i br0 -j KOX_QUIC 2>/dev/null && return 0
  iptables -t mangle -C PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null && return 0
  ip6tables -t mangle -C PREROUTING -i br0 -j KOX_QUIC 2>/dev/null && return 0
  ip6tables -t mangle -C PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null && return 0
  return 1
}

# Отдельный UDP-вход 10810 (TPROXY). TCP 10808 не трогаем — иначе ноут зависает.
kox_xray_ensure_udp_inbound() {
  _conf="${1:-/opt/etc/xray/config.json}"
  [ -f "$_conf" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  _need=0
  jq -e '.inbounds[] | select(.tag=="kox-tproxy-udp" and .port==10810 and .streamSettings.sockopt.tproxy=="tproxy")' "$_conf" >/dev/null 2>&1 || _need=1
  jq -e '.routing.rules[] | select(.inboundTag != null and (.inboundTag | index("kox-tproxy-udp")) and .outboundTag=="kox-proxy")' "$_conf" >/dev/null 2>&1 || _need=1
  jq -e '.inbounds[] | select(.port==10808 or .tag=="kox-transparent") | .streamSettings.sockopt.tproxy' "$_conf" >/dev/null 2>&1 && _need=1
  [ "$_need" = "0" ] && return 0
  _tmp="${_conf}.udp.$$"
  jq '
    (.inbounds[] | select(.port==10808 or .tag=="kox-transparent")) |= (del(.streamSettings))
    | .inbounds |= (map(select(.tag != "kox-tproxy-udp")) + [{
        tag: "kox-tproxy-udp",
        listen: "0.0.0.0",
        port: 10810,
        protocol: "dokodemo-door",
        settings: {network: "udp", followRedirect: true},
        streamSettings: {sockopt: {tproxy: "tproxy"}},
        sniffing: {enabled: true, destOverride: ["quic"]}
      }])
    | .routing.rules |= (
        map(select(.inboundTag == null or (.inboundTag | index("kox-tproxy-udp") | not)))
        | . as $rules
        | (
            $rules
            | to_entries
            | map(select(.value.network=="udp" and (.value.port|not) and (.value.inboundTag|not)))
            | .[0].key
          ) as $i
        | if $i != null then
            $rules[:$i] + [{"type":"field","inboundTag":["kox-tproxy-udp"],"outboundTag":"kox-proxy"}] + $rules[$i:]
          else
            $rules + [{"type":"field","inboundTag":["kox-tproxy-udp"],"outboundTag":"kox-proxy"}]
          end
      )
  ' "$_conf" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
  jq -e . "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp"; return 1; }
  mv "$_tmp" "$_conf"
  return 2
}

kox_udp_tproxy_active() {
  iptables -t mangle -C PREROUTING -i br0 -j KOX_UDP 2>/dev/null || return 1
  iptables -t mangle -L KOX_UDP -n 2>/dev/null | grep -q TPROXY
}

# Игровые TCP-порты → kox-proxy. Только Supercell 9339.
# CODM лобби/матч по UDP должен идти напрямую (иначе таймаут, нет игроков).
KOX_GAME_TCP_PORTS="9339"
kox_xray_ensure_game_ports() {
  _conf="${1:-/opt/etc/xray/config.json}"
  [ -f "$_conf" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg p "$KOX_GAME_TCP_PORTS" \
    '.routing.rules[] | select((.port|tostring)==$p and .outboundTag=="kox-proxy")' \
    "$_conf" >/dev/null 2>&1 && return 0
  _tmp="${_conf}.game.$$"
  jq --arg p "$KOX_GAME_TCP_PORTS" '
    .routing.rules |= (
      map(select((.port|tostring) != "9339" and (.port|tostring) != $p
        and (.port|tostring) != "9339,65010,65050"))
      | . as $rules
      | (
          $rules
          | to_entries
          | map(select(.value.network=="tcp" and (.value.port|not) and (.value.inboundTag|not)))
          | .[0].key
        ) as $i
      | if $i != null then
          $rules[:$i] + [{"type":"field","network":"tcp","port":$p,"outboundTag":"kox-proxy"}] + $rules[$i:]
        else
          $rules + [{"type":"field","network":"tcp","port":$p,"outboundTag":"kox-proxy"}]
        end
    )
  ' "$_conf" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
  jq -e . "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp"; return 1; }
  mv "$_tmp" "$_conf"
  return 2
}

# Скачать и установить 99-kox-nat.sh (CDN / GitHub).
kox_install_nat_script() {
  _dest="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
  mkdir -p /opt/etc/ndm/netfilter.d
  if kox_fetch_repo_upgrade "99-kox-nat.sh" "$_dest" 12 && [ -s "$_dest" ]; then
    chmod +x "$_dest"
    return 0
  fi
  return 1
}

# Есть ли REDIRECT на 10808 в XRAY_REDIRECT (иначе WiFi-клиенты без VPN).
kox_nat_redirect_ok() {
  iptables -t nat -L XRAY_REDIRECT -n 2>/dev/null | grep -q 'redir ports 10808'
}

# switch-auto включён? (0 или >=999 = выкл)
kox_failover_enabled() {
  _fm="${1:-}"
  if [ -z "$_fm" ] && [ -f /opt/etc/xray/kox.conf ]; then
    # shellcheck disable=SC1091
    . /opt/etc/xray/kox.conf 2>/dev/null
    _fm="${KOX_FAILOVER_MINUTES:-10}"
  fi
  _fm="${_fm:-10}"
  case "$_fm" in
    0|off|OFF|disabled|DISABLED) return 1 ;;
  esac
  [ "$_fm" -ge 999 ] 2>/dev/null && return 1
  return 0
}

# Применить NAT + QUIC-блок (IPv4 и IPv6), с проверкой REDIRECT.
kox_apply_nat_rules() {
  _nat="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
  [ -f "$_nat" ] || return 1
  _xray_need=0
  if type kox_xray_ensure_udp_inbound >/dev/null 2>&1; then
    kox_xray_ensure_udp_inbound /opt/etc/xray/config.json
    [ "$?" = "2" ] && _xray_need=1
  fi
  if type kox_xray_ensure_game_ports >/dev/null 2>&1; then
    kox_xray_ensure_game_ports /opt/etc/xray/config.json
    [ "$?" = "2" ] && _xray_need=1
  fi
  if [ "$_xray_need" = "1" ]; then
    ulimit -n 65535 2>/dev/null || true
    /opt/etc/init.d/S24xray restart >/dev/null 2>&1 || true
    _w=0
    while [ "$_w" -lt 12 ]; do
      netstat -ln 2>/dev/null | grep -q ':10808 ' && break
      sleep 1
      _w=$((_w + 1))
    done
  fi
  _try=0
  while [ "$_try" -lt 3 ]; do
    sh "$_nat" 2>/dev/null || return 1
    sh "$_nat" ip6tables 2>/dev/null || true
    kox_nat_redirect_ok && return 0
    _try=$((_try + 1))
    sleep 1
  done
  return 1
}

# Снять NAT Xray + QUIC-блок (при падении Xray / kox off).
kox_iptables_remove_quic_block() {
  iptables  -t mangle -D PREROUTING -i br0 -j KOX_QUIC 2>/dev/null || true
  iptables  -t mangle -F KOX_QUIC 2>/dev/null || true
  iptables  -t mangle -X KOX_QUIC 2>/dev/null || true
  iptables  -t mangle -D PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null || true
  iptables  -t mangle -D PREROUTING -i br0 -j KOX_UDP 2>/dev/null || true
  iptables  -t mangle -D PREROUTING -i br0 -p udp -m socket -j KOX_DIVERT 2>/dev/null || true
  iptables  -t mangle -F KOX_UDP 2>/dev/null || true
  iptables  -t mangle -X KOX_UDP 2>/dev/null || true
  iptables  -t mangle -F KOX_DIVERT 2>/dev/null || true
  iptables  -t mangle -X KOX_DIVERT 2>/dev/null || true
  ip6tables -t mangle -D PREROUTING -i br0 -j KOX_QUIC 2>/dev/null || true
  ip6tables -t mangle -F KOX_QUIC 2>/dev/null || true
  ip6tables -t mangle -X KOX_QUIC 2>/dev/null || true
  ip6tables -t mangle -D PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null || true
  ip rule del fwmark 0x2c0c lookup 252 2>/dev/null || true
  ip route flush table 252 2>/dev/null || true
  ip -6 rule del fwmark 0x2c0c lookup 252 2>/dev/null || true
  ip -6 route flush table 252 2>/dev/null || true
}

kox_iptables_remove_xray_nat() {
  _lanf="/opt/etc/xray/bypass-lan.txt"
  if [ -f "$_lanf" ]; then
    while IFS= read -r _lan _rest; do
      case "$_lan" in ''|'#'*) continue ;; esac
      printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
      iptables  -t nat -D PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
      iptables  -t mangle -D PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
    done < "$_lanf"
  fi
  for _bf in /opt/etc/xray/bypass-ips.auto /opt/etc/xray/bypass-ips.txt; do
    [ -f "$_bf" ] || continue
    while IFS= read -r _ip _rest; do
      case "$_ip" in ''|'#'*) continue ;; esac
      _plain="${_ip%%/*}"
      printf '%s' "$_plain" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || continue
      iptables -t nat -D PREROUTING -i br0 -d "${_plain}/32" -p tcp -j RETURN 2>/dev/null || true
      iptables -t nat -D PREROUTING -i br0 -d "${_plain}/32" -p udp -j RETURN 2>/dev/null || true
    done < "$_bf"
  done
  iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p udp -j XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  kox_iptables_remove_quic_block
}

# Версия из установленного kox-cli (после upgrade бот подхватывает актуальную).
kox_read_cli_version() {
  _v=$(grep '^KOX_VERSION=' /opt/bin/kox 2>/dev/null | head -1 | sed 's/^KOX_VERSION=//; s/"//g')
  [ -n "$_v" ] && printf '%s' "$_v" && return 0
  return 1
}

# Поставить резервный сервер (KOX_BACKUP_HOST) первым в списке для switch-auto.
kox_prioritize_backup_server() {
  local BH FILE MATCH TMP
  BH="${KOX_BACKUP_HOST:-}"
  [ -z "$BH" ] && return 0
  FILE="${1:-/tmp/kox-auto-servers.txt}"
  [ ! -s "$FILE" ] && return 0
  MATCH=$(grep -F "@${BH}:" "$FILE" 2>/dev/null | head -1)
  [ -z "$MATCH" ] && MATCH=$(grep -F "$BH" "$FILE" 2>/dev/null | head -1)
  [ -z "$MATCH" ] && return 0
  TMP="${FILE}.reorder"
  grep -Fv "$MATCH" "$FILE" > "$TMP" 2>/dev/null || true
  printf '%s\n' "$MATCH" > "$FILE"
  cat "$TMP" >> "$FILE" 2>/dev/null || true
  rm -f "$TMP"
}

# BusyBox-safe подсчёт строк по паттерну (не grep -c).
kox_count_matches() {
  _src="$1"
  _pat="$2"
  _n=$(printf '%s\n' "$_src" | grep -E "$_pat" 2>/dev/null | wc -l | tr -d ' \n\r')
  case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
  printf '%d' "$_n"
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

# Версия → число для сравнения (2026.07.07.13 → 2026070713).
kox_version_to_int() {
  printf '%s' "$1" | tr -d ' \t\r\n.' | tr -cd '0-9'
}

# CHANGELOG.md: все секции ## между from_ver (не включая) и to_ver (включая).
kox_changelog_between() {
  _from="$1"
  _to="$2"
  _file="$3"
  _max="${4:-80}"
  [ -f "$_file" ] || return 1
  _from_i=$(kox_version_to_int "$_from")
  _to_i=$(kox_version_to_int "$_to")
  [ -z "$_from_i" ] || [ -z "$_to_i" ] && return 1
  awk -v from="$_from_i" -v to="$_to_i" -v max="$_max" '
    /^## [0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]+/ {
      ver = $2
      gsub(/\./, "", ver)
      show = (ver + 0 > from + 0 && ver + 0 <= to + 0)
      if (show) {
        if (sections++) print ""
        print $0
        lines = 1
      }
      in_blk = show
      next
    }
    in_blk {
      if (lines >= max) { truncated = 1; in_blk = 0; next }
      print
      lines++
    }
    END { if (truncated) print "... (ещё в CHANGELOG.md на GitHub)" }
  ' "$_file" 2>/dev/null
}

# BusyBox: grep -c при 0 совпадениях → exit 1; «grep -c || echo 0» даёт «0\n0» и ломает [ -eq ].
kox_count_lines() {
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
  _hconf="${2:-${HYSTERIA_CONF:-/opt/etc/hysteria/client.yaml}}"
  _hport="${3:-${HYSTERIA_SOCKS_PORT:-11888}}"
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
    _wan=$(kox_default_wan_dev)
    if [ -n "$_wan" ]; then
      printf 'quic:\n  sockopts:\n    bindInterface: %s\n' "$_wan"
    fi
  } > "$_hconf"
}

# IPv4 WAN (eth3 и т.п.). Без bindInterface hysteria садится на [::]
# и на Keenetic часто падает: sendto network is unreachable.
kox_default_wan_dev() {
  ip -4 route show default 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }
  }'
}

kox_hysteria_ensure_wan_bind() {
  _hconf="${1:-${HYSTERIA_CONF:-/opt/etc/hysteria/client.yaml}}"
  [ -f "$_hconf" ] || return 0
  grep -q 'bindInterface:' "$_hconf" 2>/dev/null && return 0
  _wan=$(kox_default_wan_dev)
  [ -n "$_wan" ] || return 0
  printf '\nquic:\n  sockopts:\n    bindInterface: %s\n' "$_wan" >> "$_hconf"
}

kox_hysteria_alive() {
  _port="${1:-${HYSTERIA_SOCKS_PORT:-11888}}"
  pgrep -f hysteria >/dev/null 2>&1 || return 1
  netstat -ln 2>/dev/null | grep -q ":${_port} "
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

# ── Bypass VPN server IPs (LAN clients with Happ/HY2/OpenVPN) ───────────────

kox_bypass_ip_normalize() {
  _ip="$1"
  case "$_ip" in
    */*) printf '%s' "$_ip" ;;
    *)   printf '%s/32' "$_ip" ;;
  esac
}

# Добавить IP в список обхода (если ещё нет), вывести на stdout.
kox_bypass_collect_add() {
  _raw="$1"
  _seen="$2"
  [ -z "$_raw" ] && return 0
  case "$_raw" in
    *:*|*[\|\&\;]*) return 0 ;;
  esac
  _plain="${_raw%%/*}"
  kox_validate_ip_cidr "$_raw" || return 0
  grep -qxF "$_plain" "$_seen" 2>/dev/null && return 0
  printf '%s\n' "$_plain" >> "$_seen"
  printf '%s\n' "$_plain"
}

# Все IP для обхода перехвата (уникальные, по одному на строку).
kox_bypass_ips_collect() {
  _seen="/tmp/kox-bypass-seen.$$"
  : > "$_seen"
  if [ -f /opt/etc/xray/kox.conf ]; then
    # shellcheck disable=SC1091
    . /opt/etc/xray/kox.conf 2>/dev/null
  fi
  kox_bypass_collect_add "${KOX_SERVER:-}" "$_seen"
  kox_bypass_collect_add "${KOX_BACKUP_HOST:-}" "$_seen"
  kox_bypass_collect_add "${KOX_PREFERRED_HOST:-}" "$_seen"
  kox_bypass_collect_add "${KOX_CDN_IP:-185.154.193.130}" "$_seen"
  case "${KOX_RELAY_HOST:-}" in
    *.*.*.*) kox_bypass_collect_add "${KOX_RELAY_HOST}" "$_seen" ;;
  esac
  for _f in "$KOX_BYPASS_IPS_AUTO" "$KOX_BYPASS_IPS_FILE"; do
    [ -f "$_f" ] || continue
    while IFS= read -r _line; do
      _line=$(printf '%s' "$_line" | sed 's/#.*//; s/^[ \t]*//; s/[ \t]*$//')
      [ -n "$_line" ] && kox_bypass_collect_add "$_line" "$_seen"
    done < "$_f"
  done
  for _cache in /tmp/kox-cli-servers.txt /tmp/kox-servers.txt; do
    [ -f "$_cache" ] || continue
    while IFS= read -r _line; do
      _h=$(printf '%s' "$_line" | cut -f2)
      kox_bypass_collect_add "$_h" "$_seen"
    done < "$_cache" 2>/dev/null
  done
  rm -f "$_seen"
}

# Обновить bypass-ips.auto из кэша подписки + kox.conf.
kox_bypass_ips_sync_auto() {
  _tmp="/tmp/kox-bypass-auto.$$"
  kox_bypass_ips_collect > "$_tmp" 2>/dev/null || : > "$_tmp"
  mkdir -p "$(dirname "$KOX_BYPASS_IPS_AUTO")"
  if [ -f "$KOX_BYPASS_IPS_FILE" ]; then
    while IFS= read -r _u; do
      _u=$(printf '%s' "$_u" | sed 's/#.*//; s/^[ \t]*//; s/[ \t]*$//')
      [ -n "$_u" ] && grep -qxF "${_u%%/*}" "$_tmp" 2>/dev/null || \
        printf '%s\n' "${_u%%/*}" >> "$_tmp"
    done < "$KOX_BYPASS_IPS_FILE"
  fi
  sort -u "$_tmp" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' > "$KOX_BYPASS_IPS_AUTO" 2>/dev/null || \
    mv "$_tmp" "$KOX_BYPASS_IPS_AUTO"
  rm -f "$_tmp"
}

# Правило routing direct по IP (маркер 192.0.2.254/32).
kox_sync_bypass_routing() {
  _conf="${1:-/opt/etc/xray/config.json}"
  _marker="$KOX_BYPASS_MARKER"
  [ -f "$_conf" ] || return 1
  command -v jq >/dev/null 2>&1 || return 0
  _iplist=$(kox_bypass_ips_collect | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u | \
    jq -R -s 'split("\n") | map(select(length>0)) | map(. + "/32")' 2>/dev/null) || return 1
  _tmp="/tmp/kox-bypass-route.$$"
  jq --arg marker "$_marker" --argjson bypass "$_iplist" '
    ($bypass + [$marker]) as $all |
    if (.routing.rules | map(select((.ip // []) | index($marker))) | length) > 0 then
      .routing.rules = [.routing.rules[] |
        if ((.ip // []) | index($marker)) then .ip = $all else . end]
    else
      .routing.rules = [.routing.rules[0],
        {"type":"field","ip":$all,"outboundTag":"direct"}] + .routing.rules[1:]
    end
  ' "$_conf" > "$_tmp" 2>/dev/null || return 1
  [ -s "$_tmp" ] || return 1
  mv "$_tmp" "$_conf"
  return 0
}

kox_bypass_refresh() {
  kox_bypass_ips_sync_auto
  kox_sync_bypass_routing "${2:-/opt/etc/xray/config.json}" 2>/dev/null || true
  if [ "${1:-}" != "no-reload" ] && type kox_reload_config >/dev/null 2>&1; then
    kox_reload_config 2>/dev/null || true
  fi
  if [ ! -f /tmp/kox-vpn-off ] && pgrep xray >/dev/null 2>&1; then
    kox_apply_nat_rules 2>/dev/null || \
      sh /opt/etc/ndm/netfilter.d/99-kox-nat.sh 2>/dev/null || true
  fi
}

kox_bypass_ip_add() {
  _ip="$1"
  [ -z "$_ip" ] && return 1
  kox_validate_ip_cidr "$_ip" || return 1
  _plain="${_ip%%/*}"
  mkdir -p "$(dirname "$KOX_BYPASS_IPS_FILE")"
  touch "$KOX_BYPASS_IPS_FILE"
  grep -qxF "$_plain" "$KOX_BYPASS_IPS_FILE" 2>/dev/null && return 0
  printf '%s\n' "$_plain" >> "$KOX_BYPASS_IPS_FILE"
  kox_bypass_refresh
  return 0
}

kox_bypass_lan_add() {
  _ip="$1"
  [ -z "$_ip" ] && return 1
  printf '%s' "$_ip" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || return 1
  mkdir -p "$(dirname "$KOX_BYPASS_LAN_FILE")"
  touch "$KOX_BYPASS_LAN_FILE"
  grep -qxF "$_ip" "$KOX_BYPASS_LAN_FILE" 2>/dev/null && return 0
  printf '%s\n' "$_ip" >> "$KOX_BYPASS_LAN_FILE"
  kox_bypass_flush_lan_conntrack "$_ip"
  kox_bypass_refresh no-reload
  return 0
}

# Сбросить NAT-сессии LAN-клиента (старые TCP через Xray 10808).
kox_bypass_flush_lan_conntrack() {
  _ip="$1"
  [ -z "$_ip" ] && return 0
  if command -v conntrack >/dev/null 2>&1; then
    conntrack -D -s "$_ip" 2>/dev/null || true
  fi
}

kox_bypass_lan_del() {
  _ip="$1"
  [ -z "$_ip" ] && return 1
  [ -f "$KOX_BYPASS_LAN_FILE" ] || return 0
  grep -vxF "$_ip" "$KOX_BYPASS_LAN_FILE" > /tmp/kox-bypass-lan.$$ 2>/dev/null && \
    mv /tmp/kox-bypass-lan.$$ "$KOX_BYPASS_LAN_FILE"
  kox_bypass_refresh no-reload
  return 0
}

kox_bypass_ip_del() {
  _ip="$1"
  [ -z "$_ip" ] && return 1
  _plain="${_ip%%/*}"
  [ -f "$KOX_BYPASS_IPS_FILE" ] || return 0
  grep -vxF "$_plain" "$KOX_BYPASS_IPS_FILE" > /tmp/kox-bypass-del.$$ 2>/dev/null && \
    mv /tmp/kox-bypass-del.$$ "$KOX_BYPASS_IPS_FILE"
  kox_bypass_refresh
  return 0
}
