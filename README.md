<div align="center">

```
  ██╗  ██╗  ██████╗  ██╗  ██╗
  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝
  █████╔╝   ██║  ██║  ╚███╔╝ 
  ██╔═██╗   ██║  ██║  ██╔██╗ 
  ██║  ██╗  ╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝
```

**KOX Shield — умное шифрование трафика для роутеров Keenetic**

[![Version](https://img.shields.io/badge/версия-2026.05.02-blue)](CHANGELOG.md)
[![Telegram](https://img.shields.io/badge/Telegram-Канал-blue?logo=telegram)](https://t.me/PrivateProxyKox)
[![Bot](https://img.shields.io/badge/Telegram-Бот-blue?logo=telegram)](https://t.me/kox_nonamenebula_bot)
[![Site](https://img.shields.io/badge/🛡️-kox.nonamenebula.ru-blue)](https://kox.nonamenebula.ru/register)
[![License](https://img.shields.io/badge/Лицензия-MIT-green)](LICENSE)

🌐 **Язык / Language:** **Русский** · [English](README.en.md)

</div>

---

## 🚀 Что такое KOX Shield?

**KOX Shield** — полностью автоматизированная установка VLESS/Reality туннеля на роутеры Keenetic. Только нужные сайты идут через VPN, остальной трафик — напрямую через ваш интернет-провайдер. Никаких ручных настроек.

> ✅ **Переходите с Kvass?** Установщик автоматически обнаруживает и чисто удаляет Kvass, Shadowsocks и sing-box перед настройкой KOX Shield — нужно только подтвердить удаление.

### ✨ Ключевые возможности

| Функция | Описание |
|---------|----------|
| 🔀 **Умное шифрование** | Только нужные сайты через VPN, всё остальное напрямую |
| ⚡ **VLESS + Reality** | Современный протокол — невидим для провайдера и DPI |
| 🌐 **Смена серверов** | Переключение VPN-сервера в боте с пингом и авто-откатом |
| 🛡️ **Фолбэк при сбое** | Watchdog: если Xray упал — снимает iptables, интернет не пропадает |
| 📱 **Telegram Bot** | Полное управление роутером прямо из Telegram |
| 💻 **KOX Console** | Удобный CLI на роутере — `kox status`, `kox add`, `kox list`... |
| 🔄 **Авто-обновление** | Ежедневное обновление параметров из подписки |
| 🏠 **Для всей сети** | Подключили роутер — работает на всех устройствах |

---

## 🔑 Откуда взять VLESS сервер?

### Вариант 1: Подписка KOX Shield (готово за 1 минуту)

Зарегистрируйтесь на **[kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register)** — получите готовую VLESS-подписку с несколькими серверами, поддержкой и автообновлением.

### Вариант 2: Свой сервер (для продвинутых)

Если у вас есть VPS — можно поднять собственный VLESS/Reality сервер:

**1. Установите Xray на сервер (Ubuntu/Debian):**
```bash
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
```

**2. Сгенерируйте ключи:**
```bash
xray x25519                          # privateKey + publicKey
openssl rand -hex 4                  # shortId
cat /proc/sys/kernel/random/uuid     # UUID
```

**3. Ваша VLESS-ссылка будет выглядеть так:**
```
vless://UUID@YOUR-IP:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC-KEY&sid=SHORT-ID&flow=xtls-rprx-vision#MyServer
```

> 💡 Подробнее о Reality: [github.com/XTLS/REALITY](https://github.com/XTLS/REALITY)

---

## 📦 Установка на роутер

### Способ 1: Прямо с роутера (рекомендуется)

Подключитесь к роутеру по SSH (порт 222) и выполните одну команду:

```bash
curl -fsSL https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh | sh
```

> **Требования:** Keenetic с установленным [Entware](https://help.keenetic.com/hc/ru/articles/360021214160)

Скрипт сам:
- Установит `xray-core`, `curl`, `jq`, `cron`, `iptables`
- Спросит URL подписки или VLESS-ссылку
- При нескольких серверах предложит выбор
- **По вашему запросу** удалит Kvass / Shadowsocks / sing-box
- Настроит прозрачный туннель (только порты 80/443)
- Установит watchdog — автовосстановление при сбое Xray
- Установит `kox` CLI для управления

### Способ 2: С компьютера Mac/Linux (расширенный)

```bash
curl -O https://raw.githubusercontent.com/nonamenebula/kox-shield/main/xraykit.sh
chmod +x xraykit.sh
./xraykit.sh
```

Дополнительно настроит Telegram Bot и проведёт финальную проверку туннеля.

---

## 🔄 Миграция с Kvass на KOX Shield

KOX Shield — полноценная замена Kvass с более современным протоколом (VLESS/Reality вместо Shadowsocks).

Установщик обрабатывает миграцию автоматически:
1. Обнаруживает установленные Kvass, Shadowsocks или sing-box
2. **Спрашивает подтверждение** перед удалением
3. Чисто останавливает сервисы и удаляет конфиги
4. Устанавливает KOX Shield с вашей VLESS-подпиской

Настройки роутера и другие конфигурации **не затрагиваются**.

---

## 🖥️ KOX Console — управление на роутере

После установки на роутере появляется команда `kox`:

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
kox list-ip             # Список IP/подсетей

# Логи и диагностика
kox log                 # Последние ошибки Xray
kox log-live            # Логи в реальном времени (Ctrl+C)
kox clear-log           # Очистить все логи (Xray + бот)
kox test                # Проверить корректность config.json
kox stats               # Статистика трафика
kox server              # Параметры VLESS сервера
kox watchdog-log        # Лог watchdog (авто-фолбэк)

# Подписка и серверы
kox sub set <URL>       # Задать URL подписки
kox sub get             # Показать текущий URL подписки
kox update-sub          # Обновить параметры из подписки
kox cron-on             # Авто-обновление (ежедневно 04:00)
kox cron-off            # Отключить авто-обновление

# Списки доменов по категориям
kox list-cats                   # Все доступные категории (Telegram, YouTube, ...)
kox list-load telegram          # Загрузить категорию в туннель
kox list-load all               # Загрузить все категории сразу
kox list-remove telegram        # Удалить категорию из туннеля
kox list-check                  # Проверить наличие обновлений
kox list-update                 # Обновить списки с GitHub

# Обновление KOX Shield
kox upgrade             # Проверить и установить обновление KOX Shield

# Резервные копии
kox backup              # Создать бэкап config.json
kox restore [файл]      # Восстановить из бэкапа

# Telegram Bot
kox bot                 # Статус бота
kox admin set <ID>      # Назначить Telegram администратора
kox admin show          # Показать текущего администратора

# Справка
kox help                # Список всех команд
```

---

## 🤖 Telegram Bot

Управляйте роутером прямо из Telegram без SSH:

```
┌─────────────────────────────────────────┐
│  🔑 KOX Shield — управление роутером   │
│  Выберите действие:                     │
├──────────────────┬──────────────────────┤
│ 📊 Статус        │ 🌐 Серверы →         │
│ ✅ Вкл VPN       │ ❌ Выкл VPN          │
│ 🔄 Рестарт Xray  │ 🔧 Тест конфига      │
│ 📋 Домены и IP → │ 🛠 Инструменты →     │
│ ⚙️ Настройки     │ ❓ Помощь            │
└──────────────────┴──────────────────────┘
```

**Возможности:**
- ✅ Цветные кнопки (Bot API 9.4)
- ✅ Подтверждение для опасных действий
- ✅ Чат без флуда — сообщения редактируются на месте
- ✅ `/start` всегда присылает свежее меню
- ✅ Только для администратора — остальные игнорируются
- ✅ Трафик бота идёт через VPN, при сбое — напрямую (автофолбэк)
- 🔔 Уведомления об обновлениях KOX и списков доменов

### 🌐 Переключение серверов

Нажмите **🌐 Серверы → 🔀 Сменить сервер**:

```
🔀 Выберите сервер:

🟢 🇩🇪 Германия | Klever — 192.0.2.10:443 — 39 ms
🟢 🇩🇪 Германия          — 192.0.2.11:2053 — 36 ms
🟡 🇺🇸 США               — 198.51.100.20:8444 — 111 ms
🟢 🇨🇿 Чехия             — 198.51.100.21:443 — 38 ms
✅ 🟢 🇫🇮 Хельсинки      — 203.0.113.50:443 — 28 ms
```

- Измеряет реальный пинг до каждого сервера
- 🟢 < 50 ms · 🟡 < 120 ms · 🟠 < 250 ms · 🔴 высокий · ⚫ нет ответа
- ✅ — текущий активный сервер
- **Авто-откат**: если Xray не запустился на новом сервере — конфиг автоматически восстанавливается

### Команды через Telegram

```
/start     — сбросить меню (если пропало после очистки чата)
/status    — статус VPN
/on /off   — включить/выключить VPN
/add site  — добавить домен
/del site  — удалить домен
/update    — проверить и установить обновление
/sub URL   — задать URL подписки
/help      — справка
```

### Настройка бота

**1.** Создайте бота у [@BotFather](https://t.me/BotFather) → `/newbot` → скопируйте токен

**2.** Узнайте свой Telegram ID у [@userinfobot](https://t.me/userinfobot)

**3.** Добавьте в `/opt/etc/xray/kox.conf` на роутере:
```
KOX_BOT_TOKEN="1234567890:AAF..."
KOX_ADMIN_ID="123456789"
KOX_SUB_URL="https://kox.nonamenebula.ru/c/YOUR_TOKEN"
```

**4.** Запустите:
```bash
/opt/etc/init.d/S90kox-bot start
```

---

## 🛡️ Фолбэк при сбое VPN

**Главное отличие KOX Shield:** если VPN перестаёт работать — интернет не пропадает.

Как это работает:
1. **iptables** перехватывает только **порты 80 и 443** (HTTP/HTTPS) — не весь TCP
2. **Watchdog** запускается каждые 5 минут и проверяет:
   - Работает ли процесс Xray
   - Слушает ли порт 10808
   - Применены ли iptables правила
3. Если Xray упал — watchdog **снимает iptables правила**, трафик идёт напрямую
4. Watchdog пытается перезапустить Xray, при успехе — правила восстанавливаются
5. Команда `kox off` / кнопка ❌ в боте — мгновенно отключает VPN, интернет работает

```bash
kox off              # Выключить VPN (интернет напрямую, Xray продолжает работать)
kox on               # Включить VPN обратно
kox watchdog-log     # Посмотреть лог watchdog
```

---

## 📋 Категории доменов

KOX Shield поставляется с **29 категориями** доменов и IP-адресов. Загружайте только то, что нужно:

```bash
kox list-cats          # посмотреть все категории
kox list-load youtube  # добавить YouTube в туннель
kox list-load all      # добавить всё сразу
```

| # | Категория | Что включено |
|---|-----------|--------------|
| ✈️ | `telegram` | Telegram, WebApp, Telegraph (21 домен) |
| 📺 | `youtube` | YouTube, Shorts, API (7 доменов) |
| 💬 | `whatsapp` | WhatsApp, wa.me (15 доменов) |
| 🐦 | `twitter-x` | Twitter / X (12 доменов) |
| 📸 | `instagram` | Instagram, Threads (5 доменов) |
| 👤 | `facebook` | Facebook, Messenger (8д + 10 IP) |
| 🎮 | `discord` | Discord, CDN (8 доменов) |
| 🎵 | `tiktok` | TikTok (8 доменов) |
| 🎶 | `spotify` | Spotify (5 доменов) |
| 🎬 | `netflix` | Netflix (7 доменов) |
| 🤖 | `chatgpt-openai` | ChatGPT, Claude, Gemini (13 доменов) |
| 🔍 | `google` | Google accounts, Gemini (5 доменов) |
| 🎮 | `steam` | Steam (7 доменов) |
| 🌐 | `reddit` | Reddit (6 доменов) |
| 💼 | `linkedin` | LinkedIn (3 домена) |
| 🎨 | `canva` | Canva (3 домена) |
| 🔎 | `bing` | Bing, Copilot (5 доменов) |
| 📝 | `medium-notion` | Medium, Notion, Figma, Miro (8 доменов) |
| 📹 | `zoom` | Zoom (4 домена) |
| 📡 | `twitch` | Twitch (5 доменов) |
| 💻 | `github-dev` | GitHub, npm, Docker, GitLab, StackOverflow (16 доменов) |
| 🎵 | `soundcloud` | SoundCloud (2 домена) |
| 📱 | `viber` | Viber (2 домена) |
| 🔒 | `signal` | Signal (3 домена) |
| 📌 | `pinterest` | Pinterest (2 домена) |
| 📶 | `telegram-ip` | Telegram IP для звонков (13 подсетей) |
| 📦 | `other` | Patreon, PayPal, BBC, Wikipedia и др. (25 доменов) |

> Бот уведомляет вас, когда появляются обновления категорий.

---

## 📂 Структура файлов на роутере

```
/opt/
├── bin/
│   ├── kox              ← CLI управление
│   └── kox-bot          ← Telegram bot daemon
├── etc/
│   ├── xray/
│   │   ├── config.json          ← Конфиг Xray (VLESS + routing)
│   │   ├── kox.conf             ← Параметры сервера + токен бота
│   │   ├── .kox-bot-offset      ← Offset бота (persistent)
│   │   └── lists/               ← Категории доменов
│   ├── ndm/netfilter.d/
│   │   └── 99-kox-nat.sh        ← iptables правила (порты 80/443)
│   └── init.d/
│       ├── S24xray              ← Xray сервис (автозапуск)
│       └── S90kox-bot           ← Telegram bot сервис (автозапуск)
├── var/log/
│   ├── xray-err.log             ← Логи Xray
│   ├── kox-bot.log              ← Логи бота
│   └── kox-watchdog.log         ← Лог watchdog
└── etc/kox-watchdog.sh          ← Watchdog (cron 5 мин)
```

---

## ⬆️ Обновление KOX Shield

### Через бота (удобнее всего)

Нажмите `/update` в чате с ботом или `/settings` → включите автообновление.

### Через консоль

```bash
kox upgrade
```

Проверит версию на GitHub, покажет список изменений и спросит подтверждение.

### Вручную (для старых версий без `kox upgrade`)

```bash
curl -fsSL https://raw.githubusercontent.com/nonamenebula/kox-shield/main/kox-cli.sh \
  -o /opt/bin/kox && chmod +x /opt/bin/kox && kox upgrade
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

**Q: Как временно выключить VPN (для банков, госуслуг)?**
```bash
kox off   # Трафик напрямую, Xray не останавливается
kox on    # Включить обратно
```
Или нажмите ❌ Выкл VPN в боте.

**Q: Пропал интернет после включения VPN**

KOX Shield перехватывает только порты 80/443. Watchdog автоматически снимает iptables если Xray упал. Если интернет пропал — выполните `kox off`.

**Q: Как переключить сервер?**

В боте: **🌐 Серверы → 🔀 Сменить сервер**. Или через консоль:
```bash
kox update-sub   # обновить из подписки (берёт первый сервер)
```

**Q: Как задать URL подписки?**
```bash
kox sub set https://kox.nonamenebula.ru/c/YOUR_TOKEN
```
Или командой `/sub URL` прямо в боте.

**Q: Бот не отвечает / не присылает меню**
```bash
/opt/etc/init.d/S90kox-bot restart
tail -20 /opt/var/log/kox-bot.log
```
Если очистили чат — напишите `/start`, бот пришлёт свежее меню.

**Q: Конфликт с Kvass — как мигрировать?**

Запустите установщик — он обнаружит Kvass и предложит его удалить. Для ручной установки используйте `xraykit.sh` с компьютера.

---

## 🆚 KOX Shield vs Kvass

| | KOX Shield | Kvass |
|--|---------|-------|
| Протокол | VLESS + Reality | Shadowsocks |
| Защита от DPI | ✅ Невидим для провайдера | ⚠️ Частично |
| Фолбэк при сбое VPN | ✅ Watchdog + авто-восстановление | ❌ |
| Установка с роутера | ✅ `curl \| sh` | ✅ |
| Установка с ПК | ✅ `xraykit.sh` | ✅ |
| CLI консоль | ✅ `kox` | ✅ |
| Telegram Bot | ✅ Встроен | ❌ |
| Смена серверов из бота | ✅ С пингом и авто-откатом | — |
| Уведомления об обновлениях | ✅ | — |
| Умное шифрование | ✅ Домены + IP | ✅ |
| Авто-обновление | ✅ | ✅ |
| Миграция с Kvass | ✅ Автоматически | — |
| Open source | ✅ | ✅ |

---

## 🔧 Требования

- **Роутер:** Keenetic (любая модель с поддержкой Entware)
- **Entware:** [Инструкция по установке](https://help.keenetic.com/hc/ru/articles/360021214160)
- **VLESS сервер:** Подписка [kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register) или свой сервер

---

## 📄 Лицензия

MIT License — используйте свободно, ссылка на проект приветствуется.

---

<div align="center">

**[🌐 kox.nonamenebula.ru](https://kox.nonamenebula.ru/register)** · **[📢 Telegram](https://t.me/PrivateProxyKox)** · **[🤖 Bot](https://t.me/kox_nonamenebula_bot)**

</div>
