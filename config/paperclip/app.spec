spec_version=1
display_name=Paperclip
image=ghcr.io/paperclipai/paperclip:latest
doc_url=https://github.com/paperclipai/paperclip
menu_order=197

access_policy=local_only

base_port=3115
instance_subdirs=data
record_subdirs=data

var=better_auth_secret|source=random_hex|len=64|env=BETTER_AUTH_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env

post_deploy=scripts/post_deploy_onboard_restart.sh|runner=bash|allow_fail=0

success_extra=ℹ️ 產生管理員邀請連結須執行：podman exec -it --user node ${container_name} bash -lc 'cd /app && pnpm paperclipai auth bootstrap-ceo --data-dir "$PAPERCLIP_HOME"'
success_extra=ℹ️ 若要接入 LLM，請編輯 ${instance_dir}/.env 補上對應 API Key 後重啟。
success_warn= 若你之後改成自訂域名或 HTTPS，請先把 ${instance_dir}/.env 的 PAPERCLIP_PUBLIC_URL 改成最終網址，再執行更新 / 重啟，避免登入回呼或分享連結異常。

quadlet_type=single
quadlet_template=quadlet/default.container
