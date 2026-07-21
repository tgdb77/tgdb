spec_version=1
cli_quick_args=none
display_name=AdGuard Home
description=DNS 過濾服務，可在網路層封鎖廣告、追蹤器與不想要的網域請求。
image=docker.io/adguard/adguardhome:latest
doc_url=https://github.com/AdguardTeam/AdGuardHome
menu_order=7

access_policy=local_only

base_port=3333
instance_subdirs=data conf
record_subdirs=data conf

config=.env|template=configs/.env.example|mode=600|label=.env

quadlet_type=single
quadlet_template=quadlet/default.container
update_pull_images=docker.io/adguard/adguardhome:latest
