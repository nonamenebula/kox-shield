<div align="center">

```
  ██╗  ██╗  ██████╗  ██╗  ██╗
  ██║ ██╔╝  ██╔══██╗ ╚██╗██╔╝
  █████╔╝   ██║  ██║  ╚███╔╝ 
  ██╔═██╗   ██║  ██║  ██╔██╗ 
  ██║  ██╗  ╚██████╔╝██╔╝ ██╗
  ╚═╝  ╚═╝   ╚═════╝  ╚═╝  ╚═╝
```

**KOX Shield — smart traffic encryption for Keenetic routers (VLESS/Reality + Hysteria2)**

[![Version](https://img.shields.io/badge/version-2026.06.07-blue)](CHANGELOG.md)
[![Telegram](https://img.shields.io/badge/Telegram-Channel-blue?logo=telegram)](https://t.me/PrivateProxyKox)
[![Bot](https://img.shields.io/badge/Telegram-Bot-blue?logo=telegram)](https://t.me/kox_nonamenebula_bot)
[![Site](https://img.shields.io/badge/🛡️-kox.nonamenebula.ru-blue)](https://kox.nonamenebula.ru/register)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

🌐 **Language / Язык:** [Русский](README.md) · **English**

</div>

---

## 🚀 What is KOX Shield?

**KOX Shield** is a fully automated VPN tunnel setup for Keenetic routers with two protocols: **VLESS/Reality** and **Hysteria2**. Traffic to selected sites goes through the VPN; everything else goes directly through your ISP. No manual configuration needed.

> ✅ **Migrating from Kvass?** The installer automatically detects and cleanly removes Kvass, Shadowsocks, and sing-box before setting up KOX Shield — just answer "yes" when prompted.

### ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔀 **Smart encryption** | Only selected sites through VPN, everything else direct |
| ⚡ **VLESS + Reality** | Modern protocol — invisible to ISP and DPI |
| 🚀 **Hysteria2 (QUIC)** | Fast UDP protocol with Salamander obfuscation — stable where TCP is throttled |
| 🔁 **Both protocols in one subscription** | A subscription can mix VLESS and Hysteria2; the router switches between them correctly |
| 📱 **Telegram Bot** | Full router management from Telegram |
| 💻 **KOX Console** | Router CLI — `kox status`, `kox add`, `kox list`... |
| 🔄 **Auto-update** | Daily subscription parameter refresh |
| 🏠 **Whole network** | Works on all devices once the router is set up |

> 🧩 **How it works:** Xray is always the transparent front-end (iptables intercepts only ports 80/443). For a VLESS server the outbound is native VLESS/Reality; for a Hysteria2 server a local `hysteria` client (SOCKS5 on `127.0.0.1`) is started and Xray routes traffic into it. Switching between protocols is fully automatic — routing rules and domain lists stay unchanged.

---

## 🔑 Getting a Server

### Option 1: KOX Shield Subscription (ready in 1 minute)

Register at **[kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register)** — get a ready subscription with multiple servers (VLESS/Reality and/or Hysteria2), support, and auto-update. The router detects each server's protocol automatically.

### Option 2: Your Own Server

If you have a VPS, set up your own VLESS/Reality or Hysteria2 server. VLESS/Reality example:

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

A **Hysteria2 link** (if you run [Hysteria2](https://v2.hysteria.network/)) looks like:
```
hysteria2://PASSWORD@YOUR-IP:443?obfs=salamander&obfs-password=OBFS-PASS&sni=your.domain#MyServer
```

KOX Shield understands both link formats — pass either one at install time or mix them in a single subscription.

> 💡 More: [Reality](https://github.com/XTLS/REALITY) · [Hysteria2](https://v2.hysteria.network/)

---

## 📦 Installation

### Method 1: Directly on the Router (recommended)

Connect to your router via SSH (port 222) and run one command:

```bash
wget -O /tmp/kox-install.sh https://raw.githubusercontent.com/nonamenebula/kox-shield/main/install.sh && sh /tmp/kox-install.sh
```

> **Requirements:** Keenetic router with [Entware](https://help.keenetic.com/hc/en-us/articles/360021214160) installed

The script will:
- Install `xray-core`, `curl`, `jq`
- Install the `hysteria` client (for Hysteria2 servers) for your architecture
- Ask for your subscription URL or a link (`vless://` or `hysteria2://`)
- Show server selection if multiple servers are available
- **Optionally remove Kvass / Shadowsocks / sing-box** (asks for confirmation first)
- Configure transparent tunnel and iptables rules
- Install the `kox` CLI

### Method 2: From Mac / Linux PC (advanced)

```bash
### Option 2: From Mac/Linux PC

`xraykit.sh` is a thin SSH wrapper that runs the official `install.sh` from GitHub
(VLESS + Hysteria2). Requires `curl`, `sshpass`, and the router root password.

```bash
curl -O https://raw.githubusercontent.com/nonamenebula/kox-shield/main/xraykit.sh
chmod +x xraykit.sh
./xraykit.sh
```

Prefer **Option 1** (install directly on the router).
```

Additionally sets up the Telegram Bot and runs a final tunnel verification.

---

## 🔄 Migrating from Kvass

KOX Shield is a full replacement for Kvass with more modern protocols (VLESS/Reality and Hysteria2 instead of Shadowsocks).

The installer handles migration automatically:
1. Detects installed Kvass, Shadowsocks, or sing-box
2. **Asks for confirmation** before removing anything
3. Cleanly stops services and removes configs
4. Installs KOX Shield with your VLESS subscription

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
kox clear-log           # Clear all logs (Xray + bot)
kox test                # Validate config.json
kox stats               # Traffic statistics
kox server              # Current server parameters (VLESS or Hysteria2)

# Domain category lists
kox list-cats                   # Show all available categories (Telegram, YouTube, ...)
kox list-load telegram          # Load category into tunnel
kox list-load all               # Load all categories at once
kox list-remove telegram        # Remove category from tunnel
kox list-remove all             # Remove all categories
kox list-check                  # Check for list updates on GitHub
kox list-update                 # Download and apply updated lists

# Updates
kox update-sub          # Update server parameters from subscription
kox cron-on             # Enable auto-update (daily at 04:00)
kox cron-off            # Disable auto-update
kox upgrade             # Check for and install KOX Shield updates

# Backups
kox backup              # Backup config.json
kox restore [file]      # Restore from backup

# Telegram Bot
kox bot                 # Bot status
kox admin set <ID>      # Set Telegram administrator
kox admin show          # Show current administrator

# Help
kox help                # List all commands
```

---

## 🤖 Telegram Bot

Manage your router from Telegram without SSH:

```
  ┌─────────────────────────────────────┐
  │  🔑 KOX Shield — Router Management    │
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

## 🆚 KOX Shield vs Kvass

| | KOX Shield | Kvass |
|--|---------|-------|
| Protocol | VLESS/Reality + Hysteria2 | Shadowsocks |
| DPI protection | ✅ Invisible to ISP | ⚠️ Partial |
| Install from router | ✅ `curl \| sh` | ✅ |
| Install from PC | ✅ `xraykit.sh` | ✅ |
| CLI console | ✅ `kox` | ✅ |
| Telegram Bot | ✅ Built-in | ❌ |
| Colored bot buttons | ✅ Bot API 9.4 | — |
| Smart encryption | ✅ Domain + IP | ✅ |
| Auto-update | ✅ | ✅ |
| Migrate from Kvass | ✅ Automatic | — |
| Open source | ✅ | ✅ |

---

## 🔧 Requirements

- **Router:** Keenetic (any model with Entware support)
- **Entware:** [Installation guide](https://help.keenetic.com/hc/en-us/articles/360021214160)
- **Server:** Subscription at [kox.nonamenebula.ru/register](https://kox.nonamenebula.ru/register) or your own VLESS/Reality or Hysteria2 server

---

## 📂 File Structure on Router

```
/opt/
├── bin/
│   ├── kox              ← CLI management tool
│   └── kox-bot          ← Telegram bot daemon
├── sbin/
│   └── hysteria         ← Hysteria2 client (for HY2 servers)
├── etc/
│   ├── xray/
│   │   ├── config.json  ← Xray config (front-end + routing; kox-proxy outbound)
│   │   └── kox.conf     ← Server params, protocol (KOX_PROTO) + bot token
│   ├── hysteria/
│   │   └── client.yaml  ← Hysteria2 client config (when HY2 is active)
│   ├── ndm/netfilter.d/
│   │   └── 99-kox-nat.sh  ← iptables rules (auto-applied on boot)
│   └── init.d/
│       ├── S24xray      ← Xray service (autostart)
│       ├── S25hysteria  ← Hysteria2 client (starts when KOX_PROTO=hysteria2)
│       └── S90kox-bot   ← Telegram bot service (autostart)
└── var/log/
    ├── xray-err.log     ← Xray error log
    └── kox-bot.log      ← Bot log
```

---

## ⬆️ Updating KOX Shield

### Automatically (recommended)

Starting from version `2026.04.13`, the console has a built-in update command:

```bash
kox upgrade
```

It checks the version on GitHub, shows the changelog, and asks for confirmation before downloading and installing new script versions.

---

### Manually (for users on the first version without `kox upgrade`)

If you have an old version and the `kox upgrade` command doesn't exist yet — just update the console with one command via SSH (port 222):

```bash
curl -fsSL https://raw.githubusercontent.com/nonamenebula/kox-shield/main/kox-cli.sh \
  -o /opt/bin/kox && chmod +x /opt/bin/kox && kox upgrade
```

This downloads the new console and immediately runs `kox upgrade`, which updates everything else automatically.

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

**Q: How to update KOX Shield to the latest version?**
```bash
kox upgrade   # Checks for updates, shows what changed, asks for confirmation
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
