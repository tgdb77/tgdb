spec_version=1
display_name=LibreTranslate
image=docker.io/libretranslate/libretranslate:latest
doc_url=https://docs.libretranslate.com/guides/installation/
menu_order=86

base_port=3456

access_policy=local_only

uses_volume_dir=1
volume_dir_prompt=LibreTranslate 模型資料目錄
volume_subdirs=models

cli_quick_args=volume_dir

instance_subdirs=db
record_subdirs=db

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ API Keys 資料庫：${instance_dir}/db/api_keys.db（啟用 LT_API_KEYS 時）
success_warn=首次啟動通常會下載語言模型，時間與磁碟用量取決於你啟用的語言；若想增加語言支持，建議在 ${instance_dir}/.env 設定 LT_LOAD_ONLY（例如：en,zh）並視需要啟用 LT_UPDATE_MODELS。
success_warn=此服務容易被濫用造成資源耗盡；若要對外提供，建議至少啟用 LT_API_KEYS 並設定 LT_REQ_LIMIT / LT_CHAR_LIMIT，並透過反向代理加上驗證與 HTTPS，避免直接暴露到公網。

quadlet_type=single
quadlet_template=quadlet/default.container

