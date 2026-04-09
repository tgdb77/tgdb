spec_version=1
display_name=Browserless
image=ghcr.io/browserless/chromium:latest
doc_url=https://github.com/browserless/browserless
menu_order=142

base_port=3005

access_policy=local_only

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

var=token|source=random_hex|len=32|env=TOKEN

success_extra=🔑 API Token：${token}
success_extra=ℹ️ WebSocket 端點：ws://127.0.0.1:${host_port}?token=${token}
success_extra=ℹ️ Debugger 列表：${http_url}/json/version?token=${token}
success_extra=ℹ️ 詳細看文件：${http_url}:${host_port}/docs
success_warn=此服務相當吃 CPU / RAM / /dev/shm；若併發量過高，可能造成瀏覽器啟動失敗、OOM 或整機負載升高。請依主機資源調整 .env 內的併發與逾時設定。

quadlet_type=single
quadlet_template=quadlet/default.container
