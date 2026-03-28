spec_version=1
display_name=OctoBot
image=docker.io/drakkarsoftware/octobot:stable
doc_url=https://www.octobot.cloud/en/guides/octobot-installation/install-octobot-with-docker-video
menu_order=89

base_port=3458

access_policy=local_only

instance_subdirs=user tentacles logs backtesting
record_subdirs=user tentacles logs backtesting

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=交易機器人有資金風險，請先用模擬/紙上交易熟悉設定，再評估是否要接入真實資金與 API 權限。
success_warn=強烈建議僅本機訪問（127.0.0.1）；若必須遠端使用，請走 HTTPS 反向代理並加上驗證，避免直接暴露到公網。

quadlet_type=single
quadlet_template=quadlet/default.container

