spec_version=1
display_name=Ollama
image=docker.io/ollama/ollama:latest
doc_url=https://github.com/ollama/ollama
menu_order=46

base_port=13434
access_policy=local_only

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Ollama 模型資料目錄（建議使用大容量磁碟）

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

post_deploy=scripts/post_deploy_model_hint.sh|runner=bash|allow_fail=1

success_warn=若要讓前端（例如 Open WebUI）跨來源呼叫，請在 ${instance_dir}/.env 設定 OLLAMA_ORIGINS 後重啟服務。

quadlet_type=single
quadlet_template=quadlet/default.container
