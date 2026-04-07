spec_version=1
display_name=Frigate
image=ghcr.io/blakeblackshear/frigate:stable
doc_url=https://github.com/blakeblackshear/frigate
menu_order=125

access_policy=local_only

base_port=15757

instance_subdirs=config media
record_subdirs=config media

deploy_mode_default=rootful
compat_deploy_modes=rootful

var=rtsp_password|source=random_hex|len=20|env=FRIGATE_RTSP_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/config.yml|template=configs/config.yml.example|mode=600|label=config.yml

success_extra=🔐 預設帳號：admin
success_extra=🔐 預設密碼：${rtsp_password}
success_warn= 預設開啟額外埠： RTSP restreaming(18554) 、 WebRTC(18558) ，可根據需求調整。
success_warn= TGDB 預設僅綁 127.0.0.1（local_only）。若需要讓其他主機存取，請到 Quadlet 把 PublishPort 的 127.0.0.1 改成 0.0.0.0，並自行設定防火牆白名單。

quadlet_type=single
quadlet_template=quadlet/default.container
