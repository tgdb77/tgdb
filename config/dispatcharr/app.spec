spec_version=1
display_name=Dispatcharr
image=ghcr.io/dispatcharr/dispatcharr:latest
doc_url=https://github.com/Dispatcharr/Dispatcharr
menu_order=200

access_policy=local_only

base_port=9003
instance_subdirs=data
record_subdirs=data

var=postgres_password|source=random_hex|len=32|env=POSTGRES_PASSWORD

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn= 若你要啟用 VA-API / NVIDIA 等硬體加速，需另外調整 Quadlet 的 devices / GPU 設定，建議先在測試環境驗證。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/dispatcharr/dispatcharr:latest
