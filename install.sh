#!/bin/sh
# ╔══════════════════════════════════════════════════════════════════╗
# ║   KOX Shield — Installer for Keenetic Router (Entware)            ║
# ║   https://kox.nonamenebula.ru | t.me/PrivateProxyKox           ║
# ╚══════════════════════════════════════════════════════════════════╝
#
# Запуск на роутере одной командой:
#   wget -O /tmp/kox-install.sh https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh && sh /tmp/kox-install.sh
#
# Требования:
#   • Keenetic с установленным Entware (/opt)
#   • Доступ к интернету с роутера
#   • VLESS-подписка (URL вида https://...)

set -e

GITHUB_RAW="https://raw.githubusercontent.com/nonamenebula/kox-shield/main"
OPT="/opt"
XRAY_CONF="/opt/etc/xray"
BIN="/opt/bin"
INIT="/opt/etc/init.d"

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[0;33m'
C='\033[0;36m'; W='\033[1;37m'; N='\033[0m'

ok()   { printf " ${G}✓${N}  %s\n" "$*"; }
fail() { printf " ${R}✗${N}  %s\n" "$*" >&2; exit 1; }
info() { printf " ${C}•${N}  %s\n" "$*"; }
warn() { printf " ${Y}!${N}  %s\n" "$*"; }
sep()  { printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"; }
ask()  { printf " ${W}?${N}  %s " "$*"; }

read_tty() {
  # The installer is usually started as `wget -qO- ... | sh`, so stdin is the
  # script pipe, not the user's keyboard. Read interactive answers from TTY.
  if [ -r /dev/tty ]; then
    IFS= read -r "$1" </dev/tty
  else
    IFS= read -r "$1"
  fi
}

banner() {
  printf "\n"
  printf "${W}  ██╗  ██╗  ██████╗  ██╗  ██╗${N}\n"
  printf "${W}  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝${N}\n"
  printf "${W}  █████╔╝   ██║  ██║  ╚███╔╝ ${N}\n"
  printf "${W}  ██╔═██╗   ██║  ██║  ██╔██╗ ${N}\n"
  printf "${W}  ██║  ██╗  ╚██████╔╝██╔╝ ██╗${N}\n"
  printf "${W}  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝${N}\n"
  printf "\n"
  printf "${C}        ── VPN Installer for Keenetic ──${N}\n"
  printf "\n"
  printf "  ${C}🌐 kox.nonamenebula.ru/register${N}\n"
  printf "  ${C}📢 t.me/PrivateProxyKox${N}\n"
  printf "  ${C}🤖 @kox_nonamenebula_bot${N}\n"
  sep
  printf "\n"
}

# ── Проверки ──────────────────────────────────────────────────────────────────
check_entware() {
  if [ ! -f /opt/bin/opkg ]; then
    fail "Entware не установлен! Установите Entware через веб-интерфейс Keenetic."
  fi
  ok "Entware найден"
}

# CA bundle + curl до загрузки подписки (иначе HTTPS падает, а ping проходит).
ensure_https_tools() {
  info "Проверяю HTTPS (curl, ca-certificates)..."
  /opt/bin/opkg update >/dev/null 2>&1 || warn "opkg update завершился с ошибкой"

  if ! command -v curl >/dev/null 2>&1 && [ ! -x /opt/bin/curl ]; then
    info "Устанавливаю curl..."
    /opt/bin/opkg install curl >/dev/null 2>&1 || warn "Не удалось установить curl"
  fi

  if ! /opt/bin/opkg list-installed 2>/dev/null | grep -q '^ca-certificates '; then
    info "Устанавливаю ca-certificates..."
    /opt/bin/opkg install ca-certificates >/dev/null 2>&1 || warn "Не удалось установить ca-certificates"
  fi

  if [ -f /opt/etc/ssl/certs/ca-certificates.crt ]; then
    export SSL_CERT_FILE=/opt/etc/ssl/certs/ca-certificates.crt
    export CURL_CA_BUNDLE=/opt/etc/ssl/certs/ca-certificates.crt
  elif [ -f /etc/ssl/certs/ca-certificates.crt ]; then
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
  fi

  _curl=""
  if [ -x /opt/bin/curl ]; then _curl=/opt/bin/curl
  elif command -v curl >/dev/null 2>&1; then _curl=curl
  fi

  if [ -n "$_curl" ] && "$_curl" -fsSL -4 --max-time 12 https://kox.nonamenebula.ru/healthz -o /dev/null 2>/dev/null; then
    ok "HTTPS работает"
    return 0
  fi
  if [ -n "$_curl" ] && "$_curl" -fsSL --max-time 12 https://github.com -o /dev/null 2>/dev/null; then
    ok "HTTPS работает (github.com)"
    return 0
  fi
  warn "HTTPS не проверен — при ошибке загрузки: opkg install ca-certificates curl"
}

# Загрузка URL: IPv4, CA bundle, повторы, wget fallback.
kox_curl_fetch() {
  _url="$1"
  _curl=""
  if [ -x /opt/bin/curl ]; then _curl=/opt/bin/curl
  elif command -v curl >/dev/null 2>&1; then _curl=curl
  fi
  _ca="${CURL_CA_BUNDLE:-}"
  [ -z "$_ca" ] && [ -f /opt/etc/ssl/certs/ca-certificates.crt ] && _ca=/opt/etc/ssl/certs/ca-certificates.crt

  _try_curl() {
    _c="$1"
    shift
    _body=$("$_c" "$@" 2>/dev/null) || return 1
    [ -n "$_body" ] || return 1
    printf '%s' "$_body"
    return 0
  }

  if [ -n "$_curl" ]; then
    if [ -n "$_ca" ]; then
      _try_curl "$_curl" -fsSL -4 --max-time 25 --cacert "$_ca" "$_url" && return 0
    fi
    _try_curl "$_curl" -fsSL -4 --max-time 25 "$_url" && return 0
    _try_curl "$_curl" -fsSL --max-time 25 "$_url" && return 0
    if [ -n "$_ca" ]; then
      _try_curl "$_curl" -sSL -4 --max-time 25 --cacert "$_ca" "$_url" && return 0
    fi
  fi

  if [ -x /opt/bin/wget ]; then
    _wbody=$(/opt/bin/wget -qO- -4 -T 25 "$_url" 2>/dev/null) && [ -n "$_wbody" ] && {
      printf '%s' "$_wbody"
      return 0
    }
  fi
  return 1
}

check_internet() {
  if kox_curl_fetch "https://github.com" >/dev/null 2>&1; then
    ok "Интернет доступен (HTTPS)"
  elif curl -fsSL --max-time 10 --silent https://github.com -o /dev/null 2>/dev/null; then
    ok "Интернет доступен"
  elif ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    ok "Интернет доступен (ping)"
    warn "HTTPS не отвечает — установлю ca-certificates и curl"
    ensure_https_tools
  else
    fail "Нет доступа к интернету с роутера"
  fi
}

# ── Парсинг VLESS URL ──────────────────────────────────────────────────────────
parse_vless_url() {
  VLESS_URL="$1"
  # vless://UUID@HOST:PORT?params#name
  BODY=${VLESS_URL#vless://}
  VLESS_UUID=${BODY%%@*}
  HOSTPORT=${BODY#*@}; HOSTPORT=${HOSTPORT%%\?*}
  VLESS_HOST=${HOSTPORT%%:*}; VLESS_PORT=${HOSTPORT##*:}
  PARAMS=${BODY#*\?}; PARAMS=${PARAMS%%#*}

  get_param() { printf '%s' "$PARAMS" | tr '&' '\n' | grep "^$1=" | cut -d= -f2- | head -1; }
  VLESS_PBK=$(get_param pbk)
  VLESS_SID=$(get_param sid)
  VLESS_SNI=$(get_param sni)
  VLESS_FP=$(get_param fp); [ -z "$VLESS_FP" ] && VLESS_FP="chrome"
  VLESS_FLOW=$(get_param flow); [ -z "$VLESS_FLOW" ] && VLESS_FLOW="xtls-rprx-vision"

  { [ -z "$VLESS_UUID" ] || [ -z "$VLESS_HOST" ]; } && fail "Не удалось разобрать VLESS URL" || true
}

# URL-decode (%XX → байты UTF-8, + → пробел). Работает в busybox sh.
url_decode() {
  # ВАЖНО: сначала экранируем символ % → \x, затем printf '%b' интерпретирует \x
  printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

parse_subscription() {
  SUB_URL="$1"
  _ensure_kox_lib_early

  _norm=$(kox_normalize_sub_url "$SUB_URL" 2>/dev/null || printf '%s' "$SUB_URL")
  if [ "$_norm" != "$SUB_URL" ]; then
    warn "Ссылка личного кабинета (/u/) → подписка (/c/)"
    SUB_URL="$_norm"
  fi

  info "Загружаю подписку: $SUB_URL"
  _fetched=$(kox_curl_fetch "$SUB_URL") || _fetched=""
  if [ -z "$_fetched" ]; then
    ensure_https_tools
    _fetched=$(kox_curl_fetch "$SUB_URL") || _fetched=""
  fi
  if [ -z "$_fetched" ]; then
    fail "Не удалось загрузить подписку по HTTPS.
  На роутере выполните:
    opkg update && opkg install ca-certificates curl wget-ssl
  Проверка:
    curl -4 -v \"$SUB_URL\""
  fi

  if kox_is_html_payload "$_fetched" 2>/dev/null; then
    fail "Получена HTML-страница, а не подписка. Нужна ссылка …/c/TOKEN из раздела «Подписка»"
  fi

  if type kox_decode_subscription_body >/dev/null 2>&1; then
    RAW=$(kox_decode_subscription_body "$_fetched")
  else
    RAW=$(printf '%s' "$_fetched" | base64 -d 2>/dev/null || printf '%s' "$_fetched")
  fi
  [ -z "$RAW" ] && fail "Не удалось декодировать подписку"

  if kox_is_html_payload "$RAW" 2>/dev/null; then
    fail "Это не подписка VPN. Скопируйте ссылку /c/... (не /u/...)"
  fi

  if type kox_count_lines >/dev/null 2>&1; then
    _vless_n=$(kox_count_lines "$RAW" '^vless://')
    _hy2_n=$(kox_count_lines "$RAW" '^(hysteria2|hy2)://')
    COUNT=$(kox_count_lines "$RAW" '^(vless|hysteria2|hy2)://')
  else
    COUNT=$(printf '%s\n' "$RAW" | grep -E '^(vless|hysteria2|hy2)://' 2>/dev/null | wc -l | tr -d ' \n\r')
    _vless_n=$(printf '%s\n' "$RAW" | grep -E '^vless://' 2>/dev/null | wc -l | tr -d ' \n\r')
    _hy2_n=$(printf '%s\n' "$RAW" | grep -E '^(hysteria2|hy2)://' 2>/dev/null | wc -l | tr -d ' \n\r')
  fi
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac
  case "$_vless_n" in ''|*[!0-9]*) _vless_n=0 ;; esac
  case "$_hy2_n" in ''|*[!0-9]*) _hy2_n=0 ;; esac

  if [ "$COUNT" -eq 0 ]; then
    fail "Серверы (vless/hysteria2) не найдены в подписке"
  fi

  if [ "$_vless_n" -gt 0 ] && [ "$_hy2_n" -gt 0 ]; then
    info "Подписка: ${_hy2_n} Hysteria2, ${_vless_n} VLESS — выберите протокол"
  fi

  if [ "$COUNT" -eq 1 ]; then
    SELECTED_URI=$(printf '%s' "$RAW" | grep -E '^(vless|hysteria2|hy2)://' | head -1)
    _apply_selected_uri "$SELECTED_URI"
    return
  fi

  TMPLIST="/tmp/.kox-sublist.$$"
  if type kox_build_sub_server_list >/dev/null 2>&1; then
    kox_build_sub_server_list "$RAW" "$TMPLIST"
  else
    printf '%s\n' "$RAW" | grep -E '^(vless|hysteria2|hy2)://' > "$TMPLIST" 2>/dev/null
  fi
  COUNT=$(wc -l < "$TMPLIST" | tr -d ' \n\r')
  case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

  printf "\n"
  info "${W}Доступно серверов: ${COUNT}${N}"
  sep
  i=1
  while IFS= read -r line; do
    HOST=$(printf '%s' "$line" | sed 's|^[a-z0-9]*://[^@]*@\([^:?#]*\).*|\1|')
    PROTO=$(printf '%s' "$line" | grep -qE '^hysteria2://|^hy2://' && printf 'HY2' || printf 'VLESS')
    case "$line" in
      *\#*) NAME_RAW=${line##*\#} ;;
      *)    NAME_RAW="" ;;
    esac
    if [ -n "$NAME_RAW" ]; then
      NAME=$(url_decode "$NAME_RAW" 2>/dev/null || printf '%s' "$NAME_RAW")
      [ -z "$NAME" ] && NAME="—"
    else
      NAME="—"
    fi
    printf "  ${W}%d${N}) [${PROTO}] %s  ${C}%s${N}\n" "$i" "$HOST" "$NAME"
    i=$((i+1))
  done < "$TMPLIST"
  sep
  printf "\n"
  ask "Выберите сервер [1-${COUNT}], Enter = 1:"
  read_tty CHOICE
  [ -z "$CHOICE" ] && CHOICE=1

  SELECTED_URI=$(sed -n "${CHOICE}p" "$TMPLIST")
  rm -f "$TMPLIST"
  [ -z "$SELECTED_URI" ] && fail "Неверный выбор: $CHOICE"
  _apply_selected_uri "$SELECTED_URI"
}

_ensure_kox_lib_early() {
  if type uri_host >/dev/null 2>&1; then
    return 0
  fi

  _try_lib() {
    _f="$1"
    [ -f "$_f" ] || return 1
    # shellcheck disable=SC1090
    . "$_f" 2>/dev/null
    type uri_host >/dev/null 2>&1
  }

  if _try_lib /opt/etc/kox-lib.sh; then return 0; fi
  if _try_lib /tmp/kox-lib-cache.sh; then return 0; fi
  if [ -n "$0" ] && [ "$0" != "sh" ] && _try_lib "$(dirname "$0")/kox-lib.sh"; then return 0; fi

  mkdir -p /opt/etc 2>/dev/null || true
  if curl -fsSL --max-time 20 "${GITHUB_RAW}/kox-lib.sh" -o /tmp/kox-lib-cache.sh 2>/dev/null \
    && _try_lib /tmp/kox-lib-cache.sh; then
    cp /tmp/kox-lib-cache.sh /opt/etc/kox-lib.sh 2>/dev/null || true
    return 0
  fi
  if curl -fsSL --max-time 20 "${GITHUB_RAW}/kox-lib.sh" -o /opt/etc/kox-lib.sh 2>/dev/null \
    && _try_lib /opt/etc/kox-lib.sh; then
    return 0
  fi

  # Минимальные парсеры URI — если GitHub недоступен до install_packages
  uri_host()  { printf '%s' "$1" | sed 's|^[a-z0-9]*://[^@]*@\([^:/?#]*\).*|\1|'; }
  uri_port()  { printf '%s' "$1" | sed -n 's|^[a-z0-9]*://[^@]*@[^:/?#]*:\([0-9]*\).*|\1|p'; }
  uri_userinfo() { printf '%s' "$1" | sed 's|^[a-z0-9]*://\([^@]*\)@.*|\1|'; }
  uri_qparam() {
    _p="$2"
    printf '%s' "$1" | sed 's/^[^?]*?//; s/#.*//' | tr '&' '\n' | grep "^${_p}=" | head -1 | cut -d= -f2-
  }
  uri_is_hy() { case "$1" in hysteria2://*|hy2://*) return 0 ;; *) return 1 ;; esac; }

  kox_normalize_sub_url() {
    _url="$1"
    case "$_url" in
      */u/*)
        _base=${_url%%/u/*}
        _token=${_url#*/u/}; _token=${_token%%/*}; _token=${_token%%\?*}; _token=${_token%%#*}
        [ -n "$_base" ] && [ -n "$_token" ] && { printf '%s/c/%s' "$_base" "$_token"; return 0; }
        ;;
    esac
    printf '%s' "$_url"
  }

  kox_is_html_payload() {
    case "$1" in *'<!DOCTYPE'*|*'<!doctype'*|*'<html'*|*'<HTML'*) return 0 ;; esac
    return 1
  }

  kox_decode_subscription_body() {
    _in="$1"
    _out=$(printf '%s' "$_in" | base64 -d 2>/dev/null) && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
    _out=$(printf '%s' "$_in" | base64 -D 2>/dev/null) && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
    printf '%s' "$_in"
  }

  kox_count_lines() {
    _text="$1"; _pat="$2"
    _n=$(printf '%s\n' "$_text" | grep -E "$_pat" 2>/dev/null | wc -l | tr -d ' \n\r')
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    printf '%d' "$_n"
  }

  KOX_RELAY_HOST="${KOX_RELAY_HOST:-kox.nonamenebula.ru}"
  kox_build_sub_server_list() {
    _raw="$1"; _outfile="$2"
    : > "$_outfile"
    _relay=$(printf '%s\n' "$_raw" | grep -E '^vless://' | grep "@${KOX_RELAY_HOST}:" || true)
    _vother=$(printf '%s\n' "$_raw" | grep -E '^vless://' | grep -v "@${KOX_RELAY_HOST}:" || true)
    _hy2=$(printf '%s\n' "$_raw" | grep -E '^(hysteria2|hy2)://' || true)
    [ -n "$_relay" ] && printf '%s\n' "$_relay" >> "$_outfile"
    [ -n "$_vother" ] && printf '%s\n' "$_vother" >> "$_outfile"
    [ -n "$_hy2" ] && printf '%s\n' "$_hy2" >> "$_outfile"
  }
}

_apply_selected_uri() {
  SELECTED_URI="$1"
  _ensure_kox_lib_early
  if printf '%s' "$SELECTED_URI" | grep -q '^vless://'; then
    VLESS_URL="$SELECTED_URI"
    parse_vless_url "$VLESS_URL"
    ok "Выбран VLESS: ${W}${VLESS_HOST}:${VLESS_PORT}${N}"
  else
    VLESS_HOST=$(uri_host "$SELECTED_URI")
    VLESS_PORT=$(uri_port "$SELECTED_URI"); [ -z "$VLESS_PORT" ] && VLESS_PORT=443
    VLESS_UUID=$(uri_userinfo "$SELECTED_URI")
    VLESS_SNI=$(uri_qparam "$SELECTED_URI" sni)
    VLESS_PBK="placeholder"
    VLESS_SID=""
    VLESS_FP="chrome"
    VLESS_FLOW=""
    ok "Выбран Hysteria2: ${W}${VLESS_HOST}:${VLESS_PORT}${N} (применится после установки CLI)"
  fi
}

SELECTED_URI=""

# ── Установка пакетов ─────────────────────────────────────────────────────────
install_packages() {
  info "Загружаю kox-lib.sh..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-lib.sh" -o /opt/etc/kox-lib.sh 2>/dev/null \
    && chmod +x /opt/etc/kox-lib.sh 2>/dev/null && ok "kox-lib.sh" || warn "kox-lib.sh не загружен"

  info "Обновляю список пакетов..."
  opkg update >/dev/null 2>&1 || warn "opkg update завершился с ошибкой"

  for PKG in xray-core curl jq cron iptables; do
    if opkg list-installed 2>/dev/null | grep -q "^${PKG} "; then
      ok "${PKG} уже установлен"
    else
      info "Устанавливаю ${PKG}..."
      opkg install "$PKG" >/dev/null 2>&1 && ok "${PKG} установлен" || warn "Не удалось установить ${PKG}"
    fi
  done

  # Создать xray init скрипт если не существует
  if [ ! -f "${INIT}/S24xray" ]; then
    info "Создаю xray init скрипт..."
    cat > "${INIT}/S24xray" << 'INITSCRIPT'
#!/bin/sh
ENABLED=yes
PROCS=xray
ARGS="-config /opt/etc/xray/config.json"
PIDFILE=/var/run/xray.pid
ulimit -n 65535 2>/dev/null || true
. /opt/etc/init.d/rc.func
INITSCRIPT
    chmod +x "${INIT}/S24xray"
    ok "Xray init скрипт создан"
  else
    sed -i 's/^ENABLED=no/ENABLED=yes/' "${INIT}/S24xray" 2>/dev/null || true
    if ! grep -q 'ulimit.*65535' "${INIT}/S24xray" 2>/dev/null; then
      awk '
        BEGIN { inserted=0 }
        {
          if (!inserted && $0 ~ /^\. \/opt\/etc\/init\.d\/rc\.func/) {
            print "ulimit -n 65535 2>/dev/null || true"
            inserted=1
          }
          print
        }
        END { if (!inserted) print "ulimit -n 65535 2>/dev/null || true" }
      ' "${INIT}/S24xray" > /tmp/kox-s24xray.new 2>/dev/null && \
        mv /tmp/kox-s24xray.new "${INIT}/S24xray" && chmod +x "${INIT}/S24xray"
      ok "S24xray: добавлен ulimit -n 65535"
    fi
    ok "Xray init скрипт активирован"
  fi

  install_hysteria
}

# ── Установка Hysteria2 (для подписок с hysteria2://|hy2://) ───────────────────
# Xray остаётся прозрачным фронтом; hysteria поднимается как локальный
# SOCKS5-клиент (127.0.0.1:11888), на который указывает outbound kox-proxy
# при переключении на hysteria-сервер. На vless-серверах клиент не запускается.
install_hysteria() {
  HY_BIN="/opt/sbin/hysteria"
  if [ -x "$HY_BIN" ] && "$HY_BIN" version >/dev/null 2>&1; then
    ok "hysteria уже установлен"
  else
    info "Определяю архитектуру для hysteria..."
    # Предпочитаем opkg-арку (Entware), иначе uname -m
    OPKG_ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | grep -v '^all$\|^noarch$' | tail -1)
    RAW_ARCH="${OPKG_ARCH:-$(uname -m)}"
    case "$RAW_ARCH" in
      *aarch64*|*arm64*)            HY_ARCH="arm64" ;;
      *armv7*|*armv6*|*arm*)        HY_ARCH="arm" ;;
      *mipsel*|*mipsle*)            HY_ARCH="mipsle" ;;
      *mips64el*)                   HY_ARCH="mipsle" ;;
      *mips*)                       HY_ARCH="mips" ;;
      *x86_64*|*amd64*)             HY_ARCH="amd64" ;;
      *i?86*|*x86*)                 HY_ARCH="386" ;;
      *)                            HY_ARCH="" ;;
    esac
    if [ -z "$HY_ARCH" ]; then
      warn "Не удалось определить архитектуру ($RAW_ARCH) — hysteria пропущен (vless будет работать)"
    else
      info "Загружаю hysteria (linux-${HY_ARCH})..."
      HY_URL="https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-${HY_ARCH}"
      if curl -fsSL --max-time 60 "$HY_URL" -o "$HY_BIN" 2>/dev/null && [ -s "$HY_BIN" ]; then
        chmod +x "$HY_BIN"
        if "$HY_BIN" version >/dev/null 2>&1; then
          ok "hysteria установлен (${HY_ARCH})"
        else
          # На MIPS без FPU помогает softfloat-вариант
          if [ "$HY_ARCH" = "mipsle" ] || [ "$HY_ARCH" = "mips" ]; then
            info "Пробую softfloat-вариант hysteria..."
            curl -fsSL --max-time 60 "${HY_URL}-sf" -o "$HY_BIN" 2>/dev/null && chmod +x "$HY_BIN"
          fi
          "$HY_BIN" version >/dev/null 2>&1 && ok "hysteria установлен (${HY_ARCH}-sf)" || \
            warn "hysteria не запускается на этом устройстве — vless будет работать"
        fi
      else
        warn "Не удалось загрузить hysteria — vless будет работать, hysteria-серверы недоступны"
      fi
    fi
  fi

  # init-скрипт S25hysteria: стартует клиент только когда KOX_PROTO=hysteria2
  if [ ! -f "${INIT}/S25hysteria" ]; then
    cat > "${INIT}/S25hysteria" << 'HYINIT'
#!/bin/sh
# S25hysteria — KOX Shield hysteria2 client (управляется kox)
# Запускается только если активный протокол — hysteria2.
BIN=/opt/sbin/hysteria
HCONF=/opt/etc/hysteria/client.yaml
KOXCONF=/opt/etc/xray/kox.conf
LOG=/opt/var/log/hysteria.log
[ -f "$KOXCONF" ] && . "$KOXCONF" 2>/dev/null

hy_start() {
  [ "${KOX_PROTO:-vless}" = "hysteria2" ] || { echo "hysteria: KOX_PROTO!=hysteria2 — пропуск"; return 0; }
  [ -x "$BIN" ]   || { echo "hysteria: бинарник отсутствует"; return 1; }
  [ -f "$HCONF" ] || { echo "hysteria: нет client.yaml"; return 1; }
  killall hysteria 2>/dev/null; sleep 1
  ulimit -n 65535 2>/dev/null || true
  "$BIN" client -c "$HCONF" >> "$LOG" 2>&1 &
  echo "hysteria client запущен"
}
hy_stop() { killall hysteria 2>/dev/null; echo "hysteria остановлен"; }

case "$1" in
  start)   hy_start ;;
  stop)    hy_stop ;;
  restart) hy_stop; sleep 1; hy_start ;;
  *)       echo "usage: $0 {start|stop|restart}" ;;
esac
HYINIT
    chmod +x "${INIT}/S25hysteria"
    ok "S25hysteria init скрипт создан"
  fi

  # Запустить crond если не работает
  if ! pgrep crond >/dev/null 2>&1; then
    "${INIT}/S10cron" start 2>/dev/null || crond -c /opt/var/spool/cron/crontabs 2>/dev/null || true
  fi
}

# ── Генерация конфига ─────────────────────────────────────────────────────────
generate_config() {
  mkdir -p "$XRAY_CONF" /opt/var/log

  info "Генерирую config.json..."
  cat > "${XRAY_CONF}/config.json" << CONFIG
{
  "log": {
    "loglevel": "warning",
    "error": "/opt/var/log/xray-err.log",
    "access": "/opt/var/log/xray-acc.log"
  },
  "inbounds": [
    {
      "tag": "kox-transparent",
      "listen": "0.0.0.0",
      "port": 10808,
      "protocol": "dokodemo-door",
      "settings": {"network": "tcp,udp", "followRedirect": true},
      "sniffing": {"enabled": true, "destOverride": ["http","tls","quic"]}
    },
    {
      "tag": "socks-local",
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "socks",
      "settings": {"auth": "noauth", "udp": true}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom", "settings": {}},
    {
      "tag": "kox-proxy",
      "protocol": "vless",
      "settings": {"vnext": [{"address": "${VLESS_HOST}", "port": ${VLESS_PORT},
        "users": [{"id": "${VLESS_UUID}", "encryption": "none", "flow": "${VLESS_FLOW}"}]}]},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "show": false, "fingerprint": "${VLESS_FP}",
          "serverName": "${VLESS_SNI}",
          "publicKey": "${VLESS_PBK}",
          "shortId": "${VLESS_SID}", "spiderX": "/"
        }
      }
    },
    {"tag": "block", "protocol": "blackhole", "settings": {}}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.0.0.0/24","192.168.0.0/16","198.18.0.0/15","198.51.100.0/24","203.0.113.0/24","224.0.0.0/4","240.0.0.0/4"],"outboundTag":"direct"},
      {"type":"field","domain":["domain:${VLESS_HOST}"],"outboundTag":"direct"},
      {"type":"field","network":"udp","port":"53","outboundTag":"direct"},
      {
        "type": "field",
        "domain": [
          "domain:youtube.com",       "domain:youtu.be",           "domain:googlevideo.com",
          "domain:ytimg.com",         "domain:ggpht.com",
          "domain:whatsapp.com",      "domain:whatsapp.net",       "domain:wa.me",
          "domain:twitter.com",       "domain:x.com",              "domain:t.co",
          "domain:twimg.com",
          "domain:instagram.com",     "domain:cdninstagram.com",   "domain:threads.net",
          "domain:facebook.com",      "domain:fbcdn.net",          "domain:fb.com",
          "domain:discord.com",       "domain:discord.gg",         "domain:discordapp.com",
          "domain:tiktok.com",        "domain:tiktokcdn.com",
          "domain:spotify.com",       "domain:scdn.co",
          "domain:netflix.com",       "domain:nflxext.com",        "domain:nflxvideo.net",
          "domain:openai.com",        "domain:chatgpt.com",        "domain:oaiusercontent.com",
          "domain:claude.ai",         "domain:anthropic.com",
          "domain:steampowered.com",  "domain:steamcommunity.com",
          "domain:reddit.com",        "domain:redd.it",
          "domain:linkedin.com",      "domain:licdn.com",
          "domain:canva.com",
          "domain:medium.com",        "domain:notion.so",
          "domain:figma.com",         "domain:zoom.us",
          "domain:twitch.tv",         "domain:twitchcdn.net",
          "domain:github.com",        "domain:githubusercontent.com",
          "domain:npmjs.com",         "domain:docker.io",
          "domain:viber.com",         "domain:signal.org",
          "domain:wikipedia.org",     "domain:wikimedia.org",
          "domain:proton.me",         "domain:protonmail.com",
          "domain:rutracker.org",     "domain:rutor.info",
          "domain:telegram.org",      "domain:t.me",               "domain:tdesktop.com",
          "domain:core.telegram.org", "domain:api.telegram.org",   "domain:cdn.telegram.org",
          "domain:web.telegram.org",  "domain:telegra.ph",         "domain:graph.org",
          "domain:2ip.ru",            "domain:2ip.io",
          "domain:kox.nonamenebula.ru",
          "domain:kox-custom-marker"
        ],
        "outboundTag": "kox-proxy"
      },
      {
        "type": "field",
        "ip": [
          "149.154.160.0/20","91.108.4.0/22",  "91.108.8.0/22",   "91.108.12.0/22",
          "91.108.16.0/22",  "91.108.20.0/22", "91.108.56.0/22",  "95.161.64.0/20",
          "31.13.24.0/21",   "31.13.64.0/18",  "157.240.0.0/17",
          "192.0.2.255/32"
        ],
        "outboundTag": "kox-proxy"
      },
      {"type":"field","network":"udp","outboundTag":"direct"},
      {"type":"field","network":"tcp","outboundTag":"direct"}
    ]
  }
}
CONFIG
  ok "config.json создан"

  # kox.conf
  cat > "${XRAY_CONF}/kox.conf" << KOXCONF
# KOX Shield — параметры сервера
# https://kox.nonamenebula.ru | t.me/PrivateProxyKox
KOX_PROTO="vless"
KOX_SERVER="${VLESS_HOST}"
KOX_PORT="${VLESS_PORT}"
KOX_UUID="${VLESS_UUID}"
KOX_SNI="${VLESS_SNI}"
KOX_FLOW="${VLESS_FLOW}"
KOX_SUB_URL="${SUB_URL:-}"
KOX_INSTALLED="$(date '+%Y-%m-%d %H:%M')"
KOX_BOT_TOKEN=""
KOX_ADMIN_ID=""
KOXCONF
  ok "kox.conf сохранён"
}

# ── iptables NAT ──────────────────────────────────────────────────────────────
setup_nat() {
  info "Настраиваю iptables NAT..."
  NAT_DIR="/opt/etc/ndm/netfilter.d"
  mkdir -p "$NAT_DIR"

  cat > "${NAT_DIR}/99-kox-nat.sh" << 'NATSCRIPT'
#!/bin/sh
[ "$1" = "ip6tables" ] && IPTS=ip6tables || IPTS=iptables

# Не применять если пользователь вручную выключил VPN
[ -f /tmp/kox-vpn-off ] && exit 0

# Не применять если Xray не запущен — иначе весь трафик уйдёт в никуда
pgrep xray >/dev/null 2>&1 || exit 0

$IPTS -t nat -N XRAY_REDIRECT 2>/dev/null || $IPTS -t nat -F XRAY_REDIRECT

# Пропустить приватные IP
for CIDR in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 \
            172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 \
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4; do
  $IPTS -t nat -A XRAY_REDIRECT -d "$CIDR" -j RETURN 2>/dev/null || true
done

# Перенаправить только HTTP/HTTPS — только эти порты используют VPN
# Остальной трафик (игры, торренты, и т.д.) идёт напрямую
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 80  -j REDIRECT --to-ports 10808 2>/dev/null || true
$IPTS -t nat -A XRAY_REDIRECT -p tcp --dport 443 -j REDIRECT --to-ports 10808 2>/dev/null || true

# Применить к трафику LAN
$IPTS -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
$IPTS -t nat -A PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
NATSCRIPT

  chmod +x "${NAT_DIR}/99-kox-nat.sh"
  ok "iptables правила настроены"

  # Watchdog: скачиваем актуальный watchdog v4 с GitHub (failover, Telegram, auto-return) (failover, Telegram, auto-return)
  info "Загружаю watchdog с GitHub..."
  if curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-watchdog.sh" -o /opt/etc/kox-watchdog.sh 2>/dev/null \
      && [ -s /opt/etc/kox-watchdog.sh ]; then
    chmod +x /opt/etc/kox-watchdog.sh
    ok "Watchdog загружен (/opt/etc/kox-watchdog.sh)"
  else
    warn "Не удалось загрузить watchdog с GitHub — используем встроенный"
    cat > /opt/etc/kox-watchdog.sh << 'WATCHDOG_FALLBACK'
#!/bin/sh
# KOX Watchdog (fallback) — минимальная версия
KOXCONF="/opt/etc/xray/kox.conf"
NAT_SCRIPT="/opt/etc/ndm/netfilter.d/99-kox-nat.sh"
LOGF="/opt/var/log/kox-watchdog.log"
[ -f /tmp/kox-vpn-off ] && exit 0
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOGF"; }
if ! pgrep xray >/dev/null 2>&1; then
  log "Xray не работает — снимаю iptables"
  iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -F XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
  ip6tables -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  ulimit -n 65535 2>/dev/null || true
  /opt/etc/init.d/S24xray start 2>/dev/null; sleep 5
  if pgrep xray >/dev/null 2>&1; then
    sh "$NAT_SCRIPT" 2>/dev/null; log "Xray перезапущен"
  else
    log "Xray не запустился — интернет напрямую"
    iptables  -t nat -F XRAY_REDIRECT 2>/dev/null || true
    iptables  -t nat -D PREROUTING -i br0 -p tcp -j XRAY_REDIRECT 2>/dev/null || true
    iptables  -t nat -D PREROUTING -i br0 -p udp --dport 443 -j XRAY_REDIRECT 2>/dev/null || true
  fi
  exit 0
fi
! netstat -ln 2>/dev/null | grep -q ':10808 ' && { killall xray 2>/dev/null; sleep 2; ulimit -n 65535 2>/dev/null || true; /opt/etc/init.d/S24xray start 2>/dev/null; }
! iptables -t nat -L XRAY_REDIRECT 2>/dev/null | grep -q REDIRECT && sh "$NAT_SCRIPT" 2>/dev/null
[ "$(wc -l < "$LOGF" 2>/dev/null || echo 0)" -gt 300 ] && tail -150 "$LOGF" > "$LOGF.tmp" && mv "$LOGF.tmp" "$LOGF"
WATCHDOG_FALLBACK
    chmod +x /opt/etc/kox-watchdog.sh
  fi

  # Добавить watchdog в cron (каждую минуту)
  CRON_LINE="* * * * * /opt/etc/kox-watchdog.sh"
  mkdir -p /opt/var/spool/cron/crontabs
  if ! crontab -l 2>/dev/null | grep -q kox-watchdog; then
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab - 2>/dev/null || \
      echo "$CRON_LINE" >> /opt/var/spool/cron/crontabs/root
    ok "Watchdog добавлен в cron (каждую минуту)"
  else
    ok "Watchdog уже в cron"
  fi

  # Ежедневное обслуживание (hysteria + xray в 04:05)
  if curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-maintenance.sh" -o "$MAINT" 2>/dev/null \
      && [ -s "$MAINT" ]; then
    chmod +x "$MAINT"
    ok "Maintenance-скрипт загружен ($MAINT)"
  else
    warn "Maintenance-скрипт не загружен — cron 04:05 не будет добавлен"
    MAINT=""
  fi
  if [ -n "$MAINT" ] && [ -x "$MAINT" ]; then
    CRON_MAINT="5 4 * * * ${MAINT} >> /opt/var/log/kox-maintenance.log 2>&1 # kox-maintenance"
    TMP=/tmp/kox-cron-install.$$
    crontab -l 2>/dev/null | grep -v 'kox-xray-refresh' | grep -v 'kox-maintenance' > "$TMP" 2>/dev/null || : > "$TMP"
    if ! grep -q kox-maintenance "$TMP" 2>/dev/null; then
      echo "$CRON_MAINT" >> "$TMP"
      crontab "$TMP" 2>/dev/null || echo "$CRON_MAINT" >> /opt/var/spool/cron/crontabs/root 2>/dev/null
      ok "Cron: ежедневное обслуживание в 04:05 (hysteria + xray + ротация логов)"
    fi
    rm -f "$TMP"
  fi

  # Символические ссылки для geo-данных
  if [ ! -f "/opt/usr/share/xray/geoip.dat" ] && [ -f "/opt/usr/share/xray-core/geoip.dat" ]; then
    mkdir -p /opt/usr/share/xray
    ln -sf /opt/usr/share/xray-core/geoip.dat /opt/usr/share/xray/geoip.dat
    ln -sf /opt/usr/share/xray-core/geosite.dat /opt/usr/share/xray/geosite.dat
  fi
}

# ── Загрузка kox CLI и бота с GitHub ─────────────────────────────────────────
download_scripts() {
  info "Загружаю kox-lib.sh..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-lib.sh" -o /opt/etc/kox-lib.sh \
    && chmod +x /opt/etc/kox-lib.sh && ok "kox-lib → /opt/etc/kox-lib.sh" || \
    warn "Не удалось загрузить kox-lib.sh"

  info "Загружаю kox CLI с GitHub..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-cli.sh" -o "${BIN}/kox" && chmod +x "${BIN}/kox" || \
    fail "Не удалось загрузить kox CLI"
  ok "kox → /opt/bin/kox"

  info "Загружаю kox-bot с GitHub..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/kox-bot.sh" -o "${BIN}/kox-bot" && chmod +x "${BIN}/kox-bot" || \
    warn "Не удалось загрузить kox-bot (опционально)"

  info "Загружаю init.d сервис..."
  curl -fsSL --max-time 30 "${GITHUB_RAW}/S90kox-bot" -o "${INIT}/S90kox-bot" && chmod +x "${INIT}/S90kox-bot" || \
    warn "Не удалось загрузить S90kox-bot (опционально)"
}

# ── Запуск Xray ───────────────────────────────────────────────────────────────
start_xray() {
  info "Запускаю Xray..."
  # Остановить если уже запущен (BusyBox не имеет pkill)
  killall xray 2>/dev/null || true; sleep 1
  ulimit -n 65535 2>/dev/null || true
  if [ -f "${INIT}/S24xray" ]; then
    "${INIT}/S24xray" start 2>/dev/null || true
  else
    # Прямой запуск
    /opt/sbin/xray -config "${XRAY_CONF}/config.json" >> /opt/var/log/xray-err.log 2>&1 &
  fi
  sleep 3
  if pgrep xray >/dev/null 2>&1; then
    ok "Xray запущен (PID: $(pgrep xray | head -1))"
  else
    warn "Xray не запустился — проверьте: kox log"
  fi
}

# ── Итог ──────────────────────────────────────────────────────────────────────
show_result() {
  printf "\n"
  sep
  printf " ${G}✓${N}  ${W}KOX Shield установлен!${N}\n"
  sep
  printf "\n"
  printf "  Сервер:  ${W}%s:%s${N}\n" "$VLESS_HOST" "$VLESS_PORT"
  printf "\n"
  printf "  ${C}Команды управления:${N}\n"
  printf "    kox status     — статус VPN\n"
  printf "    kox on/off     — включить/выключить\n"
  printf "    kox add <домен>— добавить домен в туннель\n"
  printf "    kox list       — список доменов\n"
  printf "    kox help       — все команды\n"
  printf "\n"
  printf "  ${C}Telegram Bot:${N}\n"
  printf "    kox.conf: добавьте KOX_BOT_TOKEN и KOX_ADMIN_ID\n"
  printf "    Или: напишите @kox_nonamenebula_bot за токеном\n"
  printf "\n"
  sep
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
banner

# 1. Проверки
info "Проверяю окружение..."
check_entware
ensure_https_tools
check_internet

# 2. Получить URL подписки или VLESS URL
printf "\n"
sep
printf " ${W}Настройка VPN подключения${N}\n"
sep
printf "\n"
printf "  Введите ${W}URL подписки${N} (https://...) или ссылку ${W}vless:// / hysteria2://${N}:\n"
printf "  ${C}Подписка: только HY2, только VLESS или смешанная. Ссылку /u/... заменим на /c/...${N}\n"
printf "\n"
ask "→"
read_tty USER_INPUT
[ -z "$USER_INPUT" ] && fail "Ввод не может быть пустым"

if printf '%s' "$USER_INPUT" | grep -q '^vless://'; then
  SELECTED_URI="$USER_INPUT"
  parse_vless_url "$USER_INPUT"
  ok "VLESS URL принят: ${W}${VLESS_HOST}:${VLESS_PORT}${N}"
elif printf '%s' "$USER_INPUT" | grep -qE '^(hysteria2|hy2)://'; then
  SELECTED_URI="$USER_INPUT"
  _apply_selected_uri "$USER_INPUT"
elif printf '%s' "$USER_INPUT" | grep -q '^https\?://'; then
  SUB_URL="$USER_INPUT"
  parse_subscription "$SUB_URL"
else
  fail "Введите URL подписки (https://...) или vless:// / hysteria2://"
fi

# 3. Установка
printf "\n"
sep
printf " ${W}Установка пакетов${N}\n"
sep
install_packages

# 4. Конфиг
printf "\n"
sep
printf " ${W}Конфигурация${N}\n"
sep
generate_config
setup_nat

# 5. Скачать CLI и бот
printf "\n"
sep
printf " ${W}Установка KOX инструментов${N}\n"
sep
download_scripts

# 6. Запуск
start_xray

# 6b. Hysteria2: применить выбранный сервер через kox CLI
if [ -n "$SELECTED_URI" ] && printf '%s' "$SELECTED_URI" | grep -qE '^(hysteria2|hy2)://'; then
  if [ -x /opt/bin/kox ]; then
    info "Применяю Hysteria2 сервер..."
    /opt/bin/kox _apply-uri "$SELECTED_URI" 2>/dev/null && ok "Hysteria2 настроен" || \
      warn "Не удалось применить hysteria2 — выполните: kox switch"
    /opt/bin/kox restart 2>/dev/null || true
  fi
fi

# 7. Итог
show_result
