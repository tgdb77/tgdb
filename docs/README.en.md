<p align="center">
  <img src="./tgdb.png" alt="TGDB logo" width="220">
</p>

<h1 align="center">TGDB</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/Container-Podman-892CA0?style=for-the-badge&logo=podman&logoColor=white" alt="Podman">
  <img src="https://img.shields.io/badge/Systemd-Quadlet-000000?style=for-the-badge&logo=linux&logoColor=white" alt="Quadlet">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
</p>

<p align="center">
  <strong>All-in-one Linux VPS management and containerized application deployment framework</strong>
</p>

<p align="center">
  <em>Pure Bash • Rootless Containers • Quadlet Powered • Interactive + CLI Modes</em>
</p>

<p align="center">
  <a href="../README.md">繁體中文</a> •
  <strong>English</strong>
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-highlights">Highlights</a> •
  <a href="#-supported-applications">Supported Applications</a> •
  <a href="#-usage">Usage</a> •
  <a href="#disclaimer">Disclaimer</a>
</p>

---

## ✨ Highlights

<table>
  <tr>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🔧-Pure%20Bash-4EAA25?style=flat-square" alt="Pure Bash">
      <br><strong>Pure Bash</strong>
      <br><sub>No heavyweight runtime required</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🎮-Dual%20Mode-blue?style=flat-square" alt="Dual Mode">
      <br><strong>Dual Mode</strong>
      <br><sub>Interactive menu + CLI spell mode</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🔒-Rootless-892CA0?style=flat-square" alt="Rootless">
      <br><strong>Rootless Containers</strong>
      <br><sub>Safer deployment with Podman + Quadlet</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🌐-Cross%20Distro-orange?style=flat-square" alt="Cross-distro">
      <br><strong>Cross-distro Support</strong>
      <br><sub>apt/dnf/yum/zypper/pacman</sub>
    </td>
  </tr>
</table>

### Core Capabilities

| Feature Area | Details |
|:------------:|:--------|
| **Containerized Apps** | Built-in support for 100+ app specs across media, AI, knowledge management, monitoring, databases, and network services |
| **Security Stack** | nftables firewall + Fail2ban intrusion protection |
| **Automated Backups** | Cold backup/restore, Kopia hot backup, Rclone sync, and systemd timer scheduling |
| **Cloud Storage** | Rclone integration for mounting and syncing cloud storage |
| **Reverse Proxy** | Containerized Nginx with SSL renewal, Cloudflare Real-IP updates, and WAF support |
| **Timers** | Built-in backup, DB export, Kopia, and Nginx tasks, plus custom scripts and Healthchecks integration |
| **Advanced Modules** | Cloudflare Tunnel, Headscale / DERP, database management, and LinuxGSM game server support |

---

## 🚀 Quick Start

### Installation Notes

> ✅ **Recommended environment**
>
> - Recommended OS: **Debian 13**
> - Run TGDB with a **regular user that has sudo privileges**
> - **Do not launch it directly as root** unless you really know what you are doing. Rootless Podman, `systemd --user`, shortcut creation, and part of the directory ownership flow are designed around a normal user environment

### Requirements

| Item | Requirement |
|------|-------------|
| **Operating System** | Linux (Debian 13 recommended; Debian/Ubuntu, RHEL/CentOS/Fedora, openSUSE, Arch, are also supported) |
| **Privileges** | Use a regular user with sudo privileges for system-level operations |
| **Shell** | Bash 4.0+ |
| **Podman** | 4.4+ recommended for containerized features; TGDB can help install it |

### Installation and Launch

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tgdb77/tgdb/main/install.sh)
```

> The installer uses your current working directory. `cd` into the target folder before running it.
> It creates a `tgdb/` folder in the current directory, then runs `./tgdb.sh` automatically.

> 💡 **Notes**
>
> - On the first interactive launch, TGDB may try to create the default shortcut `t` at `/usr/local/bin/t`. You can manage it later from `9. Shortcut Management`.
> - The first run may ask for your `sudo` password when installing packages, creating shortcuts, changing system settings, or updating firewall rules.

---

## 🎮 Usage

### 🖥️ Interactive Menu Mode

Run TGDB to enter the interactive menu:

```bash
./tgdb.sh
# or, after the shortcut is created
t
```

<details>
<summary>📋 <b>Show Main Menu Structure</b></summary>

```text
❖ TGDB Management System ❖
══════════════════════════════════════════
 1. System Info           → View system status summary
 2. System Maintenance    → Cross-distro package update and cleanup
 3. System Management     → Users / SSH / DNS / Swap and more
 4. Base Tools            → One-click install of common tools
 5. Podman Management     → Container engine and Quadlet operations
 6. Application Manager   → Containerized app deployment
 7. Advanced Modules      → Rclone / Nginx / tmux / Tunnel / DB / Game Server
 8. Third-party Scripts   → Handy external tools
 9. Shortcut Management   → Manage command shortcuts
10. Full Backup Manager   → Cold backup / restore / auto backup / Kopia
11. Timer Management      → Backup / DB / Nginx / custom timer / Healthchecks
══════════════════════════════════════════
777. Quick Environment Setup → Bootstrap a fresh environment
00. Update System            → Git pull update for TGDB
 0. Exit
══════════════════════════════════════════
```

</details>

### ⚡ CLI Spell Mode

Use TGDB directly from the terminal for scripting and automation:

```bash
# Generic syntax
./tgdb.sh <main-menu> <sub-menu> <action> [args...]

# Show CLI help
./tgdb.sh -h

# Install all base tools
./tgdb.sh 4 1

# Quick deploy an app (<idx> follows the order shown in the interactive app menu)
./tgdb.sh 6 <idx> 1 <name|0> <port|0> [extra args...]

# Mount Rclone storage
./tgdb.sh 7 1 4 remote:/path /mnt/cloud

# Create a system backup
./tgdb.sh 10 1
```

> 💡 `8. Third-party Scripts` and `11. Timer Management` are currently intended for interactive use. For full functionality, launch `./tgdb.sh` and use the menu.

<details>
<summary>📖 <b>Common CLI Examples</b></summary>

| Command | Description |
|:-------:|:------------|
| `t 1` | Show system information |
| `t 2` | Run system maintenance |
| `t 4 1` | Install all base tools |
| `t 5 1` | Install Podman |
| `t 5 8 <container>` | Open a shell inside a container |
| `t 6 X 1 <...>` | Deploy a specific application |
| `t 7 1 1` | Install or update Rclone |
| `t 10 1` | Create a backup |
| `t 10 2` | Restore the latest backup |

</details>

---

## 📱 Supported Applications

TGDB uses **Podman + Quadlet** for rootless container deployment and currently includes **100+ app specs**:

<table>
  <tr>
    <td>📦 <b>Storage & Sync</b></td>
    <td>OpenList • SeaweedFS • Syncthing • Gokapi • Kopia</td>
  </tr>
  <tr>
    <td>🎬 <b>Media & Downloads</b></td>
    <td>Immich • Jellyfin • Navidrome • qBittorrent • Pinchflat • JDownloader 2 </td>
  </tr>
  <tr>
    <td>📝 <b>Productivity & Content</b></td>
    <td>Outline • Linkwarden • Memos • Vikunja • Stirling PDF • Paperless-ngx • Excalidraw • IT-Tools • Ghost • WordPress • Kutt</td>
  </tr>
  <tr>
    <td>🤖 <b>Automation & AI</b></td>
    <td>n8n • Open WebUI • Ollama • GPTLoad • New API • CLI Proxy API • SillyTavern • Chromium • Webtop • Homepage</td>
  </tr>
  <tr>
    <td>📊 <b>Monitoring & Notifications</b></td>
    <td>Uptime Kuma • Healthchecks • Gotify • Beszel • Beszel Agent • Changedetection.io • Umami • RSS Stack</td>
  </tr>
  <tr>
    <td>🗄️ <b>Databases & Management</b></td>
    <td>PostgreSQL • Redis • pgAdmin • RedisInsight • Portainer • Gitea</td>
  </tr>
  <tr>
    <td>🔐 <b>Security, Search & Personal Use</b></td>
    <td>Vaultwarden • Authentik • AdGuard Home • SearXNG • Whoogle • Firefly III • Ghostfolio • Wallos</td>
  </tr>
</table>

> 📝 The exact available list depends on the current version. For CLI deployment, use the order shown in the interactive app menu for `<idx>`.

### Deployment Example

```bash
# Interactive deployment
./tgdb.sh
# Choose 6 → choose an app → 1. Deploy → follow the prompts

# CLI quick deployment with defaults
./tgdb.sh                              # first confirm the app order in the interactive menu
./tgdb.sh 6 <idx> 1 0 0 [extra args...]  # 0 means use the default value
```

---

## 🛡️ Security Features

### 🔥 Firewall Management (nftables)

- Secure default rule set (`input drop`)
- Compatible with Docker / Podman / Quadlet
- IPv4 / IPv6 dual-stack support
- Allowlist / blocklist management
- Automatic SSH port tracking

### 🚫 Intrusion Protection (Fail2ban)

- SSH brute-force protection
- Nginx bad request blocking
- Tight nftables integration
- Real-time monitoring and log inspection

---

## 🌐 Advanced Features

### Cloud Storage (Rclone)

```bash
./tgdb.sh 7 1 1              # Install/update Rclone
./tgdb.sh 7 1 3              # Edit config
./tgdb.sh 7 1 4 myremote:/ /mnt/cloud  # Mount remote storage
./tgdb.sh 7 1 5 /mnt/cloud   # Unmount
```

### Reverse Proxy (Nginx)

The containerized Nginx manager supports:

- Fast setup for reverse proxy sites and static sites
- Per-site certificate renewal and custom certificate import
- Log tracking
- Automated tasks for SSL renewal, Cloudflare Real-IP updates, and WAF CRS updates
- WAF support with ModSecurity + OWASP CRS

### Networking

- **Cloudflare Tunnel**: securely expose services to the public internet
- **Headscale**: self-hosted Tailscale control server
- **Tailscale**: secure peer-to-peer networking
- **DERP**: self-hosted Tailscale relay server

### Database and Game Services

- **Database Management**: deploy `pgAdmin 4` and `RedisInsight`, plus PostgreSQL / Redis / MySQL export, restore, batch export, and scheduled backup flows
- **Game Server (LinuxGSM)**: deploy LinuxGSM / docker-gameserver based game servers with logs and maintenance commands

### Timer Center

Main menu `11. Timer Management` centralizes TGDB-managed `systemd --user` tasks, including:

- Auto backup
- Batch database export
- Kopia unified backup
- Nginx SSL renewal
- Cloudflare Real-IP update
- WAF CRS rule update
- Custom timer scripts
- Healthchecks ping notifications

```bash
./tgdb.sh
# Choose 11 → choose a task → adjust schedule / run now / Healthchecks
```

---

## 💾 Backup and Restore

TGDB includes a full backup system. By default it uses **cold backups**, stopping related services before packaging data to reduce inconsistency risks for PostgreSQL / SQLite style workloads:

```bash
# Create a manual backup
./tgdb.sh 10 1

# Restore the latest backup
./tgdb.sh 10 2

# Configure scheduled backups from the menu
./tgdb.sh
# Choose 10 → 3
```

**Backup scope**:

- `TGDB_DIR` application data
- Quadlet unit files
- TGDB-managed `systemd --user` timer / service units
- nftables / Fail2ban rules
- TGDB persistent configuration, including timer-related settings

**Backup characteristics**:

- Keeps up to 3 local backups
- Restore syncs Quadlet and timer units back into place and re-enables them
- Optional automatic Rclone sync after each backup
- When restoring onto a new system, it is recommended to use the same username as the source environment

### Kopia (Snapshots / Encryption / No Full Downtime)

TGDB also provides a Kopia integration (deployed with Quadlet) for a unified backup flow:

- DB hot backup first (PostgreSQL / Redis dumps into each instance's `db-dump/`)
- Kopia snapshot creation with DB data directories excluded by default to avoid inconsistent snapshots

Entry point:

```bash
./tgdb.sh
# Choose 10 → 4 (Kopia Management)
```

---

## 📦 Project Structure

```text
tgdb/
├── 🚀 tgdb.sh              # Main entry script
├── 📁 src/                  # Feature modules
│   ├── core/               # Core shared layer
│   ├── apps/               # App deployment modules (dynamic discovery)
│   ├── advanced/           # Advanced modules
│   ├── system/             # System management modules
│   ├── timer/              # Timers / Healthchecks / custom timers
│   └── *.sh                # Other feature modules
└── 📁 config/               # App specs, templates, and Quadlet units
```

---

## 🔧 Update and Maintenance

```bash
# Update from the menu
./tgdb.sh
# Choose 00

# Or update manually via Git
cd /path/to/tgdb
git pull --ff-only origin main
```

---

<a id="disclaimer"></a>
## ⚠️ Disclaimer

### Important Notice

> **Please read the following terms carefully before using this project. By using this software, you agree to all of the terms below.**

1. **Use at your own risk**
   - This software is provided on an "AS IS" basis without warranties of any kind.
   - You are fully responsible for any consequences caused by using this software.
   - **Strongly test in a non-production environment before using it in production.**

2. **Data safety**
   - This software performs system-level operations, including but not limited to firewall changes, SSH configuration updates, container management, and filesystem mounts.
   - **Back up important data before use.**
   - The authors and contributors are not responsible for data loss, system damage, or security incidents.

3. **Third-party services**
   - This project integrates multiple third-party tools and services such as Podman, Rclone, and container images.
   - The security, availability, and compatibility of those third-party components are outside the guarantee scope of this project.
   - All copyrights and related rights for third-party software, images, names, and trademarks remain with their respective rights holders.
   - This project does not claim ownership of, or re-license, those rights. Before downloading, deploying, modifying, or redistributing any component, you are responsible for verifying and complying with its license terms, including required LICENSE/NOTICE preservation obligations.
   - Please evaluate them yourself and comply with their terms of use.

4. **Security considerations**
   - Some operations require sudo privileges. Make sure you understand the impact before running them.
   - Default settings may not fit every environment. Review and adjust them according to your needs.
   - Keep this project and related dependencies updated to receive security fixes.

5. **Project Positioning (Vibe Coding)**
   - This project is a fully vibe-coded personal engineering build, created to solve the author's real-world needs first.
   - It does not aim to cover every scenario or guarantee alignment with enterprise governance and workflow standards.
   - If you choose to adopt it, you are responsible for your own evaluation, adaptation, and risk control.

6. **Use cases**
   - This project is mainly designed for personal VPS management and learning purposes.
   - For enterprise or mission-critical environments, consult professionals and perform a full security review before use.

7. **No warranty**
   - The authors and contributors do not guarantee that this software is error-free, uninterrupted, or fit for a particular purpose.
   - They are not liable for any direct, indirect, incidental, special, or consequential damages caused by the use of this software.

### Recommendations

- Test in a **non-production environment** before first use
- **Create backups** before performing system management tasks
- Read each prompt and warning carefully
- Keep the project updated regularly
- Open an Issue if you find unclear behavior or documentation gaps

---

## 📝 License

This project is released under the **Apache 2.0 License**. See [LICENSE](../LICENSE) for details.

---

<p align="center">
  <strong>🌟 If this project helps you, please consider giving it a Star! 🌟</strong>
</p>

<p align="center">
  Made with ❤️ for the Linux community
</p>
