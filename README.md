<div align="center">

```
  ██╗  ██╗  ██████╗  ██╗  ██╗
  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝
  █████╔╝   ██║  ██║  ╚███╔╝ 
  ██╔═██╗   ██║  ██║  ██╔██╗ 
  ██║  ██╗  ╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝
```

**VLESS split-tunnel VPN для роутеров Keenetic**

[![Telegram](https://img.shields.io/badge/Telegram-Channel-blue?logo=telegram)](https://t.me/PrivateProxyKox)
[![Bot](https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram)](https://t.me/kox_nonamenebula_bot)
[![Site](https://img.shields.io/badge/🌐-kox.nonamenebula.ru-blue)](https://kox.nonamenebula.ru/register)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

</div>

---

## 🚀 Что такое KOX VPN?

**KOX VPN** — полностью автоматизированная установка VLESS/Reality туннеля на роутеры Keenetic. Весь трафик к заблокированным сайтам идёт через VPN, остальной — напрямую через ваш интернет провайдер. Никаких ручных настроек.

### ✨ Ключевые возможности

| Функция | Описание |
|---------|----------|
| 🔀 **Split-tunnel** | Только заблокированные сайты через VPN, всё остальное напрямую |
| ⚡ **VLESS + Reality** | Современный протокол, не определяется провайдером |
| 📱 **Telegram Bot** | Полное управление роутером прямо из Telegram |
| 💻 **KOX Console** | Удобный CLI на роутере — `kox status`, `kox add`, `kox list`... |
| 🔄 **Авто-обновление** | Ежедневное обновление серверных параметров из подписки |
| 🏠 **Для всей сети** | Подключили роутер — работает на всех устройствах без настройки |

---

## 🔑 VLESS сервер — откуда взять?

Для работы KOX VPN нужен **VLESS сервер**. Есть два варианта:

### Вариант 1: Подписка KOX VPN (готово за 1 минуту)

Зарегистрируйтесь на **[kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register)** — получите готовую VLESS-подписку с несколькими серверами, поддержкой и автообновлением.

### Вариант 2: Свой сервер (для продвинутых)

Если у вас уже есть VPS, можно поднять собственный VLESS/Reality сервер:

**1. Установите Xray на сервер (Ubuntu/Debian):**
```bash
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
```

**2. Создайте конфиг `/usr/local/etc/xray/config.json`:**
```json
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "YOUR-UUID", "flow": "xtls-rprx-vision"}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "www.microsoft.com:443",
        "serverNames": ["www.microsoft.com"],
        "privateKey": "YOUR-PRIVATE-KEY",
        "shortIds": ["YOUR-SHORT-ID"]
      }
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
```

**3. Сгенерируйте ключи:**
```bash
xray x25519            # privateKey + publicKey
openssl rand -hex 4    # shortId
cat /proc/sys/kernel/random/uuid  # UUID
```

**4. Ваша VLESS-ссылка будет выглядеть так:**
```
vless://UUID@YOUR-SERVER-IP:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC-KEY&sid=SHORT-ID&flow=xtls-rprx-vision#MyServer
```

**5. Вставьте эту ссылку при установке KOX VPN на роутер.**

> 💡 Подробнее о Reality: [github.com/XTLS/REALITY](https://github.com/XTLS/REALITY)

---

## 📦 Установка на роутер

### Способ 1: Прямо с роутера (рекомендуется)

Подключитесь к роутеру по SSH (порт 222) и выполните одну команду:

```bash
wget -qO- https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/install.sh | sh
```

> **Требования:** Keenetic с установленным [Entware](https://help.keenetic.com/hc/ru/articles/360021214160)

Скрипт сам:
- Установит `xray-core`, `curl`, `jq`
- Спросит URL подписки или VLESS-ссылку
- При нескольких серверах предложит выбор
- Настроит прозрачный туннель и iptables
- Установит `kox` CLI для управления

### Способ 2: С компьютера Mac/Linux (расширенный)

```bash
# Скачайте установщик
curl -O https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/xraykit.sh
chmod +x xraykit.sh

# Запустите
./xraykit.sh
```

Дополнительно настроит Telegram Bot и проведёт финальную проверку туннеля.

---

## 🖥️ KOX Console — управление на роутере

После установки на роутере появляется команда `kox`:

```
  ██╗  ██╗  ██████╗  ██╗  ██╗
  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝
  █████╔╝   ██║  ██║  ╚███╔╝ 
  ██╔═██╗   ██║  ██║  ██╔██╗ 
  ██║  ██╗  ╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝

            ── VPN Console ──

  🌐 kox.nonamenebula.ru
  📢 t.me/PrivateProxyKox
  🤖 @kox_nonamenebula_bot
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Команды

```bash
# Статус и управление
kox status              # Статус VPN, Xray, iptables
kox on                  # Включить VPN
kox off                 # Выключить VPN (Xray работает, трафик напрямую)
kox restart             # Перезапустить Xray

# Домены и IP
kox add example.com     # Добавить домен в туннель
kox del example.com     # Удалить домен из туннеля
kox check example.com   # Проверить — идёт домен через туннель?
kox list                # Список всех доменов
kox add-ip 1.2.3.0/24  # Добавить IP/подсеть в туннель
kox del-ip 1.2.3.0/24  # Удалить IP/подсеть
kox list-ip             # Список IP/подсетей

# Логи и диагностика
kox log                 # Последние ошибки Xray
kox log-live            # Логи в реальном времени (Ctrl+C)
kox test                # Проверить корректность config.json
kox stats               # Статистика трафика
kox server              # Параметры VLESS сервера

# Обновление
kox update-sub          # Обновить параметры из подписки
kox cron-on             # Авто-обновление (ежедневно 04:00)
kox cron-off            # Отключить авто-обновление

# Резервные копии
kox backup              # Создать бэкап config.json
kox restore [файл]      # Восстановить из бэкапа

# Telegram Bot
kox bot                 # Статус бота
kox admin set <ID>      # Назначить Telegram администратора
kox admin show          # Показать текущего администратора
```

---

## 🤖 Telegram Bot

Управляйте роутером прямо из Telegram без SSH:

```
  ┌─────────────────────────────────────┐
  │  🔑 KOX VPN — управление роутером  │
  │  Выберите действие:                 │
  ├──────────────┬──────────────────────┤
  │ 📊 Статус   │ 🌐 Сервер            │
  │ ✅ Вкл VPN  │ ❌ Выкл VPN         │
  │ 🔄 Рестарт  │ 🔧 Тест конфига     │
  │ 📋 Домены   │ 🔢 IP-список         │
  │ ➕ Домен    │ ➖ Удалить домен     │
  │ 📝 Логи     │ 📈 Трафик            │
  │ 💾 Бэкап    │ 🗑️ Очистить логи    │
  └─────────────┴──────────────────────┘
```

**Возможности:**
- ✅ Цветные кнопки (Bot API 9.4)
- ✅ Подтверждение для опасных действий
- ✅ Чат без флуда — сообщения редактируются на месте
- ✅ Анимация печатания при длинных операциях
- ✅ Меню команд `/` в Telegram
- ✅ Только для администратора
- ✅ Трафик бота идёт через VPN (не блокируется)

### Настройка бота

**1.** Создайте бота у [@BotFather](https://t.me/BotFather) → `/newbot` → скопируйте токен

**2.** Узнайте свой Telegram ID у [@userinfobot](https://t.me/userinfobot)

**3.** На роутере добавьте в `/opt/etc/xray/kox.conf`:
```bash
KOX_BOT_TOKEN="1234567890:AAF..."
KOX_ADMIN_ID="123456789"
```

**4.** Запустите:
```bash
/opt/etc/init.d/S90kox-bot start
```

---

## 📋 Встроенные домены (по умолчанию)

| Категория | Сервисы |
|-----------|---------|
| 📹 Видео | YouTube, TikTok, Twitch, Netflix |
| 💬 Мессенджеры | Telegram, WhatsApp, Signal, Viber, Discord |
| 📱 Соцсети | Instagram, Facebook, Twitter/X, LinkedIn, Reddit |
| 🎵 Музыка | Spotify |
| 🤖 AI | ChatGPT, Claude, Gemini, Copilot |
| 🎮 Игры | Steam |
| 💻 Разработка | GitHub, npm, Docker |
| 📚 Другое | Wikipedia, Medium, Notion, Figma, Zoom, ProtonMail |
| 📰 Торренты | Rutracker, Rutor |

Добавить свой сайт:
```bash
kox add my-site.com
```

---

## 🔧 Требования

- **Роутер:** Keenetic (любая модель с Entware)
- **Entware:** [Инструкция по установке](https://help.keenetic.com/hc/ru/articles/360021214160)
- **VLESS сервер:** Подписка [kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register) или свой сервер (см. выше)

---

## 📂 Структура файлов на роутере

```
/opt/
├── bin/
│   ├── kox              ← CLI управление
│   └── kox-bot          ← Telegram bot daemon
├── etc/
│   ├── xray/
│   │   ├── config.json  ← Конфиг Xray (VLESS + routing)
│   │   └── kox.conf     ← Параметры сервера и токен бота
│   ├── ndm/netfilter.d/
│   │   └── 99-kox-nat.sh  ← iptables правила (автозапуск)
│   └── init.d/
│       ├── S24xray      ← Xray сервис (автозапуск)
│       └── S90kox-bot   ← Telegram bot сервис (автозапуск)
└── var/log/
    ├── xray-err.log     ← Логи Xray
    └── kox-bot.log      ← Логи бота
```

---

## ❓ Частые вопросы

**Q: Не работает YouTube после установки**
```bash
kox status   # Всё зелёным?
kox log      # Есть ошибки?
kox test     # Конфиг корректен?
```

**Q: Как добавить сайт который не открывается?**
```bash
kox add site.com   # Xray перезапустится автоматически
```

**Q: Как временно выключить VPN (для банков)?**
```bash
kox off   # Трафик напрямую, Xray не останавливается
kox on    # Вернуть обратно
```

**Q: Как обновить параметры сервера?**
```bash
kox update-sub   # Обновит из подписки и перезапустит Xray
```

**Q: Бот не отвечает**
```bash
kox bot
/opt/etc/init.d/S90kox-bot restart
tail -20 /opt/var/log/kox-bot.log
```

---

## 📄 Лицензия

MIT License — используйте свободно.

---

<div align="center">

**[🌐 kox.nonamenebula.ru](https://kox.nonamenebula.ru/register)** · **[📢 Telegram](https://t.me/PrivateProxyKox)** · **[🤖 Bot](https://t.me/kox_nonamenebula_bot)**

</div>
