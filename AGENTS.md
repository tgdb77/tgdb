# Repository Guidelines

本文件說明在本倉庫進行開發與貢獻時的基本規範，請在提交變更前完整閱讀。

## 專案結構與模組

- `tgdb.sh`：互動式主入口腳本。
- `src/`：主要功能模組（核心/系統/Apps 等）；進階應用集中於 `src/advanced/`（例如 `nginx-p.sh`、`rclone.sh`、`headscale-p.sh` 等）。
- `config/`：服務預設設定與 Quadlet 範本（Nginx、OpenList、Teldrive、utils 等）。
- `plan/`：規劃與協調相關檔案（本文件即位於此倉庫根目錄）。

請維持功能模組單一職責，避免將無關邏輯塞入同一腳本。

## 建置、測試與開發

- 本專案無編譯流程，確保腳本具可執行權限：`chmod +x tgdb.sh src/*.sh src/advanced/*.sh src/system/*.sh scripts/*.sh`。
- 本地執行主程式：`./tgdb.sh`。
- 建議在乾淨的測試 VM 或容器中驗證：安裝、選單操作、備份/還原與 Podman/Nginx/Rclone 功能。

## 程式風格與命名

- 主要語言為 Bash；縮排以 2 空白為主，不使用 Tab。
- 函式命名採用小寫加底線，例如：`create_tgdb_dir`、`ensure_podman_ready`。
- 變數命名使用大寫加底線，例如：`TGDB_DIR`、`BACKUP_MAX_COUNT`。
- 所有註解與使用者訊息請使用繁體中文，保持語氣一致且具體。

## 測試與驗證

- 目前未使用自動化測試框架，請以「情境測試」為主（例如：首次安裝、升級版本、還原備份）。
- 靜態檢查請優先使用：`bash scripts/lint.sh`（內含 `bash -n` + `shellcheck`）。
- 日常開發可先執行：`bash scripts/lint-changed.sh`（僅檢查 Git 變更檔；支援 `--cached` / `--unstaged`）。
- 最低要求：`bash -n` 與 `shellcheck` 無報錯。
- 若完整 lint 在當前環境耗時過長，至少需先對「本次變更檔案」執行 `bash -n` 與 `shellcheck`，再進行提交。
- 影響系統的操作（apt、systemctl、nginx/podman 變更）請先在測試環境驗證。
- 若修正錯誤，請在提交描述中說明重現步驟與驗證方式。

## Commit 與 Pull Request 規範

- Commit 訊息建議包含類型與簡要說明，例如：`feat: 新增 Rclone 掛載選項`、`fix: 修正 Nginx 配置路徑`。
- 每個 PR 應：
  - 說明變更目的與主要調整檔案。
  - 標註相關 Issue 或需求背景。
  - 如涉及互動流程或輸出變更，可附上終端輸出截圖或範例。

## 安全與設定建議

- 變更與網路、安全（nftables、Fail2ban、憑證、自動備份）相關程式碼時，避免預設開啟高風險選項。
- 所有預設值應偏向保守，可透過設定檔調整；請在 README 或相關模組加入清楚說明。
