# 貢獻指南

感謝你願意協助改進 TGDB。

本專案以 Bash 為主，會涉及系統設定、Podman、Nginx、nftables、Fail2ban、備份與還原等操作。為了降低回歸風險，提交前請先閱讀並遵守以下規範。

## 開發環境建議

- 推薦使用 Debian 13 測試。
- 請使用具 `sudo` 權限的普通用戶進行開發與驗證。
- 建議在乾淨的 VM 或容器中測試安裝、升級、備份/還原與互動流程。

## 專案結構

- `tgdb.sh`：互動式主入口。
- `src/`：主要功能模組。
- `src/advanced/`：進階應用模組。
- `config/`：App Spec、預設設定與 Quadlet 範本。
- `scripts/`：開發輔助腳本，例如 lint。

請維持模組單一職責，避免把不相干的邏輯塞進同一支腳本。

## 程式風格

- 主要語言為 Bash。
- 縮排使用 2 空白，不使用 Tab。
- 函式命名使用小寫加底線，例如 `ensure_podman_ready`。
- 變數命名使用大寫加底線，例如 `TGDB_DIR`。
- 註解與使用者訊息請使用繁體中文。

## 提交前檢查

最低要求：

```bash
bash scripts/lint.sh
```

`scripts/lint.sh` 預設為快速模式，不追蹤 `source`，適合日常全量檢查；完整模式需要的 ShellCheck 設定已直接內嵌在腳本內。

日常開發若只想先檢查 Git 變更檔，可使用：

```bash
bash scripts/lint-changed.sh
```

若要做完整深度檢查（會追蹤 `source`，並自動收斂到受影響模組入口，耗時仍可能較久），可在需要時執行：

```bash
bash scripts/lint.sh --deep
```

若變更內容會影響系統狀態，也請補做情境測試，例如：

- 首次安裝
- 升級既有環境
- 還原備份
- Podman / Nginx / Rclone / nftables 相關流程

## Commit 與 Pull Request

Commit 訊息建議採用：

```text
feat: 新增 xxx
fix: 修正 xxx
docs: 更新 xxx
refactor: 調整 xxx
```

Pull Request 建議包含：

- 變更目的
- 主要調整檔案
- 驗證方式
- 若有 UI/互動流程變更，可附上終端輸出範例

## 安全注意事項

- 不要提交 `.env`、私鑰、憑證、Token、真實密碼或備份資料。
- 涉及 SSH、憑證、防火牆、Fail2ban、自動備份等邏輯時，請優先採保守預設值。
- 若變更可能導致遠端主機失聯，請先在測試環境驗證。
