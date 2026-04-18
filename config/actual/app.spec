spec_version=1
display_name=Actual Budget
image=docker.io/actualbudget/actual-server:latest
doc_url=https://actualbudget.org/docs/install/docker/
menu_order=166

base_port=5666

instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 首次啟動後請盡速設定伺服器密碼，再建立或匯入第一份預算檔。
success_warn= 若之後要啟用 header / OpenID 登入，請編輯 ${instance_dir}/.env 並依官方文件同步檢查 trusted proxies / trusted auth proxies 設定。
success_warn= 若要透過自訂域名或 HTTPS 反代，建議走 TGDB 的 Nginx/HTTPS，並在啟用進階登入方式前先完成反代與信任代理設定，避免認證被錯誤放大。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/actualbudget/actual-server:latest
