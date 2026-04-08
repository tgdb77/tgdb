spec_version=1
display_name=Vane
image=docker.io/itzcrazykns1337/vane:latest
doc_url=https://github.com/ItzCrazyKns/Vane
menu_order=136

access_policy=local_only

base_port=3077

instance_subdirs=data
record_subdirs=data

success_warn= 若你要串接同機的 Ollama，Linux 環境通常不能直接用 127.0.0.1，請依官方文件改填宿主機的私網 IP 或可達位址。
success_warn= 目前上游尚未提供內建認證；若要公開到外網，建議搭配 Nginx/HTTPS 與額外存取控制。

quadlet_type=single
quadlet_template=quadlet/default.container
