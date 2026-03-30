spec_version=1
display_name=Termix
image=ghcr.io/lukegus/termix:latest
doc_url=https://docs.termix.site/install/server/docker
menu_order=102

base_port=14090
access_policy=local_only

instance_subdirs=data
record_subdirs=data

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn=請勿在不清楚風險情況下，暴露本應用到公網訪問。
success_warn=若要反向代理或 HTTPS 網域，請做好防護並依需求編輯 ${instance_dir}/.env 內的 OIDC_FORCE_HTTPS、SSL_ENABLED 與 VITE_BASE_PATH。

quadlet_type=single
quadlet_template=quadlet/default.container
