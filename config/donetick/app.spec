spec_version=1
display_name=Donetick
image=docker.io/donetick/donetick:latest
doc_url=https://github.com/donetick/donetick
menu_order=103

base_port=2026

instance_subdirs=config data
record_subdirs=config data

var=jwt_secret|source=random_hex|len=32

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/selfhosted.yaml|template=configs/selfhosted.yaml.example|mode=600|label=selfhosted.yaml

success_extra=ℹ️ 請盡速創建初始用戶。
success_warn=若你要透過反向代理、網域、行動裝置或 OAuth 使用 Donetick，請編輯 ${instance_dir}/config/selfhosted.yaml 的 server.public_host 與 oauth2 設定後再重啟。

quadlet_type=single
quadlet_template=quadlet/default.container
