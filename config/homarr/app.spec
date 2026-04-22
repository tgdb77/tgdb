spec_version=1
display_name=Homarr
image=ghcr.io/homarr-labs/homarr:latest
doc_url=https://homarr.dev/docs/next/getting-started/installation/portainer/
menu_order=170

access_policy=local_only

base_port=37557
instance_subdirs=appdata
record_subdirs=appdata

var=secret_encryption_key|source=random_hex|len=64|env=SECRET_ENCRYPTION_KEY

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 首次啟動後請前往 ${http_url} 完成初始設定與建立第一個管理員。
success_warn=若你要在 Homarr 裡串接影音全家桶服務，請使用 TGDB 的 3xxxx 主機側埠，並在容器內一律填 host.containers.internal。
success_warn=若要讓 Homarr 讀取容器狀態，需在 ${container_name}.container 取消註解 docker/podman socket 掛載，或依官方文件改用 socket proxy；這會提高權限風險，請只在可信任環境使用。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/homarr-labs/homarr:latest
