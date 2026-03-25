spec_version=1
display_name=Yt-Dlp WebUI
image=docker.io/marcobaobao/yt-dlp-webui:latest
doc_url=https://hub.docker.com/r/marcobaobao/yt-dlp-webui
menu_order=82

base_port=3303

instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
volume_dir_prompt=下載目錄

cli_quick_args=volume_dir user_name pass_word

input=user_name|prompt=請輸入 yt-dlp-webui 帳號（預設 admin，輸入 0 取消）: |required=1|ask=1|default=admin|no_space=1|pattern=^[A-Za-z0-9._-]+$|pattern_msg=僅可使用英數、點、底線與連字號。|env=YTDLP_WEBUI_USERNAME|allow_cancel=1
input=pass_word|prompt=請輸入 yt-dlp-webui 密碼（直接按 Enter 使用隨機密碼，輸入 0 取消）: |required=1|type=password|no_space=1|ask=1|default_source=random_hex|len=32|env=YTDLP_WEBUI_PASSWORD|allow_cancel=1

var=jwt_secret|source=random_hex|len=64|env=YTDLP_WEBUI_JWT_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）
config=config/config.yml|template=configs/config.yml.example|mode=600|label=config.yml（應用設定）

success_extra=🔐 帳號：${user_name}
success_extra=🔐 密碼：${pass_word}
success_extra=📚 API 文件：${http_url}/openapi

quadlet_type=single
quadlet_template=quadlet/default.container

