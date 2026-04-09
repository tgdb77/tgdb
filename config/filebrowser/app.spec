spec_version=1
display_name=FileBrowser Quantum
image=docker.io/gtstef/filebrowser:stable
doc_url=https://github.com/gtsteffaniak/filebrowser
menu_order=143

base_port=1800

uses_volume_dir=1
cli_quick_args=volume_dir admin_user admin_password
volume_dir_prompt= FileBrowser 資料目錄

instance_subdirs=data
record_subdirs=data

input=admin_user|prompt=請輸入 FileBrowser 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|allow_cancel=1
input=admin_password|prompt=請輸入 FileBrowser 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|ask=1|default_source=random_hex|len=24|min_len=5|no_space=1|env=FILEBROWSER_ADMIN_PASSWORD|allow_cancel=1

var=jwt_token_secret|source=random_hex|len=64|env=FILEBROWSER_JWT_TOKEN_SECRET
var=totp_secret|source=random_hex|len=64|env=FILEBROWSER_TOTP_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config.yaml|template=configs/config.yaml.example|mode=600|label=config.yaml

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_password}
success_warn=請避免把 `/`、`/var` 或其他過大的系統路徑直接掛進 FileBrowser；建議只掛你真正要管理的子目錄。

quadlet_type=single
quadlet_template=quadlet/default.container
