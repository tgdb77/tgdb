spec_version=1
display_name=qBittorrent
image=lscr.io/linuxserver/qbittorrent:latest
doc_url=https://github.com/linuxserver/docker-qbittorrent
menu_order=22

base_port=8998
instance_subdirs=config
record_subdirs=config

uses_volume_dir=1
cli_quick_args=volume_dir
volume_dir_prompt=下載目錄

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

success_extra=ℹ️ 下載輸出：已掛載 ${volume_dir} 到容器 /downloads。
success_warn=傳輸提醒：請確保已放行 6881/TCP 與 6881/UDP（防火牆/安全群組/NAT 轉發），否則 BT 傳輸可能無法正常連線。
success_warn=首次登入帳號為：admin，密碼需要使用「查看單元日誌」確認並且在登入後必須更改。

quadlet_type=single
quadlet_template=quadlet/default.container
