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
[![Site](https://img.shields.io/badge/🌐-kox.nonamenebula.ru-blue)](https://kox.nonamenebula.ru)
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

## 📦 Установка

### Способ 1: Прямо с роутера (рекомендуется)

Подключитесь к роутеру по SSH и выполните одну команду:

```bash
wget -qO- https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/install.sh | sh
```

> **Требования:** Keenetic с установленным [Entware](https://help.keenetic.com/hc/ru/articles/360021214160)

Скрипт сам:
- Установит `xray-core`, `curl`, `jq`
- Спросит URL вашей подписки VLESS (или VLESS-ссылку)
- Настроит прозрачный туннель и iptables
- Установит `kox` CLI для управления

### Способ 2: С компьютера Mac/Linux (расширенный)

```bash
# Скачайте установщик
curl -O https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/xraykit.sh
chmod +x xraykit.sh

# Запустите (укажет ваш роутер по IP)
./xraykit.sh
```

Установщик с компьютера дополнительно:
- Автоматически подключается к роутеру по SSH
- Может настроить Telegram Bot во время установки
- Показывает итоговую проверку туннеля

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
kox on                  # Включить VPN (применить iptables)
kox off                 # Выключить VPN (Xray работает, трафик напрямую)
kox restart             # Перезапустить Xray

# Домены и IP
kox add example.com     # Добавить домен в туннель
kox del example.com     # Удалить домен из туннеля
kox check example.com   # Проверить — идёт домен через туннель?
kox list                # Список всех доменов в туннеле
kox add-ip 1.2.3.0/24  # Добавить IP/подсеть в туннель
kox del-ip 1.2.3.0/24  # Удалить IP/подсеть
kox list-ip             # Список IP/подсетей

# Логи и диагностика
kox log                 # Последние ошибки Xray
kox log-live            # Логи в реальном времени (Ctrl+C для выхода)
kox test                # Проверить корректность config.json
kox stats               # Статистика трафика
kox server              # Параметры VLESS сервера

# Обновление
kox update-sub          # Обновить параметры из подписки
kox cron-on             # Включить авто-обновление (ежедневно 04:00)
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

**Возможности бота:**
- ✅ Цветные кнопки (Bot API 9.4)
- ✅ Подтверждение для опасных действий
- ✅ Один чат без флуда (сообщения редактируются на месте)
- ✅ Анимация печатания при длинных операциях
- ✅ Команды в меню `/` (Telegram input)
- ✅ Только для администратора (другие пользователи игнорируются)
- ✅ Трафик бота идёт через VPN (не блокируется провайдером)

### Настройка бота

**Шаг 1.** Создайте бота у [@BotFather](https://t.me/BotFather) → `/newbot` → скопируйте токен

**Шаг 2.** Узнайте свой Telegram ID у [@userinfobot](https://t.me/userinfobot)

**Шаг 3.** На роутере:
```bash
# Откройте конфиг
vi /opt/etc/xray/kox.conf

# Добавьте токен и ID:
KOX_BOT_TOKEN="1234567890:AAF..."
KOX_ADMIN_ID="123456789"

# Запустите бота
/opt/etc/init.d/S90kox-bot start
```

**Или через kox:**
```bash
kox admin set 123456789    # Установить Admin ID
kox bot                     # Проверить статус бота
```

---

## 📋 Список заблокированных сайтов (по умолчанию)

KOX VPN автоматически туннелирует трафик к:

| Категория | Сервисы |
|-----------|---------|
| 📹 Видео | YouTube, TikTok, Twitch, Netflix |
| 💬 Мессенджеры | Telegram, WhatsApp, Signal, Viber, Discord |
| 📱 Соцсети | Instagram, Facebook, Twitter/X, LinkedIn, Reddit, Snapchat |
| 🎵 Музыка | Spotify |
| 🤖 AI | ChatGPT, Claude, Gemini, Copilot |
| 🎮 Игры | Steam |
| 💻 Разработка | GitHub, npm, Docker |
| 📚 Другое | Wikipedia, Medium, Notion, Figma, Zoom, ProtonMail |
| 📰 Торренты | Rutracker, Rutor |

Добавить свой сайт одной командой:
```bash
kox add my-blocked-site.com
```

---

## 🔧 Требования

- **Роутер:** Keenetic (любая модель с Entware)
- **Entware:** Установленный пакетный менеджер ([инструкция](https://help.keenetic.com/hc/ru/articles/360021214160))
- **VLESS сервер:** Подписка или VLESS-ссылка вида `vless://UUID@host:port?params`
- **Протокол:** VLESS + XTLS-Vision + Reality

> Не знаете где взять VLESS сервер? Подпишитесь на [@PrivateProxyKox](https://t.me/PrivateProxyKox)

---

## 📂 Структура файлов

```
/opt/
├── bin/
│   ├── kox              ← CLI управление (kox status, kox add...)
│   └── kox-bot          ← Telegram bot daemon
├── etc/
│   ├── xray/
│   │   ├── config.json  ← Конфиг Xray (VLESS + routing)
│   │   └── kox.conf     ← Параметры сервера и токен бота
│   ├── ndm/
│   │   └── netfilter.d/
│   │       └── 99-kox-nat.sh  ← iptables правила (автозапуск)
│   └── init.d/
│       ├── S24xray      ← Xray сервис (автозапуск)
│       └── S90kox-bot   ← Telegram bot сервис (автозапуск)
└── var/log/
    ├── xray-err.log     ← Логи ошибок Xray
    └── kox-bot.log      ← Логи Telegram бота
```

---

## ❓ Частые вопросы

**Q: Не работает YouTube, хотя установка прошла успешно**

Проверьте:
```bash
kox status          # Всё ли зелёным?
kox log             # Есть ли ошибки?
kox test            # Корректен ли конфиг?
```

**Q: Как добавить сайт который не работает?**
```bash
kox add site.com    # Перезапустит Xray автоматически
```

**Q: Хочу выключить VPN временно (например для банков)**
```bash
kox off             # Xray продолжает работать, трафик прямой
kox on              # Включить обратно
```

**Q: Как обновить сервер из подписки?**
```bash
kox update-sub      # Обновит config.json и перезапустит Xray
```

**Q: Бот не отвечает**
```bash
kox bot             # Проверить статус
/opt/etc/init.d/S90kox-bot restart
tail -20 /opt/var/log/kox-bot.log
```

**Q: Конфликт с другими VPN (Kvass, Shadowsocks, sing-box)**

Запускайте установщик с компьютера (`xraykit.sh`) — он автоматически найдёт и отключит конкурирующие VPN сервисы.

---

## 🆚 Сравнение с Kvass

| | KOX VPN | Kvass |
|--|---------|-------|
| Протокол | VLESS/Reality | Shadowsocks |
| Установка с роутера | ✅ `wget \| sh` | ✅ |
| CLI консоль | ✅ `kox` команды | ✅ |
| Telegram Bot | ✅ Встроен | ❌ |
| Split-tunnel | ✅ По доменам + IP | ✅ |
| Цветные кнопки бота | ✅ Bot API 9.4 | — |
| Обход DPI | ✅ Reality | ⚠️ частично |
| Open source | ✅ | ✅ |

---

## 📄 Лицензия

MIT License — используйте свободно, ссылка на проект приветствуется.

---

<div align="center">

**[🌐 kox.nonamenebula.ru](https://kox.nonamenebula.ru)** · **[📢 Telegram канал](https://t.me/PrivateProxyKox)** · **[🤖 Bot](https://t.me/kox_nonamenebula_bot)**

</div>
