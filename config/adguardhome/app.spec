spec_version=1
display_name=AdGuard Home
image=docker.io/adguard/adguardhome:v0.107.74
doc_url=https://github.com/AdguardTeam/AdGuardHome
menu_order=7

access_policy=local_only

base_port=3333
instance_subdirs=data conf
record_subdirs=data conf

quadlet_type=single
quadlet_template=quadlet/default.container
update_pull_images=docker.io/adguard/adguardhome:latest

