spec_version=1
display_name=copyparty
image=docker.io/copyparty/ac:latest
doc_url=https://github.com/9001/copyparty
menu_order=175

base_port=3929
instance_subdirs=cfg hist
record_subdirs=cfg hist

uses_volume_dir=1
volume_dir_prompt=檔案分享目錄
cli_quick_args=volume_dir admin_user admin_pass

input=admin_user|prompt=請輸入 copyparty 管理員帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=COPYPARTY_ADMIN_USER|allow_cancel=1
input=admin_pass|prompt=請輸入 copyparty 管理員密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|ask=1|type=password|default_source=random_hex|len=24|no_space=1|env=COPYPARTY_ADMIN_PASSWORD|allow_cancel=1

config=cfg/copyparty.conf|template=configs/copyparty.conf.example|mode=600|label=copyparty.conf

success_extra=🔐 管理員帳號：${admin_user}
success_extra=🔐 管理員密碼：${admin_pass}
success_extra=ℹ️ 預設只有管理員可登入與上傳/下載；不開放匿名訪問。
success_warn= 若你之後改成域名或 HTTPS 反代，請確認反向代理會正確送出 `X-Forwarded-Proto: https`，否則 copyparty 可能誤判自己仍在 HTTP。
success_warn= copyparty 功能非常多（WebDAV / FTP / TFTP / 媒體索引 / 縮圖等）；TGDB 這裡只做保守的 Web 檔案分享預設。若你要開更多功能，請編輯 ${instance_dir}/cfg/copyparty.conf。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/copyparty/ac:latest
