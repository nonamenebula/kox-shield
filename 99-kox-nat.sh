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

# Пропустить приватные IP
for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
            172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$CIDR" -j RETURN 2>/dev/null || true
done

# Перенаправить только HTTP/HTTPS — только эти порты используют VPN
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 80  -j REDIRECT --to-ports 10808 2>/dev/null || true
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 443 -j REDIRECT --to-ports 10808 2>/dev/null || true

# YouTube/Google QUIC (UDP/443) → DROP на LAN, браузер переключается на TCP
$IPTS -t mangle -D PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null || true
$IPTS -t mangle -A PREROUTING -i br0 -p udp --dport 443 -j DROP 2>/dev/null || true

# Применить к трафику LAN
$IPTS -t nat -A PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true

# Проверка: без REDIRECT прозрачный VPN для WiFi не работает
$IPTS -t nat -L XRAY_REDIRECT -n 2>/dev/null | grep -q 'redir ports 10808' || exit 1
