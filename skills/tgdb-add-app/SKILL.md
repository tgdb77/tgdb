---
name: tgdb-add-app
description: 將新容器專案整合進 TGDB 的標準流程技能。當使用者貼上專案/文件連結並要求「加入應用」時使用；先判斷應走 AppSpec（主選單 6）或進階應用（主選單 7），可直接融入時立即完成實作與驗證，無法直接融入時提供具體建議與風險評估。
---

# TGDB Add App

## 概覽

使用此流程把新專案整合進 TGDB，並維持既有架構：
- 先做路線判斷（AppSpec 或進階應用）
- 先決定部署模式支援範圍（rootless / rootful）
- 可直接整合就直接改檔與驗證
- 不適合直接整合就先回報建議與取捨

## 步驟 1：判斷整合路線

優先判斷是否可走 AppSpec。

### 1.1 可走 AppSpec（主選單 6）

符合以下多數條件時，直接走 `config/<service>/app.spec`：
- 標準容器部署（image + env + volume + port）
- 可用單容器或固定多單元（`quadlet_type=single|multi`）描述
- 初始化可用 `input=`、`var=`、`config=`、`pre_deploy=`、`post_deploy=` 表達
- 日常維運可用現有通用流程（部署、更新、移除、還原）

### 1.2 應放進進階應用（主選單 7）

出現以下情境時，建議走 `src/advanced/*`：
- 強互動登入授權流程（例如第三方 OAuth 裝置授權）
- 部署後長鏈路維運流程（不只是啟停/更新）
- 需要跨多模組協調（網路、憑證、外部控制面）
- AppSpec 難以維持可讀性與可維護性

### 1.3 部署模式判斷（Rootless vs Rootful）

TGDB Apps 支援兩種部署模式：
- `rootless`：`systemd --user` + `~/.config/containers/systemd`（預設）
- `rootful`：`systemd system` + `/etc/containers/systemd` + root Podman（需要 sudo）

建議在符合以下需求時，將 App 宣告支援/預設 rootful：
- 需要 `Network=host`（LAN 探測、mDNS/SSDP/UDP broadcast 等）
- 需要掛載 `/dev`、`/run/udev`、`/var/log`、`/etc` 等敏感資源
- 需要綁 1024 以下埠（80/443）且不想透過反代
- 需要系統層權限（journald、host metrics、eBPF 等）

AppSpec 相關鍵：
- `deploy_mode_default=inherit|rootless|rootful`
- `compat_deploy_modes=rootless rootful`（未宣告時預設視為 rootless-only，避免誤觸 sudo）

### 1.4 決策輸出規則

- 可融入：直接實作，不只停在建議。
- 不可融入：先回報「為何不適合 AppSpec」與最小可行替代方案，再等使用者確認。

## 步驟 2：蒐集上游部署資訊

優先讀官方文件（部署章節），至少提取以下資訊：
- 容器映像：名稱與 tag 建議
- 容器內埠號與對外埠建議
- 必要環境變數（required）與可選變數
- 需要持久化的路徑（Volume）
- 首次初始化/後置任務需求（migrate/seed/admin init 等）

若資訊不完整，明確標註假設，並使用保守預設。

## 步驟 3：AppSpec 實作（可直接融入時）

在 repo 內新增：
- `config/<service>/app.spec`
- `config/<service>/quadlet/default.container`（或 multi unit）
- `config/<service>/configs/.env.example`（或其他設定模板）
- 若需要：`config/<service>/scripts/*.sh` + `post_deploy=`

### 3.1 app.spec 最低建議欄位

至少設定：
- `spec_version=1`
- `display_name`
- `image`
- `doc_url`
- `menu_order`
- `base_port`
- `instance_subdirs` / `record_subdirs`
- `quadlet_type`
- `quadlet_template`（single）或 `unit=`（multi）

視需求補上：
- `input=`（必要輸入）
- `cli_quick_args=`（CLI 快速部署）
- `var=`（例如 secret）
- `config=`（設定檔模板）
- `volume_dir` 相關欄位（當服務要保存「不需要納入備份」或「大檔案/外部資料」時優先考慮）
- `deploy_mode_default=` / `compat_deploy_modes=`（rootful 支援/預設）
- `success_extra/success_warn`
- `post_deploy=`
- 若需要更完整欄位說明與範例，可直接參考 `src/apps/app.spec.example` 模板

### 3.2 模板建議（避免硬編碼 rootless）

- `PublishPort` 優先綁 `127.0.0.1`
- 若資料屬於「不需要備份」或「大檔案」類型（例如下載、媒體、匯出資料），優先使用 `volume_dir`，不要混放進 instance/record 目錄
- 使用 `volume_dir` 時，記得同步評估 `volume_subdirs`、`cli_quick_args=volume_dir`、`volume_dir_propagation` 與 `selinux_volume_dir`
- 若需要掛載 Podman API socket：
  - 模板請用 `${podman_sock_host_path}`（避免硬寫 `/run/user/.../podman.sock`）
  - rootless 預設：`/run/user/${user_id}/podman/podman.sock`
  - rootful 預設：`/run/podman/podman.sock`
  - 若上游程式只認 Docker socket 路徑（`/var/run/docker.sock`），可直接把 Podman socket 掛上去（Podman 的 Docker 相容 API，不是 Docker daemon）：
    - `Volume=${podman_sock_host_path}:/var/run/docker.sock`
- 若需要在提示/腳本中辨識模式，可用：`${tgdb_deploy_mode}`（rootless/rootful）與 `${tgdb_scope}`（user/system）

### 3.3 安全預設

遵守保守預設：
- `PublishPort` 優先綁 `127.0.0.1`
- 預設關閉高風險功能（例如公開註冊）
- 機敏值放 `.env` 並設定 `mode=600`
- 對外訪問建議走 Nginx/HTTPS 反向代理
- rootful 預設仍偏保守；但若此 App 明確就是『硬體/局域網探測』類（例如家庭自動化），也可以在 rootful 範本中直接預設開啟必要權限/掛載（`Network=host`、`--privileged`、`/dev`、`/run/udev` 等），並在 `success_warn` 做醒目風險提醒（僅建議內網/回環、確認防火牆/反代策略）。

## 步驟 4：進階應用方案（不適合 AppSpec 時）

不要直接硬塞 AppSpec。先提供：
- 不適合原因（對應實際流程限制）
- 建議模組位置（例如 `src/advanced/<module>-p.sh`）
- 與既有功能的整合點（路由、CLI、設定檔）
- 最小可行實作範圍與風險

## 步驟 5：驗證

完成後至少執行以下檢查：

```bash
# 服務合法性
bash -lc 'source src/apps-p.sh >/dev/null 2>&1; _apps_service_is_valid <service> && echo valid'

# 可被 Apps 清單探索
bash -lc 'source src/apps-p.sh >/dev/null 2>&1; _apps_list_services | grep -n "^<service>$"'

# AppSpec 渲染 smoke test（prepare + render；rootless）
bash -lc 'set -e; source src/apps-p.sh >/dev/null 2>&1; \
  tmpi=$(mktemp -d /tmp/tgdb_<service>_instance.XXXXXX); \
  tmpu=$(mktemp -d /tmp/tgdb_<service>_units.XXXXXX); \
  _app_invoke <service> prepare_instance <name> <port> "$tmpi" >/dev/null; \
  _app_invoke <service> render_quadlet <name> <port> "$tmpi" none none "" "$tmpu" >/dev/null; \
  rm -rf "$tmpi" "$tmpu"'

# 若宣告支援 rootful，建議也做一次 rootful 渲染（不會真的寫 /etc；只是讓模板變數走 rootful 路徑）
bash -lc 'set -e; export TGDB_APPS_ACTIVE_DEPLOY_MODE=rootful TGDB_APPS_ACTIVE_SCOPE=system; \
  source src/apps-p.sh >/dev/null 2>&1; \
  tmpi=$(mktemp -d /tmp/tgdb_<service>_instance.XXXXXX); \
  tmpu=$(mktemp -d /tmp/tgdb_<service>_units.XXXXXX); \
  _app_invoke <service> prepare_instance <name> <port> "$tmpi" >/dev/null; \
  _app_invoke <service> render_quadlet <name> <port> "$tmpi" none none "" "$tmpu" >/dev/null; \
  rm -rf "$tmpi" "$tmpu"'
```

若本次只有新增設定檔，至少補做上述 smoke test。若有 shell 腳本變更，再跑：
- `bash scripts/lint-changed.sh --unstaged`
- 或針對變更檔執行 `bash -n` + `shellcheck`

## 步驟 6：回報格式

回報時固定包含：
- 決策：AppSpec 或進階應用
- 部署模式：rootless / rootful（若有）與原因
- 主要變更檔案
- 預設安全策略（埠綁定、註冊策略、敏感設定）
- 驗證結果（列出實際檢查項）
- 若未直接整合：給出下一步選項
