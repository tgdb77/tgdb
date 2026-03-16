spec_version=1
display_name=Conduit
image=registry.gitlab.com/famedly/conduit/matrix-conduit:latest
doc_url=https://docs.conduit.rs/deploying/docker.html
menu_order=54

base_port=6767
instance_subdirs=data
record_subdirs=data

cli_quick_args=server_name
input=server_name|prompt=請輸入 Matrix Server Name（例：matrix.example.com，輸入 0 取消）: |required=1|no_space=1|pattern=^[A-Za-z0-9.-]+(:[0-9]+)?$|pattern_msg=Server Name 格式不正確（允許網域或網域:埠號）。|env=CONDUIT_SERVER_NAME|allow_cancel=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=需使用前端應用訪問，例如：https://element.io/download。
success_warn=預設已關閉註冊（CONDUIT_ALLOW_REGISTRATION=false）；若要開放註冊請編輯 ${instance_dir}/.env 後再更新/重啟。

quadlet_type=single
quadlet_template=quadlet/default.container
