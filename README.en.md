<div align="center">

```
  ██╗  ██╗  ██████╗  ██╗  ██╗
  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝
  █████╔╝   ██║  ██║  ╚███╔╝ 
  ██╔═██╗   ██║  ██║  ██╔██╗ 
  ██║  ██╗  ╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝
```

**VLESS split-tunnel VPN for Keenetic routers**

[![Telegram](https://img.shields.io/badge/Telegram-Channel-blue?logo=telegram)](https://t.me/PrivateProxyKox)
[![Bot](https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram)](https://t.me/kox_nonamenebula_bot)
[![Site](https://img.shields.io/badge/🌐-kox.nonamenebula.ru-blue)](https://kox.nonamenebula.ru/register)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

🌐 **Language / Язык:** [Русский](README.md) · **English**

</div>

---

## 🚀 What is KOX VPN?

**KOX VPN** is a fully automated VLESS/Reality tunnel setup for Keenetic routers. Traffic to blocked sites goes through the VPN; everything else goes directly through your ISP. No manual configuration needed.

> ✅ **Migrating from Kvass?** The installer automatically detects and cleanly removes Kvass, Shadowsocks, and sing-box before setting up KOX VPN — just answer "yes" when prompted.

### ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔀 **Split-tunnel** | Only blocked sites through VPN, everything else direct |
| ⚡ **VLESS + Reality** | Modern protocol — undetectable by ISP/DPI |
| 📱 **Telegram Bot** | Full router management from Telegram |
| 💻 **KOX Console** | Router CLI — `kox status`, `kox add`, `kox list`... |
| 🔄 **Auto-update** | Daily subscription parameter refresh |
| 🏠 **Whole network** | Works on all devices once the router is set up |

---

## 🔑 Getting a VLESS Server

### Option 1: KOX VPN Subscription (ready in 1 minute)

Register at **[kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register)** — get a ready VLESS subscription with multiple servers, support, and auto-update.

### Option 2: Your Own Server

If you have a VPS, set up your own VLESS/Reality server:

**1. Install Xray on the server (Ubuntu/Debian):**
```bash
bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)
```

**2. Generate keys:**
```bash
xray x25519                          # privateKey + publicKey
openssl rand -hex 4                  # shortId
cat /proc/sys/kernel/random/uuid     # UUID
```

**3. Create `/usr/local/etc/xray/config.json`:**
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

**4. Your VLESS link will look like:**
```
vless://UUID@YOUR-IP:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC-KEY&sid=SHORT-ID&flow=xtls-rprx-vision#MyServer
```

> 💡 More about Reality: [github.com/XTLS/REALITY](https://github.com/XTLS/REALITY)

---

## 📦 Installation

### Method 1: Directly on the Router (recommended)

Connect to your router via SSH (port 222) and run one command:

```bash
wget -qO- https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/install.sh | sh
```

> **Requirements:** Keenetic router with [Entware](https://help.keenetic.com/hc/en-us/articles/360021214160) installed

The script will:
- Install `xray-core`, `curl`, `jq`
- Ask for your subscription URL or VLESS link
- Show server selection if multiple servers are available
- **Optionally remove Kvass / Shadowsocks / sing-box** (asks for confirmation first)
- Configure transparent tunnel and iptables rules
- Install the `kox` CLI

### Method 2: From Mac / Linux PC (advanced)

```bash
curl -O https://raw.githubusercontent.com/nonamenebula/kox-vpn/main/xraykit.sh
chmod +x xraykit.sh
./xraykit.sh
```

Additionally sets up the Telegram Bot and runs a final tunnel verification.

---

## 🔄 Migrating from Kvass

KOX VPN is a full replacement for Kvass with a more modern protocol (VLESS/Reality instead of Shadowsocks).

The installer handles migration automatically:
1. Detects installed Kvass, Shadowsocks, or sing-box
2. **Asks for confirmation** before removing anything
3. Cleanly stops services and removes configs
4. Installs KOX VPN with your VLESS subscription

Your router settings and other configurations are **not affected**.

---

## 🖥️ KOX Console

After installation the `kox` command is available on the router:

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

### Commands

```bash
# Status & control
kox status              # VPN, Xray, iptables status
kox on                  # Enable VPN
kox off                 # Disable VPN (Xray keeps running, traffic goes direct)
kox restart             # Restart Xray

# Domains & IPs
kox add example.com     # Add domain to tunnel
kox del example.com     # Remove domain from tunnel
kox check example.com   # Check — does this domain go through tunnel?
kox list                # List all tunneled domains
kox add-ip 1.2.3.0/24  # Add IP/subnet to tunnel
kox del-ip 1.2.3.0/24  # Remove IP/subnet
kox list-ip             # List all IP/subnets

# Logs & diagnostics
kox log                 # Recent Xray errors
kox log-live            # Live log stream (Ctrl+C to stop)
kox test                # Validate config.json
kox stats               # Traffic statistics
kox server              # VLESS server parameters

# Updates
kox update-sub          # Update server parameters from subscription
kox cron-on             # Enable auto-update (daily at 04:00)
kox cron-off            # Disable auto-update

# Backups
kox backup              # Backup config.json
kox restore [file]      # Restore from backup

# Telegram Bot
kox bot                 # Bot status
kox admin set <ID>      # Set Telegram administrator
kox admin show          # Show current administrator
```

---

## 🤖 Telegram Bot

Manage your router from Telegram without SSH:

```
  ┌─────────────────────────────────────┐
  │  🔑 KOX VPN — Router Management    │
  │  Choose action:                     │
  ├──────────────┬──────────────────────┤
  │ 📊 Status   │ 🌐 Server            │
  │ ✅ VPN On   │ ❌ VPN Off           │
  │ 🔄 Restart  │ 🔧 Test config       │
  │ 📋 Domains  │ 🔢 IP list           │
  │ ➕ Add      │ ➖ Remove domain      │
  │ 📝 Logs     │ 📈 Traffic           │
  │ 💾 Backup   │ 🗑️ Clear logs        │
  └─────────────┴──────────────────────┘
```

**Features:**
- ✅ Colored buttons (Bot API 9.4)
- ✅ Confirmation dialogs for dangerous actions
- ✅ No chat flooding — messages edited in place
- ✅ Typing animation for long operations
- ✅ `/` command menu in Telegram
- ✅ Admin-only — all other users are silently ignored
- ✅ Bot traffic routes through VPN (not blocked by ISP)

### Bot Setup

**1.** Create a bot at [@BotFather](https://t.me/BotFather) → `/newbot` → copy the token

**2.** Get your Telegram ID from [@userinfobot](https://t.me/userinfobot)

**3.** Add to `/opt/etc/xray/kox.conf` on the router:
```
KOX_BOT_TOKEN="1234567890:AAF..."
KOX_ADMIN_ID="123456789"
```

**4.** Start the bot:
```bash
/opt/etc/init.d/S90kox-bot start
```

---

## 📋 Built-in Domain List

| Category | Services |
|----------|----------|
| 📹 Video | YouTube, TikTok, Twitch, Netflix |
| 💬 Messengers | Telegram, WhatsApp, Signal, Viber, Discord |
| 📱 Social | Instagram, Facebook, Twitter/X, LinkedIn, Reddit |
| 🎵 Music | Spotify |
| 🤖 AI | ChatGPT, Claude, Gemini, Copilot |
| 🎮 Gaming | Steam |
| 💻 Dev tools | GitHub, npm, Docker |
| 📚 Other | Wikipedia, Medium, Notion, Figma, Zoom, ProtonMail |
| 📰 Torrents | Rutracker, Rutor |

Add any site with one command:
```bash
kox add my-blocked-site.com
```

---

## 🆚 KOX VPN vs Kvass

| | KOX VPN | Kvass |
|--|---------|-------|
| Protocol | VLESS + Reality | Shadowsocks |
| DPI bypass | ✅ Undetectable | ⚠️ Partial |
| Install from router | ✅ `wget \| sh` | ✅ |
| Install from PC | ✅ `xraykit.sh` | ✅ |
| CLI console | ✅ `kox` | ✅ |
| Telegram Bot | ✅ Built-in | ❌ |
| Colored bot buttons | ✅ Bot API 9.4 | — |
| Split-tunnel | ✅ Domain + IP | ✅ |
| Auto-update | ✅ | ✅ |
| Migrate from Kvass | ✅ Automatic | — |
| Open source | ✅ | ✅ |

---

## 🔧 Requirements

- **Router:** Keenetic (any model with Entware support)
- **Entware:** [Installation guide](https://help.keenetic.com/hc/en-us/articles/360021214160)
- **VLESS server:** Subscription at [kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register) or your own server

---

## 📂 File Structure on Router

```
/opt/
├── bin/
│   ├── kox              ← CLI management tool
│   └── kox-bot          ← Telegram bot daemon
├── etc/
│   ├── xray/
│   │   ├── config.json  ← Xray config (VLESS + routing rules)
│   │   └── kox.conf     ← Server params + bot token
│   ├── ndm/netfilter.d/
│   │   └── 99-kox-nat.sh  ← iptables rules (auto-applied on boot)
│   └── init.d/
│       ├── S24xray      ← Xray service (autostart)
│       └── S90kox-bot   ← Telegram bot service (autostart)
└── var/log/
    ├── xray-err.log     ← Xray error log
    └── kox-bot.log      ← Bot log
```

---

## ❓ FAQ

**Q: YouTube doesn't work after installation**
```bash
kox status   # Everything green?
kox log      # Any errors?
kox test     # Config valid?
```

**Q: How to add a site that's not working?**
```bash
kox add site.com   # Xray restarts automatically
```

**Q: How to temporarily disable VPN (e.g. for banking)?**
```bash
kox off   # Traffic goes direct, Xray keeps running
kox on    # Re-enable
```

**Q: How to update server parameters?**
```bash
kox update-sub   # Updates from subscription, restarts Xray
```

**Q: Bot is not responding**
```bash
kox bot
/opt/etc/init.d/S90kox-bot restart
tail -20 /opt/var/log/kox-bot.log
```

---

## 📄 License

MIT License — free to use, attribution appreciated.

---

<div align="center">

**[🌐 kox.nonamenebula.ru](https://kox.nonamenebula.ru/register)** · **[📢 Telegram](https://t.me/PrivateProxyKox)** · **[🤖 Bot](https://t.me/kox_nonamenebula_bot)**

</div>
