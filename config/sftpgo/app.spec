spec_version=1
display_name=SFTPGo
image=docker.io/drakkan/sftpgo:latest
doc_url=https://github.com/drakkan/sftpgo
menu_order=131

base_port=8980

uses_volume_dir=1
volume_dir_prompt=SFTPGo 資料目錄
volume_subdirs=data backups

instance_subdirs=varlib
record_subdirs=varlib

cli_quick_args=volume_dir sftp_port
input=sftp_port|prompt=請輸入 SFTP 對外埠（預設 2022，輸入 0 取消）: |required=1|ask=1|type=port|default=2022|check_available=1|env=SFTPGO_SFTP_PORT|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=🌐 Web UI： http://127.0.0.1:${host_port}/web/admin
success_extra=📡 SFTP 連線埠：${sftp_port}
success_warn= 首次啟動後請到 /web/admin 建立第一個管理員帳號，並設定使用者/金鑰/權限。

quadlet_type=single
quadlet_template=quadlet/default.container
