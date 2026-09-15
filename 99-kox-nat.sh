#!/bin/sh
# KOX Shield — iptables NAT + QUIC block (Keenetic netfilter.d)
PATH=/opt/sbin:/opt/bin:/sbin:/usr/sbin:/usr/bin:/bin
export PATH

[ "$1" = "ip6tables" ] && IPTS=ip6tables || IPTS=iptables

# Не применять если пользователь вручную выключил VPN
[ -f /tmp/kox-vpn-off ] && exit 0

# Не применять если Xray не запущен — иначе весь трафик уйдёт в никуда
pgrep xray >/dev/null 2>&1 || exit 0

# Полная пересборка цепочки (избегаем «пустой» XRAY_REDIRECT без REDIRECT после -F)
$IPTS -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -F XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -X XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -N XRAY_REDIRECT 2>/dev/null || exit 1

# LAN-устройства целиком без перехвата (корп. VPN + RDP на Windows)
for _lanf in /opt/etc/xray/bypass-lan.txt; do
  [ -f "$_lanf" ] || continue
  while IFS= read -r _lan _rest; do
    case "$_lan" in ''|'#'*) continue ;; esac
    printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
    $IPTS -t nat -A XRAY_REDIRECT -s "$_lan" -j RETURN 2>/dev/null || true
  done < "$_lanf"
done

# Пропустить приватные IP
for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
            172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$CIDR" -j RETURN 2>/dev/null || true
done

# VPN-серверы (Happ/HY2 на LAN): не перехватывать — иначе клиент не поднимет туннель
_kox_bypass_merge() {
  _out="/tmp/kox-bypass-nat.$$"
  : > "$_out"
  for _bf in /opt/etc/xray/bypass-ips.auto /opt/etc/xray/bypass-ips.txt; do
    [ -f "$_bf" ] || continue
    while IFS= read -r _ip _rest; do
      case "$_ip" in ''|'#'*) continue ;; esac
      _plain="${_ip%%/*}"
      printf '%s' "$_plain" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || continue
      grep -qxF "$_plain" "$_out" 2>/dev/null || printf '%s\n' "$_plain" >> "$_out"
    done < "$_bf"
  done
  while IFS= read -r _ip; do
    [ -n "$_ip" ] || continue
    $IPTS -t nat -A XRAY_REDIRECT -d "${_ip}/32" -j RETURN 2>/dev/null || true
  done < "$_out"
  rm -f "$_out"
}
_kox_bypass_merge

# HTTP/HTTPS + игры: Supercell 9339, CODM лобби 65010 / чат 65050
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 80  -j REDIRECT --to-ports 10808 2>/dev/null || true
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 443 -j REDIRECT --to-ports 10808 2>/dev/null || true
for _gp in 9339 65010 65050; do
  $IPTS -t nat -A XRAY_REDIRECT -p tcp --dport "$_gp" -j REDIRECT --to-ports 10808 2>/dev/null || true
done
# Свои IP Supercell (на случай другого порта)
$IPTS -t nat -A XRAY_REDIRECT -d 5.180.72.0/22 -p tcp -j REDIRECT --to-ports 10808 2>/dev/null || true
# Telegram DC — клиент/звонки на нестандартных TCP-портах
for _tg in 149.154.160.0/20 91.108.4.0/22 91.108.8.0/22 91.108.12.0/22 \
           91.108.16.0/22 91.108.20.0/22 91.108.56.0/22 95.161.64.0/20 \
           185.76.151.0/24; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$_tg" -p tcp -j REDIRECT --to-ports 10808 2>/dev/null || true
done

# YouTube/Google QUIC (UDP/443) → DROP на LAN; VPN-серверы — исключение (HY2/QUIC)
$IPTS -t mangle -D PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null || true
$IPTS -t mangle -D PREROUTING -i br0 -j KOX_QUIC 2>/dev/null || true
$IPTS -t mangle -F KOX_QUIC 2>/dev/null || true
$IPTS -t mangle -X KOX_QUIC 2>/dev/null || true
$IPTS -t mangle -N KOX_QUIC 2>/dev/null || true
for _lanf in /opt/etc/xray/bypass-lan.txt; do
  [ -f "$_lanf" ] || continue
  while IFS= read -r _lan _rest; do
    case "$_lan" in ''|'#'*) continue ;; esac
    printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
    $IPTS -t mangle -A KOX_QUIC -s "$_lan" -j RETURN 2>/dev/null || true
  done < "$_lanf"
done
_kox_bypass_quic() {
  _out="/tmp/kox-bypass-quic.$$"
  : > "$_out"
  for _bf in /opt/etc/xray/bypass-ips.auto /opt/etc/xray/bypass-ips.txt; do
    [ -f "$_bf" ] || continue
    while IFS= read -r _ip _rest; do
      case "$_ip" in ''|'#'*) continue ;; esac
      _plain="${_ip%%/*}"
      printf '%s' "$_plain" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || continue
      grep -qxF "$_plain" "$_out" 2>/dev/null || printf '%s\n' "$_plain" >> "$_out"
    done < "$_bf"
  done
  while IFS= read -r _ip; do
    [ -n "$_ip" ] || continue
    $IPTS -t mangle -A KOX_QUIC -d "${_ip}/32" -p udp --dport 443 -j RETURN 2>/dev/null || true
  done < "$_out"
  rm -f "$_out"
}
_kox_bypass_quic
$IPTS -t mangle -A KOX_QUIC -p udp --dport 443 -j DROP 2>/dev/null || true

# IPv4 UDP (звонки/игры) → TPROXY 10810. TCP и UDP/443 не трогаем.
_KOX_UDP_OK=0
$IPTS -t mangle -D PREROUTING -i br0 -j KOX_UDP 2>/dev/null || true
$IPTS -t mangle -D PREROUTING -i br0 -p udp -m socket -j KOX_DIVERT 2>/dev/null || true
$IPTS -t mangle -F KOX_UDP 2>/dev/null || true
$IPTS -t mangle -X KOX_UDP 2>/dev/null || true
$IPTS -t mangle -F KOX_DIVERT 2>/dev/null || true
$IPTS -t mangle -X KOX_DIVERT 2>/dev/null || true
if [ "$IPTS" = "iptables" ]; then
  _kox_load_tproxy() {
    for _m in xt_TPROXY xt_socket xt_mark; do
      lsmod 2>/dev/null | grep -q "^${_m}" && continue
      for _d in "/lib/modules/$(uname -r)" /lib/modules/4.9-ndm-5 /lib/modules/4.9-ndm-4 /lib/modules/*; do
        [ -f "${_d}/${_m}.ko" ] || continue
        insmod "${_d}/${_m}.ko" 2>/dev/null && break
      done
    done
    lsmod 2>/dev/null | grep -q '^xt_TPROXY'
  }
  if _kox_load_tproxy && netstat -ln 2>/dev/null | grep -q ':10810 '; then
    ip rule del fwmark 0x2c0c lookup 252 2>/dev/null || true
    ip route flush table 252 2>/dev/null || true
    ip rule add fwmark 0x2c0c lookup 252 2>/dev/null || true
    ip route add local 0.0.0.0/0 dev lo table 252 2>/dev/null || true
    $IPTS -t mangle -N KOX_UDP 2>/dev/null || true
    $IPTS -t mangle -F KOX_UDP 2>/dev/null || true
    for _lanf in /opt/etc/xray/bypass-lan.txt; do
      [ -f "$_lanf" ] || continue
      while IFS= read -r _lan _rest; do
        case "$_lan" in ''|'#'*) continue ;; esac
        printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
        $IPTS -t mangle -A KOX_UDP -s "$_lan" -j RETURN 2>/dev/null || true
      done < "$_lanf"
    done
    for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
                172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
                198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
      $IPTS -t mangle -A KOX_UDP -d "$CIDR" -j RETURN 2>/dev/null || true
    done
    _udpb="/tmp/kox-bypass-udp.$$"
    : > "$_udpb"
    for _bf in /opt/etc/xray/bypass-ips.auto /opt/etc/xray/bypass-ips.txt; do
      [ -f "$_bf" ] || continue
      while IFS= read -r _ip _rest; do
        case "$_ip" in ''|'#'*) continue ;; esac
        _plain="${_ip%%/*}"
        printf '%s' "$_plain" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || continue
        grep -qxF "$_plain" "$_udpb" 2>/dev/null || printf '%s\n' "$_plain" >> "$_udpb"
      done < "$_bf"
    done
    while IFS= read -r _ip; do
      [ -n "$_ip" ] || continue
      $IPTS -t mangle -A KOX_UDP -d "${_ip}/32" -j RETURN 2>/dev/null || true
    done < "$_udpb"
    rm -f "$_udpb"
    for _p in 53 67 68 123 443 1900 5353; do
      $IPTS -t mangle -A KOX_UDP -p udp --dport "$_p" -j RETURN 2>/dev/null || true
    done
    if $IPTS -t mangle -A KOX_UDP -p udp -j TPROXY --on-port 10810 --tproxy-mark 0x2c0c 2>/dev/null; then
      _KOX_UDP_OK=1
      if $IPTS -t mangle -N KOX_DIVERT 2>/dev/null || $IPTS -t mangle -F KOX_DIVERT 2>/dev/null; then
        $IPTS -t mangle -F KOX_DIVERT 2>/dev/null || true
        $IPTS -t mangle -A KOX_DIVERT -j MARK --set-mark 0x2c0c 2>/dev/null || true
        $IPTS -t mangle -A KOX_DIVERT -j ACCEPT 2>/dev/null || true
      fi
    else
      $IPTS -t mangle -F KOX_UDP 2>/dev/null || true
      $IPTS -t mangle -X KOX_UDP 2>/dev/null || true
      ip rule del fwmark 0x2c0c lookup 252 2>/dev/null || true
      ip route flush table 252 2>/dev/null || true
    fi
  fi
fi

# LAN + IP VPN-серверов: обход в PREROUTING до jump (SSTP TCP/443)
_kox_bypass_lan_prerouting() {
  [ "$IPTS" = "ip6tables" ] && return 0
  for _lanf in /opt/etc/xray/bypass-lan.txt; do
    [ -f "$_lanf" ] || continue
    while IFS= read -r _lan _rest; do
      case "$_lan" in ''|'#'*) continue ;; esac
      printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
      $IPTS -t nat -D PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
      $IPTS -t mangle -D PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
    done < "$_lanf"
  done
  _bp="/tmp/kox-bypass-prerouting.$$"
  : > "$_bp"
  for _bf in /opt/etc/xray/bypass-ips.auto /opt/etc/xray/bypass-ips.txt; do
    [ -f "$_bf" ] || continue
    while IFS= read -r _ip _rest; do
      case "$_ip" in ''|'#'*) continue ;; esac
      _plain="${_ip%%/*}"
      printf '%s' "$_plain" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || continue
      grep -qxF "$_plain" "$_bp" 2>/dev/null || printf '%s\n' "$_plain" >> "$_bp"
      $IPTS -t nat -D PREROUTING -i br0 -d "$_plain/32" -p tcp -j RETURN 2>/dev/null || true
    done < "$_bf"
  done
  $IPTS -t mangle -D PREROUTING -i br0 -j KOX_QUIC 2>/dev/null || true
  $IPTS -t mangle -D PREROUTING -i br0 -j KOX_UDP 2>/dev/null || true
  $IPTS -t mangle -D PREROUTING -i br0 -p udp -m socket -j KOX_DIVERT 2>/dev/null || true
  $IPTS -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  for _lanf in /opt/etc/xray/bypass-lan.txt; do
    [ -f "$_lanf" ] || continue
    while IFS= read -r _lan _rest; do
      case "$_lan" in ''|'#'*) continue ;; esac
      printf '%s' "$_lan" | grep -qE '^192\.168\.[0-9]+\.[0-9]+$' || continue
      $IPTS -t nat -A PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
      $IPTS -t mangle -A PREROUTING -i br0 -s "$_lan" -j RETURN 2>/dev/null || true
    done < "$_lanf"
  done
  while IFS= read -r _plain; do
    [ -n "$_plain" ] || continue
    $IPTS -t nat -A PREROUTING -i br0 -d "${_plain}/32" -p tcp -j RETURN 2>/dev/null || true
  done < "$_bp"
  rm -f "$_bp"
  $IPTS -t mangle -A PREROUTING -i br0 -j KOX_QUIC 2>/dev/null || true
  if [ "$_KOX_UDP_OK" = "1" ]; then
    $IPTS -t mangle -C PREROUTING -i br0 -p udp -m socket -j KOX_DIVERT 2>/dev/null \
      || $IPTS -t mangle -A PREROUTING -i br0 -p udp -m socket -j KOX_DIVERT 2>/dev/null || true
    $IPTS -t mangle -A PREROUTING -i br0 -j KOX_UDP 2>/dev/null || true
  fi
  $IPTS -t nat -A PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
}
_kox_bypass_lan_prerouting

# Проверка: без REDIRECT прозрачный VPN для WiFi не работает
$IPTS -t nat -L XRAY_REDIRECT -n 2>/dev/null | grep -q 'redir ports 10808' || exit 1
