spec_version=1
cli_quick_args=none
display_name=Crucix
description=多來源情報監控工具，可追蹤公開資料變化並在事件符合條件時提醒。
image=ghcr.io/calesthio/crucix:latest
doc_url=https://github.com/calesthio/Crucix
menu_order=203

access_policy=local_only

base_port=3110
instance_subdirs=runs
record_subdirs=runs

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=Crucix 首次啟動後會先進行一次完整情報 sweep，通常需 30–60 秒才會看到資料；若未填 API 金鑰，部分來源會自動降級或無資料，請視需要編輯 ${instance_dir}/.env。

quadlet_type=single
quadlet_template=quadlet/default.container
