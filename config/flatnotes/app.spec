spec_version=1
display_name=Flatnotes
image=docker.io/dullage/flatnotes:latest
doc_url=https://github.com/dullage/flatnotes
menu_order=151

base_port=8217

uses_volume_dir=1
volume_dir_prompt=Flatnotes 筆記資料目錄
cli_quick_args=volume_dir admin_user admin_pass

input=admin_user|prompt=請輸入 Flatnotes 管理員帳號（預設 user，輸入 0 取消）: |required=1|ask=1|default=user|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=FLATNOTES_USERNAME|allow_cancel=1
input=admin_pass|prompt=請輸入 Flatnotes 管理員密碼（直接按 Enter 使用強密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=strong_password|len=20|no_space=1|env=FLATNOTES_PASSWORD|allow_cancel=1

var=secret_key|source=random_hex|len=32|env=FLATNOTES_SECRET_KEY

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}
success_extra=📁 筆記目錄：${volume_dir}
success_warn=Flatnotes 會直接把 Markdown 筆記存進 ${volume_dir}，並把搜尋索引放在同目錄下的 `.flatnotes/`；若你會用其他工具同步或修改檔案，建議先確認該隱藏目錄也會被妥善保留。
success_warn=若要改成唯讀或完全不登入模式，可編輯 ${instance_dir}/.env 的 `FLATNOTES_AUTH_TYPE` 為 `read_only` 或 `none` 後重啟；若要啟用 2FA，請改成 `totp` 並補上 `FLATNOTES_TOTP_KEY`。
success_warn=若之後改成域名 / HTTPS / 反向代理，請同步調整 ${instance_dir}/.env 的 `NEXT_PUBLIC_APP_URL`（若你自行加上）與反代設定；TGDB 預設僅綁定 127.0.0.1。

quadlet_type=single
quadlet_template=quadlet/default.container
