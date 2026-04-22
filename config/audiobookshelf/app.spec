spec_version=1
display_name=Audiobookshelf
image=ghcr.io/advplyr/audiobookshelf:latest
doc_url=https://www.audiobookshelf.org/docs
menu_order=188

base_port=3378
instance_subdirs=config metadata
record_subdirs=config metadata

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=Audiobookshelf 媒體資料根目錄
volume_subdirs=audiobooks podcasts ebooks

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ 首次登入後，請在 Audiobookshelf 內把媒體庫路徑指向 /library/audiobooks、/library/podcasts 或 /library/ebooks。
success_warn=建議對外存取時走 Nginx / HTTPS 反向代理；若未使用反代，請勿直接把服務公開到網際網路。

quadlet_type=single
quadlet_template=quadlet/default.container
