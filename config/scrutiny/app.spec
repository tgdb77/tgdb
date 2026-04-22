spec_version=1
display_name=Scrutiny
image=ghcr.io/analogj/scrutiny:v0.8.6-omnibus
doc_url=https://github.com/AnalogJ/scrutiny
menu_order=184

access_policy=local_only

base_port=8087
instance_subdirs=config influxdb
record_subdirs=config influxdb

deploy_mode_default=rootful
compat_deploy_modes=rootful

config=.env|template=configs/.env.example|mode=600|label=.env

success_extra=ℹ️ Omnibus 模式會內建 collector；首次啟動後通常要等第一輪掃描完成才會看到磁碟資料。
success_warn= 若你的主機有 NVMe / RAID / HBA / USB-SATA bridge，或 `smartctl --scan` 顯示特殊裝置，可能仍需依官方文件進一步調整裝置映射與 collector 設定；這裡先提供可運作的保守高權限範本。
success_warn= 預設不額外公開 InfluxDB 管理埠。若真的需要請自行編輯 Quadlet 加上 PublishPort。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=ghcr.io/analogj/scrutiny:v0.8.6-omnibus
