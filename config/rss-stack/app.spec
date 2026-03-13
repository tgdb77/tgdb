spec_version=1
display_name=FreshRSS + RSSHub
image=docker.io/freshrss/freshrss:latest
doc_url=https://github.com/FreshRSS/FreshRSS & https://github.com/DIYgod/RSSHub
menu_order=43

base_port=3410

instance_subdirs=freshrss_data freshrss_extensions
record_subdirs=freshrss_data freshrss_extensions

touch_files=freshrss_data/config.custom.php freshrss_data/config-user.custom.php

cli_quick_args=rsshub_port

input=rsshub_port|prompt=請輸入 RSSHub 對外埠（預設 3411；輸入 0 取消）: |required=1|ask=1|type=port|default=3411|avoid=host_port|check_available=1|env=RSSHUB_PORT|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ RSSHub：http://127.0.0.1:${rsshub_port}
success_warn= 若以域名反代 FreshRSS，請依官方文件調整反代/URL 設定（避免跳轉或 URL 生成不正確）。

quadlet_type=multi
unit=pod|template=quadlet/default.pod|suffix=.pod
unit=freshrss|template=quadlet/default.container|suffix=.container
unit=rsshub|template=quadlet/default2.container|suffix=-rsshub.container

update_pull_images=docker.io/freshrss/freshrss:latest
update_pull_images=docker.io/diygod/rsshub:latest
