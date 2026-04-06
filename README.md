<p align="center">
  <img src="./docs/tgdb.png" alt="TGDB logo" width="220">
</p>

<h1 align="center">TGDB</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/Container-Podman-892CA0?style=for-the-badge&logo=podman&logoColor=white" alt="Podman">
  <img src="https://img.shields.io/badge/Systemd-Quadlet-000000?style=for-the-badge&logo=linux&logoColor=white" alt="Quadlet">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge" alt="Apache 2.0 License">
</p>

<p align="center">
  <strong>一站式 Linux VPS 管理與容器化應用部署框架</strong>
</p>

<p align="center">
  <em>純 Bash 實現 • Rootless / Rootful 容器 • Quadlet 驅動 • 交互式與 CLI 雙模式</em>
</p>

<p align="center">
  <strong>繁體中文</strong> •
  <a href="./docs/README.en.md">English</a>
</p>

<p align="center">
  <a href="#-快速開始">快速開始</a> •
  <a href="#-特色亮點">特色亮點</a> •
  <a href="#-支援的應用">支援應用</a> •
  <a href="#-使用方式">使用方式</a> •
  <a href="#disclaimer">免責聲明</a>
</p>

---

## ✨ 特色亮點

<table>
  <tr>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🔧-純%20Bash-4EAA25?style=flat-square" alt="Pure Bash">
      <br><strong>純 Bash 實現</strong>
      <br><sub>無需額外依賴，開箱即用</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🎮-雙模式-blue?style=flat-square" alt="Dual Mode">
      <br><strong>雙模式操作</strong>
      <br><sub>直覺互動選單 + 強大 CLI 咒語</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🔒-Rootless%20%2F%20Rootful-892CA0?style=flat-square" alt="Rootless / Rootful">
      <br><strong>Rootless / Rootful 容器</strong>
      <br><sub>預設 rootless；需要系統權限時可選 rootful</sub>
    </td>
    <td align="center" width="25%">
      <img src="https://img.shields.io/badge/🌐-跨發行版-orange?style=flat-square" alt="Cross-distro">
      <br><strong>跨發行版支援</strong>
      <br><sub>apt/dnf/yum/zypper/pacman</sub>
    </td>
  </tr>
</table>

### 核心能力

| 🎯 功能類別 | 📝 具體說明 |
|:----------:|:----------|
| **容器化應用** | 內建 100+ 個 App Spec，涵蓋媒體、AI、知識管理、監控、資料庫與網路服務（預設 rootless；部分應用支援 rootful） |
| **安全堆疊** | nftables 防火牆 + Fail2ban 入侵防護，完整安全防護 |
| **自動備份** | 冷備份/還原、Kopia 熱備、Rclone 遠端同步、systemd timer 排程 |
| **雲端儲存** | Rclone 整合，支援各大雲端服務掛載 |
| **反向代理** | Nginx 容器化管理、SSL 自動續簽、Cloudflare Real-IP、WAF（ModSecurity + OWASP CRS） |
| **定時任務** | 內建備份、DB 匯出、Kopia、Nginx 任務，並支援自訂腳本與 Healthchecks 通知 |
| **進階應用** | Cloudflare Tunnel、Headscale / DERP、數據庫管理、Game Server（LinuxGSM） |

---

## 🚀 快速開始

### 安裝與執行提醒

> ✅ **推薦環境**
>
> - 推薦使用 **Debian 13**
> - 請使用 **帶有 sudo 權限的普通用戶** 執行 TGDB
> - **不建議直接以 root 使用者啟動**，Rootless Podman、`systemd --user`、快捷鍵與部分目錄權限流程都會以一般使用者環境為主
> - 即使要部署 rootful Apps，也建議維持以一般使用者執行 TGDB，並讓 TGDB 透過 `sudo` 進行 system scope 操作

### 系統需求

| 項目 | 需求 |
|------|------|
| **作業系統** | Linux（推薦 Debian 13；亦支援 Debian/Ubuntu、RHEL/CentOS/Fedora、openSUSE、Arch） |
| **權限** | 請使用具 sudo 權限的普通用戶執行（系統層級操作會透過 sudo 完成） |
| **Shell** | Bash 4.0+ |
| **Podman** | 4.4+（容器化功能建議版本，TGDB 可協助安裝） |

### 安裝與執行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tgdb77/tgdb/main/install.sh)
```

> 安裝器會使用「目前所在目錄」，建議先進入你要安裝 TGDB 的資料夾再執行。
> 執行後會在目前目錄建立 `tgdb/`，並自動進入執行 `./tgdb.sh`。

> 💡 **注意**
>
> - TGDB 會在首次互動模式啟動時，嘗試自動建立預設快捷鍵 `t`（`/usr/local/bin/t`）；後續可透過 `9. 快捷鍵管理` 維護。
> - 首次使用若涉及安裝套件、建立快捷鍵、調整系統設定或防火牆規則，會需要輸入 `sudo` 密碼。

---

## 🎮 使用方式

### 🖥️ 交互式選單模式

啟動 TGDB 即進入直覺的交互式選單：

```bash
./tgdb.sh
# 或設定快捷鍵後
t
```

<details>
<summary>📋 <b>點擊展開主選單結構</b></summary>

```
❖ TGDB 管理系統 ❖
══════════════════════════════════════════
 1. 系統資訊        → 檢視系統狀態摘要
 2. 系統維護        → 跨發行版套件更新與清理
 3. 系統管理        → 用戶/SSH/DNS/Swap 等設定
 4. 基礎工具管理    → 常用工具一鍵安裝
 5. Podman 管理     → 容器引擎與 Quadlet 操作
 6. 應用程式管理    → 容器化應用部署
 7. 進階應用        → Rclone / Nginx / tmux / Tunnel / DB / Game Server
 8. 第三方腳本      → 實用的第三方腳本
 9. 快捷鍵管理      → 自訂執行快捷鍵
10. 全系統備份管理  → 冷備份 / 還原 / 自動備份 / Kopia
11. 定時任務管理    → 備份 / DB / Nginx / 自訂 timer / Healthchecks
══════════════════════════════════════════
777. 快速環境設定    → 快速設定新環境
00. 更新系統        → Git pull 更新 TGDB
 0. 退出
══════════════════════════════════════════
```

</details>

### ⚡ CLI 咒語模式

直接在終端執行操作，適合腳本編排與自動化：

```bash
# 語法範例
./tgdb.sh <主選單> <次選單> <子選單> [參數...]

# 查看可用咒語說明
./tgdb.sh -h

# 安裝所有基礎工具
./tgdb.sh 4 1

# 快速部署應用（<idx> 依互動選單中的應用排序）
./tgdb.sh 6 <idx> 1 <name|0> <port|0> [額外參數...]

# Rclone 掛載
./tgdb.sh 7 1 4 remote:/path /mnt/cloud

# 建立系統備份
./tgdb.sh 10 1
```

> 💡 `8. 第三方腳本` 與 `11. 定時任務管理` 目前以互動模式為主；若需要完整功能，請直接執行 `./tgdb.sh` 進入選單。

<details>
<summary>📖 <b>常用咒語對照表</b></summary>

| 咒語 | 功能說明 |
|:----:|:---------|
| `t 1` | 顯示系統資訊 |
| `t 2` | 執行系統維護 |
| `t 4 1` | 安裝所有基礎工具 |
| `t 5 1` | 安裝 Podman |
| `t 5 8 <container>` | 進入指定容器 Shell |
| `t 6 X 1 <...>` | 部署指定應用程式 |
| `t 7 1 1` | 安裝/更新 Rclone |
| `t 10 1` | 建立備份 |
| `t 10 2` | 還原最新備份 |

</details>

---

## 📱 支援的應用

TGDB 使用 **Podman + Quadlet** 實現 **rootless / rootful** 容器化部署（預設 rootless），目前內建 **100+ 個 App Spec**：

<table>
  <tr>
    <td>📦 <b>儲存與同步</b></td>
    <td>OpenList • SeaweedFS • Syncthing • Gokapi • Kopia</td>
  </tr>
  <tr>
    <td>🎬 <b>媒體與下載</b></td>
    <td>Immich • Jellyfin • Navidrome • qBittorrent • Pinchflat • JDownloader 2 </td>
  </tr>
  <tr>
    <td>📝 <b>生產力與內容</b></td>
    <td>Outline • Linkwarden • Memos • Vikunja • Stirling PDF • Paperless-ngx • Excalidraw • IT-Tools • Ghost • WordPress • Kutt</td>
  </tr>
  <tr>
    <td>🤖 <b>自動化與 AI</b></td>
    <td>n8n • Open WebUI • Ollama • GPTLoad • New API • CLI Proxy API • SillyTavern • Chromium • Webtop • Homepage</td>
  </tr>
  <tr>
    <td>📊 <b>監控與通知</b></td>
    <td>Uptime Kuma • Healthchecks • Gotify • Beszel • Beszel Agent • Changedetection.io • Umami • RSS Stack</td>
  </tr>
  <tr>
    <td>🗄️ <b>資料庫與管理</b></td>
    <td>PostgreSQL • Redis • pgAdmin • RedisInsight • Portainer • Gitea</td>
  </tr>
  <tr>
    <td>🔐 <b>安全、搜尋與生活</b></td>
    <td>Vaultwarden • Authentik • AdGuard Home • SearXNG • Whoogle • Firefly III • Ghostfolio • Wallos</td>
  </tr>
</table>

> 📝 實際可用清單以目前版本選單為準；CLI 的 `<idx>` 請以互動選單中的應用排序為準

### 部署範例

```bash
# 互動式部署
./tgdb.sh
# 選擇 6 → 選擇應用 → 1. 部署 → 依提示填入參數

# CLI 快速部署（使用預設值）
./tgdb.sh                              # 先用互動選單確認應用排序
./tgdb.sh 6 <idx> 1 0 0 [額外參數...]  # 0 代表使用預設值
```

### `主選單 6` 的 rootful Apps 說明

- TGDB 目前在 `主選單 6` 已支援 **rootless / rootful** 兩種 Apps 部署模式，但仍以 rootless 為預設。
- 只有 AppSpec 明確宣告支援 rootful 的應用，才會在部署流程中提供 rootful 選項。
- rootful 部署會使用 `sudo`、system scope Quadlet 與獨立 runtime 目錄：
  - 單元路徑：`/etc/containers/systemd`
  - 資料路徑：`/var/lib/tgdb`
  - Podman socket：`/run/podman/podman.sock`
- 同一個實例名稱不可同時存在 rootless 與 rootful 版本。
- 實例建立後不可直接「原地切換」部署模式（需移除後重新部署）。
- 目前 TGDB 的「備份/還原」與「定時任務（.timer）」流程尚未納入 rootful Apps（以 rootless 為主）。

---

## 🛡️ 安全功能

### 🔥 防火牆管理（nftables）

- ✅ 安全預設規則（input drop 策略）
- ✅ Docker/Podman/Quadlet 容器相容
- ✅ IPv4/IPv6 雙棧支援
- ✅ 白名單/黑名單管理
- ✅ SSH 埠自動追蹤

### 🚫 入侵防護（Fail2ban）

- ✅ SSH 暴力破解防護
- ✅ Nginx 惡意請求攔截
- ✅ 與 nftables 無縫整合
- ✅ 即時監控與日誌查看

---

## 🌐 進階功能

### 雲端儲存（Rclone）

```bash
./tgdb.sh 7 1 1              # 安裝/更新 Rclone
./tgdb.sh 7 1 3              # 編輯配置檔
./tgdb.sh 7 1 4 myremote:/ /mnt/cloud  # 掛載遠端儲存
./tgdb.sh 7 1 5 /mnt/cloud   # 卸載
```

### 反向代理（Nginx）

容器化 Nginx 管理，支援：

- 反向代理站 / 靜態站快速建立
- 指定站點憑證更新與自備憑證匯入
- 日誌追蹤
- 自動任務（SSL 續簽 / Cloudflare Real-IP / WAF CRS 更新）
- WAF（ModSecurity + OWASP CRS）

### 網路組建

- **Cloudflare Tunnel**：安全暴露服務至公網
- **Headscale**：自建 Tailscale 控制伺服器
- **Tailscale**：點對點安全網路
- **DERP**：自建 Tailscale 中繼伺服器

### 數據庫與遊戲服務

- **數據庫管理**：可部署 `pgAdmin 4`、`RedisInsight`，並支援 PostgreSQL / Redis / MySQL 熱備份、還原、批次匯出與定時備份
- **Game Server（LinuxGSM）**：可部署 LinuxGSM / docker-gameserver 類型的遊戲伺服器，並提供日誌與維運命令入口

### 定時任務中心

主選單 `11. 定時任務管理` 會集中管理 TGDB 的 `systemd --user` 任務，目前包含：

- 自動備份
- 數據庫批次匯出
- Kopia 統一備份
- Nginx SSL 續簽
- Cloudflare Real-IP 更新
- WAF CRS 規則更新
- 自訂定時任務腳本
- Healthchecks Ping 通知整合

```bash
./tgdb.sh
# 選擇 11 → 選擇任務 → 調整排程 / 立即執行 / Healthchecks
```

---

## 💾 備份與還原

TGDB 提供完整的配置備份機制，預設備份策略為**冷備份**，會先停用相關服務再打包，降低 Postgres / SQLite 類資料不一致風險：

```bash
# 手動建立備份
./tgdb.sh 10 1

# 還原最新備份
./tgdb.sh 10 2

# 設定自動備份（透過選單）
./tgdb.sh
# 選擇 10 → 3
```

**備份範圍**：
- `TGDB_DIR` — 應用程式資料
- Quadlet 單元檔案
- TGDB 管理的 `systemd --user` timer / service
- nftables/Fail2ban 規則
- TGDB 持久化設定（含 timer 與部分模組設定）

**備份特性**：

- 最多保留 3 份本地備份
- 還原後會同步回填 Quadlet 與 timer 單元，並重新啟用
- 可選擇在每次備份後自動同步到 Rclone 遠端
- 新環境還原時，建議使用與原環境相同的使用者名稱

### Kopia（快照備份 / 加密 / 不停機）

TGDB 提供 Kopia 整合選項（Quadlet 部署），並提供「統一備份流程」：

- DB 熱備份（PostgreSQL/Redis dump）→ 產生到各實例的 `db-dump/`
- Kopia 建立快照（預設自動排除 DB data 目錄，避免快照不一致）

入口：

```bash
./tgdb.sh
# 選擇 10 → 4（Kopia 管理）
```

---

## 📦 系統架構

```
tgdb/
├── 🚀 tgdb.sh              # 主入口腳本
├── 📁 src/                  # 功能模組
│   ├── core/               # 核心共用層
│   ├── apps/               # 應用部署模組（動態探索）
│   ├── advanced/           # 進階應用模組
│   ├── system/             # 系統管理子模組
│   ├── timer/              # 定時任務 / Healthchecks / 自訂 timer
│   └── *.sh                # 各功能模組
└── 📁 config/               # App Spec、服務樣板與 Quadlet 單元
```

---

## 🔧 更新與維護

```bash
# 透過選單自動更新
./tgdb.sh
# 選擇 00

# 或手動 Git 更新
cd /path/to/tgdb
git pull --ff-only origin main
```

---

<a id="disclaimer"></a>
## ⚠️ 免責聲明

### 重要警告

> **請在使用本工具前仔細閱讀以下條款。使用本軟體即表示您同意以下所有條款。**

1. **風險自負**
   - 本軟體按「現狀」（AS IS）提供，不提供任何形式的明示或暗示擔保。
   - 使用者須對使用本軟體所造成的任何後果負全部責任。
   - **強烈建議在生產環境使用前先在測試環境中充分驗證。**

2. **資料安全**
   - 本軟體涉及系統層級操作，包括但不限於：防火牆規則修改、SSH 配置變更、容器管理、檔案系統掛載等。
   - **使用前請務必備份重要資料。**
   - 作者及貢獻者不對任何資料遺失、系統損壞或安全事件負責。

3. **第三方服務**
   - 本軟體整合多種第三方工具與服務（Podman、Rclone、Docker 映像等）。
   - 這些第三方組件的安全性、可用性與相容性不在本專案的保證範圍內。
   - 各第三方軟體、映像、名稱與商標之著作權及相關權利，均屬其原權利人所有。
   - 本專案不主張取得或轉授權該等權利；使用者於下載、部署、修改或再散布前，應自行確認並遵循各元件授權條款（含必要之 LICENSE/NOTICE 保留要求）。
   - 請自行評估並遵守各第三方服務的使用條款。

4. **安全性考量**
   - 本軟體需要 sudo 權限執行部分操作，請確保您了解這些操作的影響。
   - 預設配置可能不適合所有安全需求，請根據實際環境調整。
   - 定期更新本軟體及相關依賴以獲取安全修補。

5. **專案定位（Vibe Coding）**
   - 本專案為全 Vibe Coding 驅動的個人工程實作，優先解決作者自身的真實需求。
   - 不承諾覆蓋所有使用情境，也不保證符合企業級流程或治理標準。
   - 若您選擇導入於自身環境，請自行完成評估、調整與風險控管。

6. **適用場景**
   - 本軟體主要設計用於個人 VPS 管理與學習目的。
   - 在企業環境或關鍵業務系統中使用前，請諮詢專業人士並進行完整的安全評估。

7. **無擔保聲明**
   - 作者及貢獻者不保證本軟體無錯誤、無中斷運行，或適合特定用途。
   - 對於使用本軟體導致的任何直接、間接、附帶、特殊或後果性損害，作者及貢獻者概不負責。

### 使用建議

- 🔹 首次使用請在**非生產環境**測試
- 🔹 執行系統管理操作前**建立備份**
- 🔹 仔細閱讀每個操作的說明與警告
- 🔹 定期檢查並更新至最新版本
- 🔹 如有疑問，請先查閱文件或提出 Issue

---

## 📝 授權條款

本專案採用 **Apache 2.0 授權條款**。詳見 [LICENSE](./LICENSE) 文件。

---

<p align="center">
  <strong>🌟 如果這個專案對您有幫助，請給個 Star！🌟</strong>
</p>

<p align="center">
  Made with ❤️ for the Linux community
</p>
